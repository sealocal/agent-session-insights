require "spec_helper"
require_relative "../lib/parser"

RSpec.describe Parser do
  def fixture(name)
    File.join(FIXTURES_DIR, name)
  end

  describe ".parse_file" do
    context "normal session" do
      subject(:session) { Parser.parse_file(fixture("normal_session.jsonl")) }

      it "sets the session_id from the filename" do
        expect(session.session_id).to eq("normal_session")
      end

      it "extracts the project path from cwd" do
        expect(session.project).to eq("/Users/test/myproject")
      end

      it "uses the most recent ai-title record as the session title" do
        expect(session.title).to eq("Helper function request")
      end

      it "exposes title in to_h output" do
        expect(session.to_h[:title]).to eq("Helper function request")
      end

      it "sets started_at to the first turn timestamp" do
        expect(session.started_at).to eq("2026-05-10T10:00:00.000Z")
      end

      it "includes both user and assistant turns" do
        roles = session.turns.map(&:role)
        expect(roles).to eq(%w[user assistant user assistant])
      end

      it "returns the correct turn count" do
        expect(session.turn_count).to eq(4)
      end

      describe "first assistant turn" do
        subject(:turn) { session.turns[1] }

        it "computes context_tokens as input + cache_creation + cache_read" do
          # 512 + 8000 + 0 = 8512
          expect(turn.context_tokens).to eq(8_512)
        end

        it "records output_tokens" do
          expect(turn.output_tokens).to eq(42)
        end

        it "captures a text preview" do
          expect(turn.text_preview).to include("Sure")
        end
      end

      describe "second assistant turn (cache hit)" do
        subject(:turn) { session.turns[3] }

        it "includes cache_read_input_tokens in context_tokens" do
          # 1200 + 0 + 8512 = 9712
          expect(turn.context_tokens).to eq(9_712)
        end
      end

      describe "totals" do
        subject(:totals) { session.totals }

        it "sums output_tokens across assistant turns" do
          expect(totals[:output_tokens]).to eq(42 + 187)
        end

        it "reports peak context, not sum of context snapshots" do
          expect(totals[:peak_context_tokens]).to eq(9_712)
        end

        it "does NOT sum context snapshots (that would be wrong)" do
          expect(totals[:peak_context_tokens]).not_to eq(8_512 + 9_712)
        end
      end
    end

    context "malformed lines" do
      it "skips bad lines and parses the remaining records" do
        expect { Parser.parse_file(fixture("malformed_lines.jsonl")) }.not_to raise_error
      end

      it "still returns turns from the valid lines" do
        session = Parser.parse_file(fixture("malformed_lines.jsonl"))
        expect(session.turns).not_to be_empty
      end

      it "includes an assistant turn from after a bad line" do
        session = Parser.parse_file(fixture("malformed_lines.jsonl"))
        expect(session.turns.any? { |t| t.role == "assistant" }).to be true
      end
    end

    context "empty file" do
      subject(:session) { Parser.parse_file(fixture("empty.jsonl")) }

      it "returns a session with no turns" do
        expect(session.turns).to be_empty
      end

      it "returns zero turn_count" do
        expect(session.turn_count).to eq(0)
      end

      it "returns nil started_at" do
        expect(session.started_at).to be_nil
      end

      it "returns zero output_tokens total" do
        expect(session.totals[:output_tokens]).to eq(0)
      end

      it "returns nil peak_context_tokens" do
        expect(session.totals[:peak_context_tokens]).to be_nil
      end

      it "returns nil title when no ai-title record is present" do
        expect(session.title).to be_nil
      end
    end

    context "no assistant turns" do
      subject(:session) { Parser.parse_file(fixture("no_assistant_turns.jsonl")) }

      it "returns only user turns" do
        expect(session.turns.map(&:role)).to all(eq("user"))
      end

      it "has nil context_tokens on every turn" do
        expect(session.turns.map(&:context_tokens)).to all(be_nil)
      end

      it "returns zero output_tokens total" do
        expect(session.totals[:output_tokens]).to eq(0)
      end
    end

    context "missing usage fields" do
      subject(:session) { Parser.parse_file(fixture("missing_usage.jsonl")) }

      it "does not raise" do
        expect { session }.not_to raise_error
      end

      it "returns nil context_tokens for assistant turns without usage" do
        assistant_turns = session.turns.select { |t| t.role == "assistant" }
        expect(assistant_turns).not_to be_empty
        expect(assistant_turns.map(&:context_tokens)).to all(be_nil)
      end
    end
  end

  describe ".total_context" do
    it "returns nil when usage is empty" do
      expect(Parser.total_context({})).to be_nil
    end

    it "sums whichever token fields are present" do
      usage = { "input_tokens" => 100, "cache_read_input_tokens" => 50 }
      expect(Parser.total_context(usage)).to eq(150)
    end

    it "treats missing fields as zero (excludes nils from sum)" do
      usage = { "input_tokens" => 200 }
      expect(Parser.total_context(usage)).to eq(200)
    end
  end

  describe ".extract_preview" do
    it "returns text from a string content field" do
      record = { "message" => { "content" => "Hello world" } }
      expect(Parser.extract_preview(record)).to eq("Hello world")
    end

    it "joins text blocks from an array content field" do
      record = {
        "message" => {
          "content" => [
            { "type" => "thinking", "thinking" => "internal..." },
            { "type" => "text", "text" => "Visible response" }
          ]
        }
      }
      expect(Parser.extract_preview(record)).to eq("Visible response")
    end

    it "truncates long text and appends ellipsis" do
      long = "x" * 200
      record = { "message" => { "content" => long } }
      result = Parser.extract_preview(record, limit: 140)
      expect(result.length).to be <= 141  # 140 chars + "…"
      expect(result).to end_with("…")
    end

    it "returns nil when content is absent" do
      expect(Parser.extract_preview({})).to be_nil
    end

    it "returns nil when content is an array with no text blocks" do
      record = { "message" => { "content" => [{ "type" => "thinking", "thinking" => "..." }] } }
      expect(Parser.extract_preview(record)).to be_nil
    end
  end
end
