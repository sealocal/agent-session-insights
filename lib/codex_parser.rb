require "json"
require_relative "parser"
require_relative "codex_session_index"

# Parses Codex CLI rollout JSONL files into Parser::Session objects so the
# frontend can render them with the same chart and turn-list code paths as
# Claude sessions. Codex records come in three shapes we care about:
#
#   - session_meta: carries cwd, session id, and start timestamp (first line)
#   - event_msg/user_message:  one user-facing user turn
#   - event_msg/agent_message: one user-facing assistant turn
#   - event_msg/token_count:   usage snapshot — attach to the preceding
#                              assistant turn
#
# response_item records carry the same conversation in OpenAI Responses API
# format, but they include synthetic system framing (<user_instructions>,
# <environment_context>) and tool/reasoning items that aren't useful to
# surface as "turns". event_msg gives us clean human-facing text, so that's
# what we render.
module CodexParser
  module_function

  def parse_file(path)
    session_id = extract_session_id(File.basename(path))
    turns = []
    project = nil
    started_at = nil
    last_assistant_turn = nil

    File.foreach(path, encoding: "utf-8").with_index(1) do |raw, line_no|
      line = raw.strip
      next if line.empty?

      record =
        begin
          JSON.parse(line)
        rescue JSON::ParserError => e
          warn "[codex_parser] skipping malformed line #{line_no} in #{File.basename(path)}: #{e.message}"
          next
        end

      next unless record.is_a?(Hash)

      case record["type"]
      when "session_meta"
        payload = record["payload"] || {}
        project ||= payload["cwd"]
        started_at ||= payload["timestamp"] || record["timestamp"]
        session_id = payload["id"] if payload["id"]

      when "event_msg"
        payload = record["payload"] || {}
        case payload["type"]
        when "user_message"
          turns << Parser::Turn.new(
            index: turns.length,
            role: "user",
            timestamp: record["timestamp"],
            context_tokens: nil,
            output_tokens: nil,
            cache_read_tokens: nil,
            cache_creation_tokens: nil,
            text_preview: truncate(payload["message"])
          )
        when "agent_message"
          turn = Parser::Turn.new(
            index: turns.length,
            role: "assistant",
            timestamp: record["timestamp"],
            context_tokens: nil,
            output_tokens: nil,
            cache_read_tokens: nil,
            cache_creation_tokens: nil,
            text_preview: truncate(payload["message"])
          )
          turns << turn
          last_assistant_turn = turn
        when "token_count"
          attach_usage(last_assistant_turn, payload)
        end
      end
    end

    Parser::Session.new(
      session_id: session_id,
      project: project,
      title: CodexSessionIndex.titles[session_id] || turns.find { |t| t.role == "user" }&.text_preview,
      started_at: started_at || turns.first&.timestamp,
      turn_count: turns.length,
      turns: turns,
      totals: compute_totals(turns)
    )
  end

  # Codex's last_token_usage.input_tokens is already the full per-turn
  # context size (it includes cached_input_tokens as a subset, OpenAI-style),
  # which matches Parser's "context_tokens is a snapshot, not additive" rule.
  def attach_usage(turn, payload)
    return unless turn
    info = payload["info"]
    return unless info.is_a?(Hash)

    last = info["last_token_usage"] || {}
    turn.context_tokens = last["input_tokens"]
    turn.output_tokens = last["output_tokens"]
    turn.cache_read_tokens = last["cached_input_tokens"]
  end

  def compute_totals(turns)
    assistant_turns = turns.select { |t| t.role == "assistant" }
    {
      output_tokens: assistant_turns.filter_map(&:output_tokens).sum,
      peak_context_tokens: assistant_turns.filter_map(&:context_tokens).max
    }
  end

  def truncate(text, limit: 140)
    return nil if text.nil?
    text = text.to_s.strip
    return nil if text.empty?
    (text.length > limit) ? "#{text[0, limit]}…" : text
  end

  # rollout-2025-10-20T14-53-34-<uuid>.jsonl → <uuid>
  def extract_session_id(basename)
    name = basename.sub(/\.jsonl\z/, "")
    if (m = name.match(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\z/i))
      m[1]
    else
      name
    end
  end
end
