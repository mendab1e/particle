# frozen_string_literal: true

module Availability
  class Error < StandardError; end
  class ConfigError < Error; end
  class FetchError < Error; end
  class ParseError < Error; end
  class InvalidEventError < Error; end
end
