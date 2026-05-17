require "spec_helper"

# Point each provider at a fixture root before loading the app so the
# Providers registry resolves to deterministic test data.
ENV["CLAUDE_PROJECTS_DIR"] ||= File.join(FIXTURES_DIR, "claude_projects_root")
ENV["CODEX_SESSIONS_DIR"] ||= File.join(FIXTURES_DIR, "codex")
ENV["APP_ENV"] = "test"
ENV["RACK_ENV"] = "test"

require_relative "../app"

Sinatra::Application.set :host_authorization, permitted_hosts: []

RSpec.describe "HTTP API" do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  describe "GET /api/providers" do
    it "lists both providers" do
      get "/api/providers"
      expect(last_response.status).to eq(200)
      ids = JSON.parse(last_response.body).map { |p| p["id"] }
      expect(ids).to contain_exactly("claude", "codex")
    end
  end

  describe "claude provider" do
    it "lists projects" do
      get "/api/providers/claude/projects"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).not_to be_empty
    end

    it "keeps the legacy /api/projects route working" do
      get "/api/projects"
      expect(last_response.status).to eq(200)
    end
  end

  describe "codex provider" do
    it "lists projects derived from session_meta cwd" do
      get "/api/providers/codex/projects"
      expect(last_response.status).to eq(200)
      names = JSON.parse(last_response.body).map { |p| p["display_name"] }
      expect(names).to include("/Users/test/myproject", "/Users/test/other")
    end

    it "returns parsed session data" do
      get "/api/providers/codex/projects"
      project = JSON.parse(last_response.body).find { |p| p["display_name"] == "/Users/test/myproject" }
      get "/api/providers/codex/projects/#{project["id"]}/sessions"
      expect(last_response.status).to eq(200)
      sessions = JSON.parse(last_response.body)
      expect(sessions).not_to be_empty

      get "/api/providers/codex/projects/#{project["id"]}/sessions/#{sessions.first["id"]}"
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["project"]).to eq("/Users/test/myproject")
      expect(body["turns"]).not_to be_empty
    end
  end

  describe "unknown provider" do
    it "returns 404" do
      get "/api/providers/bogus/projects"
      expect(last_response.status).to eq(404)
    end
  end
end
