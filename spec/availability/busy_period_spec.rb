# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Availability::BusyPeriod do
  describe '.new' do
    subject(:busy_period) do
      described_class.new(
        Time.new(2026, 8, 27, 12, 0, 0, '+02:00'),
        Time.new(2026, 8, 27, 13, 0, 0, '+02:00')
      )
    end

    it 'creates an immutable UTC-backed value object', :aggregate_failures do
      expect(busy_period.starts_at).to eq(Time.utc(2026, 8, 27, 10))
      expect(busy_period.starts_at).to be_frozen
      expect { busy_period.starts_at = Time.now }.to raise_error(NoMethodError)
    end
  end
end
