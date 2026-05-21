require "rack/test"
require "tempfile"
require "base64"

FIXTURES_DIR = File.expand_path("fixtures", __dir__)

# Point Codex's session-rename index at the test fixture so specs never
# read the developer's real ~/.codex/session_index.jsonl.
ENV["CODEX_SESSION_INDEX"] = File.join(FIXTURES_DIR, "codex_session_index.jsonl")

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
