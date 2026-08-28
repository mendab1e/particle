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

    context 'with no calendars while enabled' do
      let(:attributes) { config_attributes('calendar_urls' => []) }

      it 'rejects the empty list' do
        expect { config }.to raise_error(Availability::ConfigError, /at least one URL/)
      end
    end
  end
end
