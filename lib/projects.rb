require "json"
require "time"

# Handles directory-level concerns: listing projects and sessions, resolving
# safe file paths. cwd_from_files peeks at session records to find the real
# project path, but no turn-level parsing happens here.
module Projects
  module_function

  # Returns array of project hashes for every subdirectory that contains
  # at least one top-level .jsonl session file.
  def list(data_root)
    return [] unless Dir.exist?(data_root)

    Dir.children(data_root).filter_map do |entry|
      dir = File.join(data_root, entry)
      next unless File.directory?(dir)

      files = session_files(dir)
      next if files.empty?

      {
        id: entry,
        display_name: cwd_from_files(files) || decode_dir_name(entry),
        session_count: files.length,
        last_active: files.map { |f| File.mtime(f) }.max.utc.iso8601
      }
    end.sort_by { |p| p[:last_active] }.reverse
  end

  # Returns lightweight metadata for each session in the project,
  # sorted newest first. Returns nil if the project doesn't exist.
  def sessions(data_root, project_id)
    dir = safe_project_dir(data_root, project_id)
    return nil unless dir

    session_files(dir).map do |path|
      {
        id: File.basename(path, ".jsonl"),
        project_id: project_id,
        title: title_from_file(path),
        size_bytes: File.size(path),
        modified_at: File.mtime(path).utc.iso8601
      }
    end.sort_by { |s| s[:modified_at] }.reverse
  end

  # Returns the absolute real path to a session file, or nil if not found or
  # if the resolved path (after symlink expansion) would escape data_root.
  def session_path(data_root, project_id, session_id)
    dir = safe_project_dir(data_root, project_id)
    return nil unless dir
    return nil unless safe_filename?(session_id)

    path = File.join(dir, "#{session_id}.jsonl")
    return nil unless File.exist?(path)

    canonical_root = File.realpath(data_root)
    real_path = File.realpath(path)
    return nil unless real_path.start_with?("#{canonical_root}/")

    real_path
  rescue Errno::ENOENT, Errno::EACCES
    nil
  end

  # private helpers ──────────────────────────────────────────────────────

  def safe_project_dir(data_root, project_id)
    return nil if project_id.nil? || project_id.empty?
    return nil if project_id.include?("\0")

    canonical_root = File.realpath(data_root)
    candidate = File.expand_path(File.join(canonical_root, project_id))

    # Pre-realpath prefix check rejects obvious traversal attempts
    return nil unless candidate.start_with?("#{canonical_root}/")
    return nil unless File.directory?(candidate)

    # Resolve symlinks and verify the real path is still inside data_root
    real_candidate = File.realpath(candidate)
    return nil unless real_candidate.start_with?("#{canonical_root}/")

    real_candidate
  rescue Errno::ENOENT, Errno::EACCES
    nil
  end

  def safe_filename?(name)
    # Session IDs are UUIDs; allow hex chars and dashes only
    !name.nil? && name.match?(/\A[0-9a-f\-]+\z/i)
  end

  def session_files(dir)
    Dir.glob(File.join(dir, "*.jsonl")).sort
  end

  # Peek at the first few records of any session file to find a cwd field.
  # Bounded to avoid scanning large files when cwd appears early (it always does).
  def cwd_from_files(files, limit: 10)
    files.each do |path|
      count = 0
      File.foreach(path, encoding: "utf-8") do |line|
        break if (count += 1) > limit

        record = JSON.parse(line.strip)
        next unless record.is_a?(Hash)

        cwd = record["cwd"]
        return cwd if cwd && !cwd.empty?
      rescue JSON::ParserError
        next
      end
    end
    nil
  end

  # Fallback: the encoded dir name replaces "/" with "-".
  # This is lossy (can't distinguish path separator from literal dash)
  # but good enough when cwd isn't available.
  def decode_dir_name(encoded)
    "/#{encoded.sub(/\A-/, "").gsub("-", "/")}"
  end

  # Claude writes an {"type":"ai-title","aiTitle":"..."} record once it has
  # summarized the session, and re-writes it as the conversation evolves.
  # Returns the most recent non-empty title found, or nil if there is none.
  # The substring guard skips JSON parsing on the vast majority of lines.
  def title_from_file(path)
    title = nil
    File.foreach(path, encoding: "utf-8") do |line|
      next unless line.include?(%("type":"ai-title"))
      record = JSON.parse(line.strip)
      next unless record.is_a?(Hash)
      candidate = record["aiTitle"]
      title = candidate if candidate.is_a?(String) && !candidate.empty?
    rescue JSON::ParserError
      next
    end
    title
  rescue Errno::ENOENT, Errno::EACCES
    nil
  end
end
