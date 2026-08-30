# frozen_string_literal: true

require 'icalendar'

module Availability
  # Isolates property-level iCalendar failures to the VEVENT that contains them.
  class TolerantIcalendarParser < Icalendar::Parser
    INVALID_MARKER = :@availability_invalid_event
    SUPPORTED_VALUE_TYPES = %w[
      BINARY BOOLEAN CAL-ADDRESS DATE DATE-TIME DURATION FLOAT INTEGER PERIOD RECUR TEXT TIME URI UTC-OFFSET
    ].freeze

    def self.invalid_event?(event)
      event.instance_variable_defined?(INVALID_MARKER)
    end

    private

    def parse_property(component, fields = nil)
      if component.is_a?(Icalendar::Event) && unsupported_value_type?(fields)
        mark_invalid(component)
        return
      end

      super
    rescue StandardError
      raise unless component.is_a?(Icalendar::Event)

      mark_invalid(component)
    end

    def parse_component(component)
      super
    rescue StandardError
      raise unless component.is_a?(Icalendar::Event)

      mark_invalid(component)
      discard_remaining_event
      component
    end

    def mark_invalid(event)
      event.instance_variable_set(INVALID_MARKER, true)
    end

    def unsupported_value_type?(fields)
      value_type = fields&.dig(:params, 'value')&.first
      value_type && !SUPPORTED_VALUE_TYPES.include?(value_type.upcase)
    end

    def discard_remaining_event
      loop do
        fields = next_fields
        return if fields.nil? || event_end?(fields)
      rescue StandardError
        next
      end
    end

    def event_end?(fields)
      fields[:name] == 'end' && fields[:value].casecmp('VEVENT').zero?
    end
  end
end
