require "sinatra"
require "sinatra/json"
require_relative "lib/providers"

set :port, ENV.fetch("PORT", 4567).to_i
set :public_folder, File.join(__dir__, "public")
set :bind, "127.0.0.1"  # local only

helpers do
  def lookup_provider!(id)
    provider = Providers.find(id)
    halt 404, json(error: "unknown provider") unless provider
    provider
  end
end

# ── Providers ───────────────────────────────────────────────────────────────

get "/api/providers" do
  content_type :json
  json Providers.summaries
end

# ── Projects ────────────────────────────────────────────────────────────────

get "/api/providers/:provider/projects" do
  content_type :json
  provider = lookup_provider!(params[:provider])
  json provider.projects.list(provider.root)
end

get "/api/providers/:provider/projects/:project_id/sessions" do
  content_type :json
  provider = lookup_provider!(params[:provider])
  sessions = provider.projects.sessions(provider.root, params[:project_id])
  halt 404, json(error: "project not found") if sessions.nil?
  json sessions
end

get "/api/providers/:provider/projects/:project_id/sessions/:session_id" do
  content_type :json
  provider = lookup_provider!(params[:provider])
  path = provider.projects.session_path(provider.root, params[:project_id], params[:session_id])
  halt 404, json(error: "session not found") unless path

  session = provider.parser.parse_file(path)
  json session.to_h
end

# ── Backwards-compatible Claude-only routes ─────────────────────────────────
# These mirror the original API surface so anything pointing at the unprefixed
# endpoints keeps working. New clients should use /api/providers/:provider/...

get "/api/projects" do
  content_type :json
  provider = Providers.find("claude")
  json provider.projects.list(provider.root)
end

get "/api/projects/:project_id/sessions" do
  content_type :json
  provider = Providers.find("claude")
  sessions = provider.projects.sessions(provider.root, params[:project_id])
  halt 404, json(error: "project not found") if sessions.nil?
  json sessions
end

get "/api/projects/:project_id/sessions/:session_id" do
  content_type :json
  provider = Providers.find("claude")
  path = provider.projects.session_path(provider.root, params[:project_id], params[:session_id])
  halt 404, json(error: "session not found") unless path

  session = provider.parser.parse_file(path)
  json session.to_h
end

# ── Frontend ─────────────────────────────────────────────────────────────────

get "/" do
  send_file File.join(settings.public_folder, "index.html")
end
