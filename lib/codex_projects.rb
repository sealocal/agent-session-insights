require "json"
require "time"
require "base64"
require_relative "codex_session_index"

# Codex stores sessions in date-partitioned directories under
# ~/.codex/sessions/YYYY/MM/DD/, not per-project directories. We derive
# "projects" by reading the session_meta record (always the first line of
# each rollout file) and grouping by its cwd.
#
# Project IDs are url-safe base64(cwd) — opaque but reversible — to keep
# them URL-safe without introducing a separate lookup table.
module CodexProjects
  module_function

  def list(data_root)
    return [] unless Dir.exist?(data_root)

    grouped = scan_sessions(data_root).group_by { |s| s[:cwd] }

    grouped.filter_map do |cwd, sessions|
      next if cwd.nil? || cwd.empty?
      {
        id: encode_project_id(cwd),
        display_name: cwd,
        session_count: sessions.length,
        last_active: sessions.map { |s| s[:mtime] }.max.utc.iso8601
      }
    end.sort_by { |p| p[:last_active] }.reverse
  end

  def sessions(data_root, project_id)
    cwd = decode_project_id(project_id)
    return nil unless cwd

    matches = scan_sessions(data_root).select { |s| s[:cwd] == cwd }
    return nil if matches.empty?

    renames = CodexSessionIndex.titles
    matches.map { |s|
      {
        id: s[:session_id],
        project_id: project_id,
        title: renames[s[:session_id]] || title_from_file(s[:path]),
        size_bytes: File.size(s[:path]),
        modified_at: s[:mtime].utc.iso8601
      }
    }.sort_by { |s| s[:modified_at] }.reverse
  end

  def session_path(data_root, project_id, session_id)
    cwd = decode_project_id(project_id)
    return nil unless cwd
    return nil unless safe_filename?(session_id)

    canonical_root = File.realpath(data_root)

    scan_sessions(data_root).each do |s|
      next unless s[:session_id] == session_id && s[:cwd] == cwd
      real_path = File.realpath(s[:path])
      return real_path if real_path.start_with?("#{canonical_root}/")
    end
    nil
  rescue Errno::ENOENT, Errno::EACCES
    nil
  end

  # private helpers ──────────────────────────────────────────────────────

  # Walks the date-partitioned tree once and returns a flat array of
  # session metadata. Reads only the first line of each .jsonl to pull
  # session_meta (cwd, id). Sessions without a parseable session_meta on
  # line 1 are skipped.
  def scan_sessions(data_root)
    Dir.glob(File.join(data_root, "**", "*.jsonl")).filter_map do |path|
      meta = read_session_meta(path)
      next unless meta

      {
        path: path,
        cwd: meta["cwd"],
        session_id: meta["id"] || filename_session_id(path),
        mtime: File.mtime(path)
      }
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end
  end

  def read_session_meta(path)
    File.open(path, "r:utf-8") do |io|
      line = io.gets
      return nil unless line
      record = JSON.parse(line.strip)
      return nil unless record.is_a?(Hash) && record["type"] == "session_meta"
      record["payload"].is_a?(Hash) ? record["payload"] : nil
    end
  rescue JSON::ParserError
    nil
  end

  # rollout-2025-10-20T14-53-34-<uuid>.jsonl → <uuid>
  def filename_session_id(path)
    name = File.basename(path, ".jsonl")
    name.match(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\z/i)&.[](1) || name
  end

  def encode_project_id(cwd)
    Base64.urlsafe_encode64(cwd, padding: false)
  end

  def decode_project_id(project_id)
    return nil if project_id.nil? || project_id.empty?
    return nil unless project_id.match?(/\A[A-Za-z0-9_-]+\z/)
    Base64.urlsafe_decode64(project_id)
  rescue ArgumentError
    nil
  end

  def safe_filename?(name)
    !name.nil? && name.match?(/\A[0-9a-f-]+\z/i)
  end

  # Codex has no explicit title field; the first user message is a clean stand-in.
  # Scan until we hit the first event_msg/user_message — typically within ~10 lines.
  # The substring guard skips JSON parsing on the vast majority of records.
  def title_from_file(path)
    File.foreach(path, encoding: "utf-8") do |line|
      next unless line.include?(%("type":"user_message"))
      record = JSON.parse(line.strip)
      next unless record.is_a?(Hash)
      text = record.dig("payload", "message")
      next unless text.is_a?(String)
      stripped = text.strip
      next if stripped.empty?
      return (stripped.length > 140) ? "#{stripped[0, 140]}…" : stripped
    rescue JSON::ParserError
      next
    end
    nil
  rescue Errno::ENOENT, Errno::EACCES
    nil
  end
end
