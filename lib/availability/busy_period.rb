# frozen_string_literal: true

module Availability
  BusyPeriod = Data.define(:starts_at, :ends_at) do
    alias_method :initialize_data, :initialize

    def initialize(starts_at:, ends_at:)
      raise ArgumentError, 'busy period end must be after start' unless ends_at > starts_at

      initialize_data(starts_at: starts_at.getutc.freeze, ends_at: ends_at.getutc.freeze)
    end

    def intersects?(starts_at, ends_at)
      self.starts_at < ends_at && self.ends_at > starts_at
    end

    private :initialize_data
  end

  Slot = Data.define(:starts_at, :ends_at) do
    alias_method :initialize_data, :initialize

    def initialize(starts_at:, ends_at:)
      raise ArgumentError, 'slot end must be after start' unless ends_at > starts_at

      initialize_data(starts_at: starts_at.getutc.freeze, ends_at: ends_at.getutc.freeze)
    end

    private :initialize_data
  end

  DayAvailability = Data.define(:date, :slots) do
    alias_method :initialize_data, :initialize

    def initialize(date:, slots:)
      initialize_data(date: date, slots: slots.dup.freeze)
    end

    private :initialize_data
  end
end
