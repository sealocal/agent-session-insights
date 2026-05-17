require "spec_helper"
require_relative "../lib/codex_projects"

RSpec.describe CodexProjects do
  let(:root) { File.join(FIXTURES_DIR, "codex") }

  describe ".list" do
    subject(:projects) { CodexProjects.list(root) }

    it "groups sessions by cwd from session_meta" do
      names = projects.map { |p| p[:display_name] }.sort
      expect(names).to eq(["/Users/test/myproject", "/Users/test/other"])
    end

    it "counts sessions per project" do
      myproject = projects.find { |p| p[:display_name] == "/Users/test/myproject" }
      expect(myproject[:session_count]).to eq(2)
    end

    it "sorts by last_active descending" do
      timestamps = projects.map { |p| p[:last_active] }
      expect(timestamps).to eq(timestamps.sort.reverse)
    end

    it "encodes project_id as url-safe base64 of the cwd" do
      myproject = projects.find { |p| p[:display_name] == "/Users/test/myproject" }
      expect(Base64.urlsafe_decode64(myproject[:id])).to eq("/Users/test/myproject")
    end
  end

  describe ".sessions" do
    let(:project_id) { Base64.urlsafe_encode64("/Users/test/myproject", padding: false) }

    it "returns sessions whose session_meta.cwd matches" do
      sessions = CodexProjects.sessions(root, project_id)
      ids = sessions.map { |s| s[:id] }.sort
      expect(ids).to eq([
        "aaaa0001-0000-0000-0000-000000000001",
        "cccc0003-0000-0000-0000-000000000003"
      ])
    end

    it "returns nil for an unknown cwd" do
      bogus_id = Base64.urlsafe_encode64("/nope", padding: false)
      expect(CodexProjects.sessions(root, bogus_id)).to be_nil
    end

    it "returns nil for an undecodable project id" do
      expect(CodexProjects.sessions(root, "!!!not-base64!!!")).to be_nil
    end
  end

  describe ".session_path" do
    let(:project_id) { Base64.urlsafe_encode64("/Users/test/myproject", padding: false) }

    it "resolves a session id to its rollout file" do
      path = CodexProjects.session_path(root, project_id,
        "aaaa0001-0000-0000-0000-000000000001")
      expect(path).to end_with("rollout-2026-05-10T10-00-00-aaaa0001-0000-0000-0000-000000000001.jsonl")
    end

    it "returns nil when the session id does not belong to the project" do
      other_id = Base64.urlsafe_encode64("/Users/test/other", padding: false)
      path = CodexProjects.session_path(root, other_id,
        "aaaa0001-0000-0000-0000-000000000001")
      expect(path).to be_nil
    end

    it "rejects path-traversal-style session ids" do
      expect(CodexProjects.session_path(root, project_id, "../etc/passwd")).to be_nil
    end
  end
end
