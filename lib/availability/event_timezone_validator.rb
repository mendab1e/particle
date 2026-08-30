# frozen_string_literal: true

require 'active_support/time'
require 'icalendar'

module Availability
  # Rejects TZID values the iCalendar parser could not resolve safely.
  class EventTimezoneValidator
    def self.validate!(event)
      new(event).validate!
    end

    def initialize(event)
      @event = event
    end

    def validate!
      temporal_values.each do |value|
        raise InvalidEventError, 'event contains an unresolved timezone' if unresolved_timezone?(value)
      end
    end

    private

    def temporal_values
      values = [@event.dtstart, @event.dtend, @event.recurrence_id, @event.exdate, @event.rdate]
      values.flat_map { |value| flatten_temporal_value(value) }.compact
    end

    def flatten_temporal_value(value)
      return [] if value.nil?
      return value.flat_map { |item| flatten_temporal_value(item) } if value.is_a?(Array)
      if value.is_a?(Icalendar::Values::Helpers::Array)
        return value.value.flat_map { |item| flatten_temporal_value(item) }
      end

      [value]
    end

    def unresolved_timezone?(value)
      return false unless value.respond_to?(:ical_params)

      tzid = Array(value.ical_params['tzid']).first
      return false if tzid.nil? || tzid == 'UTC'
      return false if resolved_time_value?(value.value)

      timezone_store = value.respond_to?(:timezone_store) && value.timezone_store
      timezone_store.nil? || timezone_store.retrieve(tzid).nil?
    end

    def resolved_time_value?(value)
      value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
    end
  end
end
