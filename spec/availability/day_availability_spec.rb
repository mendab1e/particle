# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Availability::DayAvailability do
  describe '.new' do
    it 'does not retain a mutable slots array', :aggregate_failures do
      slots = []
      day = described_class.new(Date.new(2026, 8, 27), slots)
      slots << :unexpected

      expect(day.slots).to be_empty
      expect(day.slots).to be_frozen
    end
  end
end
