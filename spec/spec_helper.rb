require "rack/test"
require "tempfile"
require "base64"

FIXTURES_DIR = File.expand_path("fixtures", __dir__)

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
