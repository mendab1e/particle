# frozen_string_literal: true

module Availability
  # Expands recurrences in bounded chunks and enforces occurrence-count limits.
  class RecurrenceExpander
    MAX_OCCURRENCES_PER_EVENT = 10_000
    MAX_OCCURRENCES_PER_CALENDAR = 50_000
    SECONDLY_CHUNK_SECONDS = 60 * 60
    MINUTELY_CHUNK_SECONDS = 24 * 60 * 60

    class LimitError < StandardError; end

    def initialize
      @calendar_occurrence_count = 0
    end

    def expand(event, range_start:, range_end:)
      occurrences = {}
      cursor = range_start
      chunk_seconds = expansion_chunk_seconds(event, range_start, range_end)

      while cursor < range_end
        chunk_end = [cursor + chunk_seconds, range_end].min
        add_occurrences(occurrences, event, cursor, chunk_end)
        cursor = chunk_end
      end

      occurrences.values
    end

    private

    def add_occurrences(occurrences, event, range_start, range_end)
      event.occurrences_between(range_start, range_end, spans: true).each do |occurrence|
        key = occurrence_key(occurrence)
        next if occurrences.key?(key)

        track_occurrence!(occurrences.length + 1)
        occurrences[key] = occurrence
      end
    end

    def expansion_chunk_seconds(event, range_start, range_end)
      frequencies = event.rrule.map { |rule| rule.value_ical[/FREQ=([^;]+)/, 1] }
      return SECONDLY_CHUNK_SECONDS if frequencies.include?('SECONDLY')
      return MINUTELY_CHUNK_SECONDS if frequencies.include?('MINUTELY')

      range_end - range_start
    end

    def occurrence_key(occurrence)
      [occurrence.start_time.to_time.utc, occurrence.end_time.to_time.utc]
    end

    def track_occurrence!(event_count)
      @calendar_occurrence_count += 1
      return if within_limits?(event_count)

      raise LimitError
    end

    def within_limits?(event_count)
      event_count <= MAX_OCCURRENCES_PER_EVENT && @calendar_occurrence_count <= MAX_OCCURRENCES_PER_CALENDAR
    end
  end
end
