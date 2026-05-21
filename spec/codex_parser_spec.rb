require "spec_helper"
require_relative "../lib/codex_parser"

CODEX_FIXTURE = File.join(
  FIXTURES_DIR, "codex", "2026", "05", "10",
  "rollout-2026-05-10T10-00-00-aaaa0001-0000-0000-0000-000000000001.jsonl"
)

RSpec.describe CodexParser do
  describe ".parse_file" do
    subject(:session) { CodexParser.parse_file(CODEX_FIXTURE) }

    it "pulls session_id from the session_meta payload" do
      expect(session.session_id).to eq("aaaa0001-0000-0000-0000-000000000001")
    end

    it "extracts cwd as the project path" do
      expect(session.project).to eq("/Users/test/myproject")
    end

    it "uses session_meta timestamp as started_at" do
      expect(session.started_at).to eq("2026-05-10T10:00:00.000Z")
    end

    it "surfaces only event_msg user/agent records as turns" do
      expect(session.turns.map(&:role)).to eq(%w[user assistant user assistant])
    end

    it "prefers the user-renamed title from the session_index over the first user message" do
      expect(session.title).to eq("Renamed by user")
    end

    describe "first assistant turn" do
      subject(:turn) { session.turns[1] }

      it "uses last_token_usage.input_tokens as the per-turn context snapshot" do
        expect(turn.context_tokens).to eq(3_899)
      end

      it "captures last_token_usage.output_tokens" do
        expect(turn.output_tokens).to eq(42)
      end

      it "captures cached_input_tokens as cache_read_tokens" do
        expect(turn.cache_read_tokens).to eq(3_200)
      end

      it "leaves cache_creation_tokens nil (Codex doesn't expose it)" do
        expect(turn.cache_creation_tokens).to be_nil
      end

      it "previews the agent message text" do
        expect(turn.text_preview).to include("Sure")
      end
    end

    describe "totals" do
      subject(:totals) { session.totals }

      it "sums output_tokens across assistant turns" do
        expect(totals[:output_tokens]).to eq(42 + 187)
      end

      it "reports peak context, not sum of context snapshots" do
        expect(totals[:peak_context_tokens]).to eq(4_101)
      end
    end
  end

  context "session missing token_count records" do
    let(:fixture) {
      File.join(FIXTURES_DIR, "codex", "2026", "05", "11",
        "rollout-2026-05-11T09-00-00-cccc0003-0000-0000-0000-000000000003.jsonl")
    }

    it "still parses turns but leaves usage fields nil" do
      session = CodexParser.parse_file(fixture)
      expect(session.turns.map(&:role)).to eq(["user"])
      expect(session.totals[:peak_context_tokens]).to be_nil
      expect(session.totals[:output_tokens]).to eq(0)
    end

    it "falls back to the first user message when no rename is recorded" do
      session = CodexParser.parse_file(fixture)
      expect(session.title).to eq("second session in myproject")
    end
  end

  context "malformed lines" do
    it "skips bad lines without crashing" do
      Tempfile.create(["codex", ".jsonl"]) do |f|
        f.write(<<~JSONL)
          {"timestamp":"2026-05-10T10:00:00Z","type":"session_meta","payload":{"id":"abc","cwd":"/tmp"}}
          this is not json
          {"timestamp":"2026-05-10T10:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"hi"}}
        JSONL
        f.flush
        session = CodexParser.parse_file(f.path)
        expect(session.turns.length).to eq(1)
        expect(session.turns.first.role).to eq("user")
      end
    end
  end
end
