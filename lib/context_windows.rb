# Maps a model id to its context window in tokens.
#
# The window is not recorded anywhere in the JSONL, so it has to be inferred
# from the model name on assistant turns. Matching is by prefix because ids may
# carry a date suffix (claude-haiku-4-5-20251001).
module ContextWindows
  WINDOWS = {
    "claude-haiku-4-5" => 200_000,
    "claude-fable-5" => 1_000_000,
    "claude-mythos-5" => 1_000_000,
    "claude-opus-5" => 1_000_000,
    "claude-opus-4-8" => 1_000_000,
    "claude-opus-4-7" => 1_000_000,
    "claude-opus-4-6" => 1_000_000,
    "claude-sonnet-5" => 1_000_000,
    "claude-sonnet-4-6" => 1_000_000
  }.freeze

  module_function

  # Returns nil for unknown or synthetic models so the frontend can omit the
  # reference line rather than draw a guessed ceiling.
  def for(model)
    return nil unless model.is_a?(String)

    match = WINDOWS.keys.select { |prefix| model.start_with?(prefix) }.max_by(&:length)
    match && WINDOWS[match]
  end
end
