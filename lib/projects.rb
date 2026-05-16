require "digest"
require "json"

# Handles directory-level concerns: listing projects and sessions, resolving
# safe file paths. No parsing of record contents happens here.
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
        size_bytes: File.size(path),
        modified_at: File.mtime(path).utc.iso8601
      }
    end.sort_by { |s| s[:modified_at] }.reverse
  end

  # Returns the absolute path to a session file, or nil if not found or
  # if the resolved path would escape data_root (path traversal guard).
  def session_path(data_root, project_id, session_id)
    dir = safe_project_dir(data_root, project_id)
    return nil unless dir
    return nil unless safe_filename?(session_id)

    path = File.join(dir, "#{session_id}.jsonl")
    File.exist?(path) ? path : nil
  end

  # private helpers ──────────────────────────────────────────────────────

  def safe_project_dir(data_root, project_id)
    return nil if project_id.nil? || project_id.empty?
    return nil if project_id.include?("\0")

    canonical_root = File.expand_path(data_root)
    candidate = File.expand_path(File.join(canonical_root, project_id))

    # Must stay inside data_root
    return nil unless candidate.start_with?("#{canonical_root}/")
    return nil unless File.directory?(candidate)

    candidate
  end

  def safe_filename?(name)
    # Session IDs are UUIDs; allow hex chars and dashes only
    !name.nil? && name.match?(/\A[0-9a-f\-]+\z/i)
  end

  def session_files(dir)
    Dir.glob(File.join(dir, "*.jsonl")).sort
  end

  # Peek at the first record in any session file that carries a cwd field.
  # This gives us the real project path rather than an approximate decode.
  def cwd_from_files(files)
    files.each do |path|
      File.foreach(path) do |line|
        record = JSON.parse(line.strip)
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
    # Strip leading "-" then replace remaining "-" with "/"
    "/#{encoded.sub(/\A-/, "").gsub("-", "/")}"
  end
end
