require "sinatra"
require "sinatra/json"
require_relative "lib/projects"
require_relative "lib/parser"

DATA_ROOT = ENV.fetch("CLAUDE_PROJECTS_DIR") do
  File.join(Dir.home, ".claude", "projects")
end

set :port, ENV.fetch("PORT", 4567).to_i
set :public_folder, File.join(__dir__, "public")
set :bind, "127.0.0.1"  # local only

# ── Projects ────────────────────────────────────────────────────────────────

get "/api/projects" do
  content_type :json
  json Projects.list(DATA_ROOT)
end

# ── Sessions (metadata only) ─────────────────────────────────────────────────

get "/api/projects/:project_id/sessions" do
  content_type :json
  sessions = Projects.sessions(DATA_ROOT, params[:project_id])
  halt 404, json(error: "project not found") if sessions.nil?
  json sessions
end

# ── Full parsed session ───────────────────────────────────────────────────────

get "/api/projects/:project_id/sessions/:session_id" do
  content_type :json
  path = Projects.session_path(DATA_ROOT, params[:project_id], params[:session_id])
  halt 404, json(error: "session not found") unless path

  session = Parser.parse_file(path)
  json session.to_h
end

# ── Frontend ─────────────────────────────────────────────────────────────────

get "/" do
  send_file File.join(settings.public_folder, "index.html")
end
