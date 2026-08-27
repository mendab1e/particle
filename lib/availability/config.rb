# frozen_string_literal: true

require 'date'
require 'uri'
require 'yaml'
require 'tzinfo'

module Availability
  # Loads, normalizes, and validates generator configuration.
  class Config
    WEEKDAYS = %w[sunday monday tuesday wednesday thursday friday saturday].freeze
    ENV_REFERENCE = /\A\$\{([A-Z][A-Z0-9_]*)\}\z/
    TIME_FORMAT = /\A(?:[01]\d|2[0-3]):[0-5]\d\z/

    attr_reader :enabled, :timezone, :calendar_urls, :days_to_show,
                :minimum_slot_minutes, :buffer_before_minutes, :buffer_after_minutes

    def self.load(path, env: ENV)
      raise ConfigError, "configuration file not found: #{path}" unless File.file?(path)

      raw = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
      raise ConfigError, 'configuration root must be a mapping' unless raw.is_a?(Hash)

      new(raw, env: env)
    rescue Psych::Exception => e
      raise ConfigError, "invalid YAML in #{path}: #{e.message.lines.first.strip}"
    end

    def initialize(raw, env: ENV)
      @raw = stringify_keys(raw)
      @env = env
      @enabled = boolean('enabled', default: true)
      @timezone = parse_timezone
      @days_to_show = positive_integer('days_to_show', default: 28)
      @minimum_slot_minutes = nonnegative_integer('minimum_slot_minutes', default: 0)
      parse_buffers
      @availability = parse_availability
      @calendar_urls = parse_calendar_urls
    end

    def windows_for(date)
      @availability.fetch(WEEKDAYS.fetch(date.wday), @availability.fetch('default'))
    end

    private

    def stringify_keys(value)
      if value.is_a?(Hash)
        return value.each_with_object({}) do |(key, item), hash|
          hash[key.to_s] = stringify_keys(item)
        end
      end
      return value.map { |item| stringify_keys(item) } if value.is_a?(Array)

      value
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

    def nonnegative_integer(key, default:)
      value = @raw.fetch(key, default)
      return value if value.is_a?(Integer) && value >= 0

      raise ConfigError, "#{key} must be a non-negative integer"
    end

    def parse_timezone
      name = @raw.fetch('timezone', 'Europe/Berlin')
      raise ConfigError, 'timezone must be a string' unless name.is_a?(String)

      TZInfo::Timezone.get(name)
    rescue TZInfo::InvalidTimezoneIdentifier
      raise ConfigError, "timezone is unknown: #{name}"
    end

    def parse_buffers
      buffer = @raw.fetch('event_buffer', {})
      raise ConfigError, 'event_buffer must be a mapping' unless buffer.is_a?(Hash)

      @buffer_before_minutes = nested_nonnegative_integer(buffer, 'before_minutes', 0, 'event_buffer.before_minutes')
      @buffer_after_minutes = nested_nonnegative_integer(buffer, 'after_minutes', 0, 'event_buffer.after_minutes')
    end

    def nested_nonnegative_integer(hash, key, default, label)
      value = hash.fetch(key, default)
      return value if value.is_a?(Integer) && value >= 0

      raise ConfigError, "#{label} must be a non-negative integer"
    end

    def parse_calendar_urls
      # Disabled mode must not depend on feed secrets being present.
      return [].freeze unless enabled

      urls = @raw.fetch('calendar_urls', [])
      raise ConfigError, 'calendar_urls must be an array' unless urls.is_a?(Array)

      resolved = urls.each_with_index.map { |value, index| parse_calendar_url(value, index) }
      raise ConfigError, 'calendar_urls must contain at least one URL when enabled' if resolved.empty?

      resolved.freeze
    end

    def parse_calendar_url(value, index)
      label = "calendar_urls[#{index}]"
      raise ConfigError, "#{label} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?

      match = ENV_REFERENCE.match(value.strip)
      value = resolve_environment(match[1], label) if match
      validate_url(value, label)
    end

    def resolve_environment(name, label)
      value = @env[name]
      raise ConfigError, "#{label} references missing environment variable #{name}" if value.nil? || value.empty?

      value
    end

    def validate_url(value, label)
      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTP) && uri.host && %w[http https].include?(uri.scheme)
        raise ConfigError, "#{label} must be an HTTP(S) URL"
      end

      value
    rescue URI::InvalidURIError
      raise ConfigError, "#{label} must be a valid HTTP(S) URL"
    end

    def parse_availability
      source = @raw['availability']
      raise ConfigError, 'availability must be a mapping' unless source.is_a?(Hash)

      unknown = source.keys - (['default'] + WEEKDAYS)
      raise ConfigError, "availability has unknown key: #{unknown.first}" unless unknown.empty?
      raise ConfigError, 'availability.default is required' unless source.key?('default')

      source.each_with_object({}) do |(day, definition), result|
        result[day] = parse_day_definition(definition, "availability.#{day}")
      end.freeze
    end

    def parse_day_definition(definition, key)
      return unavailable_day(definition, key) if unavailable?(definition)

      windows = definition.is_a?(Array) ? definition : [definition]
      raise ConfigError, "#{key} must contain at least one window or unavailable: true" if windows.empty?

      parsed = windows.each_with_index.map { |window, index| parse_window(window, "#{key}[#{index}]") }
      parsed.sort_by!(&:first)
      validate_nonoverlapping_windows(parsed, key)
      parsed.freeze
    end

    def unavailable?(definition)
      definition.is_a?(Hash) && definition['unavailable'] == true
    end

    def unavailable_day(definition, key)
      extra = definition.keys - ['unavailable']
      raise ConfigError, "#{key} cannot combine unavailable with windows" unless extra.empty?

      [].freeze
    end

    def validate_nonoverlapping_windows(windows, key)
      windows.each_cons(2) do |left, right|
        raise ConfigError, "#{key} windows must not overlap" if left.last > right.first
      end
    end

    def parse_window(window, key)
      raise ConfigError, "#{key} must be a start/end mapping" unless window.is_a?(Hash)

      unknown = window.keys - %w[start end]
      raise ConfigError, "#{key} has unknown key: #{unknown.first}" unless unknown.empty?

      starts = parse_time(window['start'], "#{key}.start")
      ends = parse_time(window['end'], "#{key}.end")
      raise ConfigError, "#{key}.start must be earlier than #{key}.end" unless starts < ends

      [starts, ends].freeze
    end

    def parse_time(value, key)
      raise ConfigError, "#{key} must use HH:MM (24-hour time)" unless value.is_a?(String) && TIME_FORMAT.match?(value)

      hour, minute = value.split(':').map(&:to_i)
      (hour * 60) + minute
    end
  end
end
