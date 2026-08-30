# frozen_string_literal: true

module Availability
  # Shared scalar and schema validation helpers for configuration loading.
  module ConfigValueParser
    private

    def validate_known_keys(hash, allowed, label)
      unknown = hash.keys - allowed
      raise ConfigError, "#{label} has unknown key: #{unknown.first}" unless unknown.empty?
    end

    def boolean(key, default:)
      value = @raw.fetch(key, default)
      return value if [true, false].include?(value)

      raise ConfigError, "#{key} must be true or false"
    end

    def positive_integer(key, default:)
      value = @raw.fetch(key, default)
      return value if value.is_a?(Integer) && value.positive?

      raise ConfigError, "#{key} must be a positive integer"
    end

    def bounded_positive_integer(key, default:, maximum:)
      value = positive_integer(key, default: default)
      return value if value <= maximum

      raise ConfigError, "#{key} must be at most #{maximum}"
    end

    def nonnegative_integer(key, default:)
      value = @raw.fetch(key, default)
      return value if value.is_a?(Integer) && value >= 0

      raise ConfigError, "#{key} must be a non-negative integer"
    end

    def nested_nonnegative_integer(hash, key, default, label)
      value = hash.fetch(key, default)
      return value if value.is_a?(Integer) && value >= 0

      raise ConfigError, "#{label} must be a non-negative integer"
    end
  end
end
