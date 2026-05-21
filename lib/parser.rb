require "json"

# Parses Claude Code JSONL session files into structured Ruby objects.
# All format fragility is contained here. Every field is treated as optional.
# A bad line is skipped with a warning; it never aborts the whole session.
module Parser
  # Represents one user or assistant turn surfaced to the frontend.
  # Token fields are nil for turns that carry no usage data (all user turns,
  # and any assistant turn where the API didn't return a usage block).
  Turn = Struct.new(
    :index, :role, :timestamp,
    :context_tokens,            # snapshot of full context at this turn — NOT additive
    :output_tokens,             # additive across turns
    :cache_read_tokens,
    :cache_creation_tokens,
    :text_preview,
    keyword_init: true
  )

  Session = Struct.new(
    :session_id, :project, :title, :started_at,
    :turn_count, :turns, :totals, :compactions,
    keyword_init: true
  ) do
    def to_h
      {
        session_id: session_id,
        project: project,
        title: title,
        started_at: started_at,
        turn_count: turn_count,
        turns: turns.map(&:to_h),
        totals: totals,
        compactions: compactions || []
      }
    end
  end

  module_function

  def parse_file(path)
    session_id = File.basename(path, ".jsonl")
    turns = []
    compactions = []
    project = nil
    title = nil

    File.foreach(path, encoding: "utf-8").with_index(1) do |raw, line_no|
      line = raw.strip
      next if line.empty?

      record =
        begin
          JSON.parse(line)
        rescue JSON::ParserError => e
          warn "[parser] skipping malformed line #{line_no} in #{File.basename(path)}: #{e.message}"
          next
        end

      next unless record.is_a?(Hash)

      # Grab project path from whichever record carries cwd first
      project ||= record["cwd"]

      # Title records may appear multiple times as the session grows; keep the latest
      if record["type"] == "ai-title" && record["aiTitle"].is_a?(String) && !record["aiTitle"].empty?
        title = record["aiTitle"]
      end

      if (compaction = build_compaction(record, turns.length))
        compactions << compaction
        next
      end

      turn = build_turn(record, turns.length)
      turns << turn if turn
    end

    Session.new(
      session_id: session_id,
      project: project,
      title: title,
      started_at: turns.first&.timestamp,
      turn_count: turns.length,
      turns: turns,
      totals: compute_totals(turns),
      compactions: compactions
    )
  end

  # A /compact (manual or automatic) writes a system/compact_boundary record
  # carrying the pre/post context sizes. We surface it as an event anchored to
  # the turn position where it occurred (turn_index = turns seen so far), so the
  # UI can mark the resulting context drop. Returns nil for any other record.
  def build_compaction(record, turn_index)
    return nil unless record["type"] == "system" && record["subtype"] == "compact_boundary"

    meta = record["compactMetadata"] || {}
    {
      turn_index: turn_index,
      timestamp: record["timestamp"],
      trigger: meta["trigger"],
      pre_tokens: meta["preTokens"],
      post_tokens: meta["postTokens"]
    }
  end

  # Returns a Turn for user/assistant records that represent real conversation
  # turns. Returns nil for meta records, tool-delta records, and other types
  # that aren't surfaced to the user.
  def build_turn(record, index)
    return nil unless record.is_a?(Hash)

    role = record["type"]
    return nil unless %w[user assistant].include?(role)

    # isMeta records are internal harness messages (skill routing, etc.)
    return nil if record["isMeta"]

    message = record["message"]
    usage = (message.is_a?(Hash) ? message["usage"] : nil) || {}

    Turn.new(
      index: index,
      role: role,
      timestamp: record["timestamp"],
      context_tokens: total_context(usage),
      output_tokens: usage["output_tokens"],
      cache_read_tokens: usage["cache_read_input_tokens"],
      cache_creation_tokens: usage["cache_creation_input_tokens"],
      text_preview: extract_preview(record)
    )
  end

  # Total context for one assistant turn.
  # input_tokens is a full-context snapshot; adding the cache fields gives
  # the true total tokens the model "saw". Returns nil when no usage present.
  def total_context(usage)
    parts = [
      usage["input_tokens"],
      usage["cache_read_input_tokens"],
      usage["cache_creation_input_tokens"]
    ].compact
    parts.empty? ? nil : parts.sum
  end

  def compute_totals(turns)
    assistant_turns = turns.select { |t| t.role == "assistant" }
    {
      # output_tokens IS additive — sum across all assistant turns
      output_tokens: assistant_turns.filter_map(&:output_tokens).sum,
      # context_tokens is a per-turn snapshot; "peak" is the meaningful aggregate
      peak_context_tokens: assistant_turns.filter_map(&:context_tokens).max
    }
  end

  # Extracts a short text preview from a record's message content.
  # Content may be a plain string or an array of typed blocks.
  def extract_preview(record, limit: 140)
    content = record.dig("message", "content")
    text =
      case content
      when String
        content
      when Array
        content
          .select { |b| b.is_a?(Hash) && b["type"] == "text" }
          .map { |b| b["text"].to_s }
          .join(" ")
      end

    return nil if text.nil? || text.strip.empty?

    text = text.strip
    (text.length > limit) ? "#{text[0, limit]}…" : text
  end
end
