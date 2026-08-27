# frozen_string_literal: true

module Availability
  BusyPeriod = Struct.new(:starts_at, :ends_at) do
    def initialize(starts_at, ends_at)
      raise ArgumentError, 'busy period end must be after start' unless ends_at > starts_at

      super(starts_at.utc, ends_at.utc)
    end

    def intersects?(starts_at, ends_at)
      self.starts_at < ends_at && self.ends_at > starts_at
    end
  end

  Slot = Struct.new(:starts_at, :ends_at)
  DayAvailability = Struct.new(:date, :slots)
end
