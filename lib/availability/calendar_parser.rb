# frozen_string_literal: true

require 'active_support/time'
require 'icalendar'
require 'icalendar/recurrence'

module Availability
  # Parses ICS events and expands occurrences into privacy-safe busy periods.
  class CalendarParser
    def initialize(timezone:)
      @timezone = timezone
    end

    def parse(ics, range_start:, range_end:, label: 'Calendar')
      events = parse_events(ics, label)
      override_keys = recurrence_override_keys(events)
      busy_periods(events, override_keys, range_start, range_end)
    rescue InvalidEventError => e
      raise ParseError, "#{label} could not be parsed: #{e.message}"
    rescue ParseError
      raise
    rescue StandardError => e
      raise ParseError, "#{label} could not be parsed (#{e.class})"
    end

    private

    def parse_events(ics, label)
      calendars = Icalendar::Calendar.parse(ics)
      raise ParseError, "#{label} did not contain a calendar" if calendars.empty?

      events = calendars.flat_map(&:events)
      events.each { |event| validate_event!(event) }
      events
    end

    def validate_event!(event)
      return if cancelled?(event)

      raise InvalidEventError, 'event is missing DTSTART' unless event.dtstart
      return if all_day?(event) && !event.dtend && !event.duration

      starts_at = event.schedule.start_time
      ends_at = event.schedule.end_time
      raise InvalidEventError, 'event duration must be positive' unless ends_at > starts_at
    end

    def busy_periods(events, override_keys, range_start, range_end)
      events.reject { |event| cancelled?(event) }.flat_map do |event|
        event_periods(event, override_keys, range_start, range_end)
      end
    end

    def event_periods(event, override_keys, range_start, range_end)
      occurrences(event, range_start, range_end).filter_map do |occurrence|
        next if master_occurrence_overridden?(event, occurrence, override_keys)

        period = occurrence_to_period(event, occurrence)
        period if period&.intersects?(range_start, range_end)
      end
    end

    def occurrences(event, range_start, range_end)
      return [] unless event.dtstart

      # `spans: true` includes an occurrence that begins before the range and
      # continues into it. Expansion remains bounded to the required output.
      event.occurrences_between(range_start, range_end, spans: true)
    end

    def occurrence_to_period(event, occurrence)
      starts_at, ends_at = period_boundaries(event, occurrence)
      raise InvalidEventError, 'event occurrence duration must be positive' unless ends_at > starts_at

      BusyPeriod.new(starts_at, ends_at)
    end

    def period_boundaries(event, occurrence)
      return all_day_boundaries(occurrence) if all_day?(event)
      return floating_boundaries(occurrence) if floating?(event)

      [occurrence.start_time.to_time.utc, occurrence.end_time.to_time.utc]
    end

    def all_day_boundaries(occurrence)
      # DATE values are created in the process zone; recover their calendar date
      # before placing the all-day span in the configured zone.
      start_date = occurrence.start_time.getlocal.to_date
      end_date = [occurrence.end_time.getlocal.to_date, start_date + 1].max
      [local_midnight(start_date), local_midnight(end_date)]
    end

    def floating_boundaries(occurrence)
      [floating_time_to_utc(occurrence.start_time), floating_time_to_utc(occurrence.end_time)]
    end

    def all_day?(event)
      event.dtstart.is_a?(Icalendar::Values::Date)
    end

    def floating?(event)
      event.dtstart.ical_params['tzid'].nil?
    end

    def floating_time_to_utc(time)
      @timezone.local_time(time.year, time.month, time.day, time.hour, time.min, time.sec).utc
    end

    def local_midnight(date)
      @timezone.local_time(date.year, date.month, date.day, 0, 0, 0).utc
    end

    def cancelled?(event)
      event.status && event.status.to_s.casecmp('CANCELLED').zero?
    end

    def recurrence_override_keys(events)
      events.each_with_object({}) do |event, keys|
        next unless event.recurrence_id && event.uid

        keys[[event.uid.to_s, value_to_utc(event.recurrence_id)]] = true
      end
    end

    def master_occurrence_overridden?(event, occurrence, override_keys)
      return false if event.recurrence_id || !event.uid

      override_keys.key?([event.uid.to_s, occurrence.start_time.to_time.utc])
    end

    def value_to_utc(value)
      Icalendar::Recurrence::TimeUtil.to_time(value).to_time.utc
    end
  end
end
