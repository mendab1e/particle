# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Availability::CLI do
  subject(:run_cli) { cli.run }

  let(:directory) { Dir.mktmpdir }
  let(:output) { StringIO.new }
  let(:error) { StringIO.new }
  let(:cli) do
    described_class.new(
      args: arguments,
      output: output,
      error: error,
      env: {},
      working_directory: directory,
      random_path: -> { 'fixed-private-path' }
    )
  end

  after { FileUtils.remove_entry(directory) }

  describe '#run' do
    context 'with the setup command' do
      let(:arguments) do
        ['setup', '--server-name', 'calendar.example.com', '--url-path', '/secret-path/']
      end

      before { run_cli }

      it 'creates a protected example configuration', :aggregate_failures do
        path = File.join(directory, 'particle.yml')

        expect(File.read(path)).to eq(File.read(Availability::Assets.example_config_path))
        expect(File.stat(path).mode & 0o777).to eq(0o600)
      end

      it 'creates a customized Nginx example', :aggregate_failures do
        nginx = File.read(File.join(directory, 'particle.nginx.conf'))

        expect(nginx).to include('server_name calendar.example.com;', 'location = /secret-path/')
        expect(nginx).to include(%(alias "#{directory}/public/index.html";))
        expect(nginx).not_to include('<%=')
      end

      it 'creates the configured output directory' do
        expect(File).to be_directory(File.join(directory, 'public'))
      end

      it 'reports the created files without printing configuration contents', :aggregate_failures do
        expect(output.string).to include('particle.yml (mode 0600)', 'particle.nginx.conf')
        expect(output.string).not_to include('CALENDAR_MAIN_URL')
      end
    end

    context 'when setup would replace an existing config' do
      let(:arguments) { ['setup'] }
      let(:config_path) { File.join(directory, 'particle.yml') }

      before { File.write(config_path, 'known secret config') }

      it 'fails without changing or partially creating setup files', :aggregate_failures do
        expect(run_cli).to eq(described_class::ERROR)
        expect(File.read(config_path)).to eq('known secret config')
        expect(File).not_to exist(File.join(directory, 'particle.nginx.conf'))
        expect(error.string).to include('Refusing to overwrite existing file')
      end
    end

    context 'when setup receives an unsafe Nginx value' do
      let(:arguments) { ['setup', '--server-name', "example.com;\ninclude bad.conf"] }

      it 'fails before creating any files', :aggregate_failures do
        expect(run_cli).to eq(described_class::ERROR)
        expect(File).not_to exist(File.join(directory, 'particle.yml'))
        expect(File).not_to exist(File.join(directory, 'particle.nginx.conf'))
      end
    end

    context 'with the generate command and a disabled configuration' do
      let(:arguments) { ['generate'] }
      let(:config_path) { File.join(directory, 'particle.yml') }

      before do
        File.write(config_path, <<~YAML)
          enabled: false
          timezone: Europe/Berlin
          calendar_urls: []
          days_to_show: 2
          availability:
            default:
              - start: "09:00"
                end: "17:00"
        YAML
      end

      it 'generates the static site using working-directory defaults', :aggregate_failures do
        expect(run_cli).to eq(described_class::SUCCESS)
        expect(File.read(File.join(directory, 'public', 'index.html'))).to include('Calendar not available')
        expect(File).to exist(File.join(directory, 'public', 'robots.txt'))
      end
    end

    context 'with an unknown command' do
      let(:arguments) { ['explode'] }

      it 'returns a usage error' do
        expect(run_cli).to eq(described_class::USAGE_ERROR)
      end
    end

    context 'with the version command' do
      let(:arguments) { ['version'] }

      it 'prints the gem version' do
        run_cli

        expect(output.string).to eq("Particle #{Availability::VERSION}\n")
      end
    end
  end
end
