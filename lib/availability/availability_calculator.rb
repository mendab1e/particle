# frozen_string_literal: true

module Availability
  # Subtracts merged busy periods from configured per-day availability windows.
  class AvailabilityCalculator
    def initialize(config)
      @config = config
    end

    def calculate(start_date:, busy_periods:)
      expanded_busy = busy_periods.map { |period| apply_buffer(period) }

      Array.new(@config.days_to_show) do |offset|
        date = start_date + offset
        DayAvailability.new(date, available_slots(date, expanded_busy))
      end
    end

    private

    def apply_buffer(period)
      BusyPeriod.new(
        period.starts_at - (@config.buffer_before_minutes * 60),
        period.ends_at + (@config.buffer_after_minutes * 60)
      )
    end

    def available_slots(date, busy_periods)
      slots = @config.windows_for(date).flat_map do |window|
        slots_for_window(date, window, busy_periods)
      end
      slots.select { |slot| long_enough?(slot) }
    end

    def slots_for_window(date, window, busy_periods)
      starts_at, ends_at = window_boundaries(date, window)
      relevant = busy_periods.select { |period| period.intersects?(starts_at, ends_at) }
      subtract(starts_at, ends_at, merge_and_clip(relevant, starts_at, ends_at))
    end

    def window_boundaries(date, window)
      window.map do |minutes|
        hour, minute = minutes.divmod(60)
        @config.timezone.local_time(date.year, date.month, date.day, hour, minute, 0).utc
      end
    rescue TZInfo::PeriodNotFound, TZInfo::AmbiguousTime => e
      raise Error, "availability boundary is invalid on #{date} because of daylight saving time (#{e.class})"
    end

    def merge_and_clip(periods, starts_at, ends_at)
      clipped = periods.map { |period| clip(period, starts_at, ends_at) }.sort_by(&:first)

      clipped.each_with_object([]) do |interval, merged|
        merge_interval(merged, interval)
      end
    end

    def clip(period, starts_at, ends_at)
      [[period.starts_at, starts_at].max, [period.ends_at, ends_at].min]
    end

    def merge_interval(merged, interval)
      return merged << interval if merged.empty? || interval.first > merged.last.last

      merged.last[1] = interval.last if interval.last > merged.last.last
    end

    def subtract(starts_at, ends_at, busy)
      cursor = starts_at
      slots = []
      busy.each do |busy_start, busy_end|
        slots << Slot.new(cursor, busy_start) if busy_start > cursor
        cursor = busy_end if busy_end > cursor
      end
      slots << Slot.new(cursor, ends_at) if cursor < ends_at
      slots
    end

    def long_enough?(slot)
      (slot.ends_at - slot.starts_at) >= (@config.minimum_slot_minutes * 60)
    end
  end
end
