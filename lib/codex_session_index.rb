require "json"

# Codex stores user-renamed session titles in a sidecar index at
# ~/.codex/session_index.jsonl — one record per session with id and
# thread_name. The rollout file itself is not rewritten on rename, so this
# index is the source of truth for the display title.
#
# Configurable via CODEX_SESSION_INDEX. Returns an empty Hash when the
# file is absent or unreadable so callers can fall back to a derived title.
module CodexSessionIndex
  module_function

  def default_path
    ENV.fetch("CODEX_SESSION_INDEX") do
      File.join(Dir.home, ".codex", "session_index.jsonl")
    end
  end

  def titles(path = default_path)
    return {} unless File.exist?(path)

    result = {}
    File.foreach(path, encoding: "utf-8") do |line|
      stripped = line.strip
      next if stripped.empty?

      record = JSON.parse(stripped)
      next unless record.is_a?(Hash)

      id = record["id"]
      name = record["thread_name"]
      result[id] = name if id.is_a?(String) && name.is_a?(String) && !name.empty?
    rescue JSON::ParserError
      next
    end
    result
  rescue Errno::ENOENT, Errno::EACCES
    {}
  end
end
