# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Availability::AvailabilityCalculator do
  describe '#calculate' do
    subject(:calculated_days) do
      described_class.new(config).calculate(start_date: start_date, busy_periods: busy_periods)
    end

    let(:date) { Date.new(2026, 8, 26) }
    let(:start_date) { date }
    let(:config) { build_config }
    let(:busy_periods) { [] }

    context 'when one event interrupts the availability window' do
      let(:busy_periods) { [period(date, 12, 13)] }

      it 'returns the free time on either side' do
        expect(slot_times(calculated_days.first)).to eq([['09:00', '12:00'], ['13:00', '22:00']])
      end
    end

    context 'when events from multiple calendars overlap or touch' do
      let(:busy_periods) do
        [period(date, 10, 12), period(date, 11, 14), period(date, 14, 15)]
      end

      it 'merges them before subtracting busy time' do
        expect(slot_times(calculated_days.first)).to eq([['09:00', '10:00'], ['15:00', '22:00']])
      end
    end

    context 'when an event crosses the availability boundary' do
      let(:busy_periods) { [period(date, 8, 10)] }

      it 'clips the event to the configured window' do
        expect(slot_times(calculated_days.first)).to eq([['10:00', '22:00']])
      end
    end

    context 'when an event spans midnight' do
      let(:config) { build_config('days_to_show' => 2) }
      let(:busy_periods) { [period(date, 21, 10, end_date: date + 1)] }

      it 'affects both dates', :aggregate_failures do
        expect(slot_times(calculated_days[0])).to eq([['09:00', '21:00']])
        expect(slot_times(calculated_days[1])).to eq([['10:00', '22:00']])
      end
    end

    context 'when an all-day event covers the date' do
      let(:busy_periods) do
        [Availability::BusyPeriod.new(local_time(date, 0), local_time(date + 1, 0))]
      end

      it 'returns no free slots' do
        expect(calculated_days.first.slots).to be_empty
      end
    end

    context 'with a weekday-specific window' do
      let(:start_date) { Date.new(2026, 8, 30) }
      let(:config) do
        build_config('availability' => {
                       'sunday' => [{ 'start' => '10:00', 'end' => '18:00' }]
                     })
      end

      it 'replaces the default window' do
        expect(slot_times(calculated_days.first)).to eq([['10:00', '18:00']])
      end
    end

    context 'with an unavailable weekday' do
      let(:start_date) { Date.new(2026, 8, 31) }
      let(:config) do
        build_config('availability' => { 'monday' => { 'unavailable' => true } })
      end

      it 'returns no free slots' do
        expect(calculated_days.first.slots).to be_empty
      end
    end

    context 'with a minimum slot duration' do
      let(:config) { build_config('minimum_slot_minutes' => 60) }
      let(:busy_periods) { [period(date, 9, 21, start_minute: 30)] }

      it 'discards shorter free intervals' do
        expect(slot_times(calculated_days.first)).to eq([['21:00', '22:00']])
      end
    end

    context 'with event buffers' do
      let(:config) do
        build_config('event_buffer' => { 'before_minutes' => 30, 'after_minutes' => 30 })
      end
      let(:busy_periods) { [period(date, 15, 16)] }

      it 'applies both buffers before subtraction' do
        expect(slot_times(calculated_days.first)).to eq([['09:00', '14:30'], ['16:30', '22:00']])
      end
    end

    context 'with multiple availability windows' do
      let(:config) do
        build_config(
          'availability' => {
            'default' => [
              { 'start' => '09:00', 'end' => '13:00' },
              { 'start' => '14:00', 'end' => '22:00' }
            ]
          }
        )
      end

      it 'preserves the intentionally unavailable gap' do
        expect(slot_times(calculated_days.first)).to eq([['09:00', '13:00'], ['14:00', '22:00']])
      end
    end

    context 'when crossing the Europe/Berlin spring DST transition' do
      let(:start_date) { Date.new(2026, 3, 29) }
      let(:config) do
        build_config('availability' => {
                       'default' => [{ 'start' => '01:00', 'end' => '04:00' }]
                     })
      end

      it 'uses elapsed time while retaining local wall times', :aggregate_failures do
        slot = calculated_days.first.slots.first

        expect(slot.ends_at - slot.starts_at).to eq(2 * 60 * 60)
        expect(slot_times(calculated_days.first)).to eq([['01:00', '04:00']])
      end
    end
  end
end
