# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Availability::Renderer::View do
  subject(:view) do
    described_class.new(
      days: [],
      generated_at: Time.utc(2026, 8, 30, 10, 0, 0),
      timezone: TZInfo::Timezone.get('Europe/Berlin'),
      enabled: true,
      today: start_date,
      days_to_show: days_to_show,
      first_day_of_week: first_day_of_week
    )
  end

  let(:start_date) { Date.new(2026, 8, 30) }
  let(:days_to_show) { 28 }
  let(:first_day_of_week) { 'monday' }

  describe '#period_description' do
    context 'when the range stays within one month' do
      let(:days_to_show) { 2 }

      it 'renders a compact exact range' do
        expect(view.period_description).to eq('30–31 Aug 2026')
      end
    end

    context 'when the range crosses a month boundary' do
      it 'renders both month names' do
        expect(view.period_description).to eq('30 Aug–26 Sep 2026')
      end
    end

    context 'when the range crosses a year boundary' do
      let(:start_date) { Date.new(2026, 12, 31) }
      let(:days_to_show) { 2 }

      it 'renders both years' do
        expect(view.period_description).to eq('31 Dec 2026–1 Jan 2027')
      end
    end
  end

  describe '#timezone_name' do
    it 'uses the configured IANA timezone identifier' do
      expect(view.timezone_name).to eq('Europe/Berlin')
    end
  end

  describe '#format_week_label' do
    let(:day) { Availability::DayAvailability.new(date: Date.new(2026, 8, 30), slots: []) }

    it 'labels the containing Monday-first week by default' do
      expect(view.format_week_label([nil, nil, nil, nil, nil, nil, day])).to eq('Week of 24 August 2026')
    end

    context 'when Sunday is the configured first day' do
      let(:first_day_of_week) { 'sunday' }

      it 'labels the containing Sunday-first week' do
        expect(view.format_week_label([day, nil, nil, nil, nil, nil, nil])).to eq('Week of 30 August 2026')
      end
    end
  end

  describe '#weekdays' do
    context 'when Sunday is the configured first day' do
      let(:first_day_of_week) { 'sunday' }

      it 'rotates the weekday headings' do
        expect(view.weekdays).to eq(%w[sunday monday tuesday wednesday thursday friday saturday])
      end
    end
  end
end
