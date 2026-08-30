# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Availability::Config do
  describe '.load' do
    subject(:load_config) { described_class.load(path) }

    context 'when the file is missing' do
      let(:path) { '/definitely/missing/availability.yml' }

      it 'raises a configuration error' do
        expect { load_config }
          .to raise_error(Availability::ConfigError, /configuration file not found/)
      end
    end

    context 'when the YAML is invalid' do
      let(:file) { Tempfile.new(['availability', '.yml']) }
      let(:path) { file.path }

      before do
        file.write('availability: [unterminated')
        file.close
      end

      after { file.unlink }

      it 'raises a configuration error' do
        expect { load_config }.to raise_error(Availability::ConfigError, /invalid YAML/)
      end
    end
  end

  describe '#initialize' do
    subject(:config) { described_class.new(attributes, env: env) }

    let(:attributes) { config_attributes }
    let(:env) { {} }

    context 'with an environment-variable URL reference' do
      let(:attributes) do
        config_attributes('calendar_urls' => ['${PRIVATE_ICS}'])
      end
      let(:env) do
        { 'PRIVATE_ICS' => 'https://example.test/secret.ics?token=hidden' }
      end

      it 'resolves the exact reference without evaluating ERB' do
        expect(config.calendar_urls).to eq(['https://example.test/secret.ics?token=hidden'])
      end
    end

    context 'with a webcal calendar URL' do
      let(:attributes) do
        config_attributes('calendar_urls' => ['webcal://example.test/private.ics?token=hidden'])
      end

      it 'normalizes it to HTTPS' do
        expect(config.calendar_urls).to eq(['https://example.test/private.ics?token=hidden'])
      end
    end

    context 'when generation is disabled without calendar URLs' do
      let(:attributes) do
        config_attributes('enabled' => false, 'calendar_urls' => [])
      end

      it 'allows an empty calendar list' do
        expect(config.calendar_urls).to be_empty
      end
    end

    context 'when generation is disabled with a missing secret reference' do
      let(:attributes) do
        config_attributes('enabled' => false, 'calendar_urls' => ['${MISSING_SECRET}'])
      end

      it 'does not resolve unused secrets' do
        expect(config.calendar_urls).to be_empty
      end
    end

    context 'with a malformed availability start' do
      let(:attributes) do
        config_attributes(
          'availability' => { 'default' => { 'start' => '9am', 'end' => '17:00' } }
        )
      end

      it 'identifies the relevant configuration key' do
        expect { config }
          .to raise_error(Availability::ConfigError, /availability\.default\[0\]\.start/)
      end
    end

    context 'when an availability window starts after it ends' do
      let(:attributes) do
        config_attributes(
          'availability' => { 'default' => { 'start' => '17:00', 'end' => '09:00' } }
        )
      end

      it 'rejects the window' do
        expect { config }.to raise_error(Availability::ConfigError, /start must be earlier/)
      end
    end

    context 'with midnight as an availability window end' do
      let(:attributes) do
        config_attributes(
          'availability' => { 'default' => { 'start' => '09:00', 'end' => '00:00' } }
        )
      end

      it 'interprets midnight as the end of the calendar day' do
        expect(config.windows_for(Date.new(2026, 8, 26))).to eq([[9 * 60, 24 * 60]])
      end
    end

    context 'with an unknown timezone' do
      let(:attributes) { config_attributes('timezone' => 'Mars/Olympus') }

      it 'rejects the timezone' do
        expect { config }.to raise_error(Availability::ConfigError, /timezone is unknown/)
      end
    end

    context 'without a first day of the week' do
      it 'defaults the calendar layout to Monday' do
        expect(config.first_day_of_week).to eq('monday')
      end
    end

    context 'with a configured first day of the week' do
      let(:attributes) { config_attributes('first_day_of_week' => 'sunday') }

      it 'accepts a weekday name' do
        expect(config.first_day_of_week).to eq('sunday')
      end
    end

    context 'with an invalid first day of the week' do
      let(:attributes) { config_attributes('first_day_of_week' => 'weekend') }

      it 'rejects the invalid weekday' do
        expect { config }.to raise_error(Availability::ConfigError, /first_day_of_week must be one of/)
      end
    end

    context 'with no calendars while enabled' do
      let(:attributes) { config_attributes('calendar_urls' => []) }

      it 'rejects the empty list' do
        expect { config }.to raise_error(Availability::ConfigError, /at least one URL/)
      end
    end

    context 'with an unknown top-level key' do
      let(:attributes) { config_attributes('minimum_slot_minute' => 60) }

      it 'rejects the typo instead of applying a default' do
        expect { config }.to raise_error(Availability::ConfigError, /unknown key: minimum_slot_minute/)
      end
    end

    context 'with an unknown event buffer key' do
      let(:attributes) do
        config_attributes('event_buffer' => { 'before_minute' => 30 })
      end

      it 'rejects the typo instead of applying a zero buffer' do
        expect { config }.to raise_error(Availability::ConfigError, /event_buffer has unknown key: before_minute/)
      end
    end

    context 'when the displayed range exceeds the safety limit' do
      let(:attributes) { config_attributes('days_to_show' => described_class::MAX_DAYS_TO_SHOW + 1) }

      it 'rejects the range' do
        expect { config }.to raise_error(Availability::ConfigError, /days_to_show must be at most/)
      end
    end

    context 'when the calendar count exceeds the safety limit' do
      let(:attributes) do
        urls = Array.new(described_class::MAX_CALENDAR_URLS + 1) { |index| "https://calendar#{index}.example/feed.ics" }
        config_attributes('calendar_urls' => urls)
      end

      it 'rejects the calendar list' do
        expect { config }.to raise_error(Availability::ConfigError, /calendar_urls must contain at most/)
      end
    end
  end
end
