require_relative "projects"
require_relative "parser"
require_relative "codex_projects"
require_relative "codex_parser"

# Registers the data sources the app knows how to read. Each provider
# exposes the same four-method surface (list/sessions/session_path/parse)
# so app.rb stays a thin router that doesn't care which one is which.
module Providers
  Provider = Struct.new(:id, :name, :root, :projects, :parser, keyword_init: true)

  ALL = [
    Provider.new(
      id: "claude",
      name: "Claude Code",
      root: ENV.fetch("CLAUDE_PROJECTS_DIR") { File.join(Dir.home, ".claude", "projects") },
      projects: Projects,
      parser: Parser
    ),
    Provider.new(
      id: "codex",
      name: "Codex CLI",
      root: ENV.fetch("CODEX_SESSIONS_DIR") { File.join(Dir.home, ".codex", "sessions") },
      projects: CodexProjects,
      parser: CodexParser
    )
  ].freeze

  module_function

  def find(id)
    ALL.find { |p| p.id == id }
  end

  def summaries
    ALL.map do |p|
      {
        id: p.id,
        name: p.name,
        available: Dir.exist?(p.root)
      }
    end
  end
end
