# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Availability::Application do
  describe '#run' do
    subject(:run_application) { application.run }

    let(:directory) { Dir.mktmpdir }
    let(:paths) do
      output_dir = File.join(directory, 'public')
      {
        config: File.join(directory, 'availability.yml'),
        output: output_dir,
        index: File.join(output_dir, 'index.html'),
        robots: File.join(output_dir, 'robots.txt'),
        template: File.expand_path('../../templates/index.html.erb', __dir__),
        fixture: File.expand_path('../fixtures/sample.ics', __dir__)
      }
    end
    let(:fixture) { File.read(paths.fetch(:fixture)) }
    let(:now) { Time.utc(2026, 8, 26, 7, 17, 0) }
    let(:output) { StringIO.new }
    let(:enabled) { true }
    let(:calendar_urls) { ['https://calendar.test/private.ics?token=super-secret'] }
    let(:fetcher) { instance_double(Availability::CalendarFetcher, fetch: fixture) }
    let(:application) do
      described_class.new(
        config_path: paths.fetch(:config),
        output_dir: paths.fetch(:output),
        template_path: paths.fetch(:template),
        output: output,
        clock: -> { now },
        fetcher: fetcher
      )
    end
    let(:config_contents) do
      <<~YAML
        enabled: #{enabled}
        timezone: Europe/Berlin
        calendar_urls: #{calendar_urls.to_json}
        days_to_show: 2
        minimum_slot_minutes: 30
        availability:
          default:
            - start: "09:00"
              end: "22:00"
      YAML
    end

    before { File.write(paths.fetch(:config), config_contents) }

    after { FileUtils.remove_entry(directory) }

    context 'when every calendar succeeds' do
      before { run_application }

      it 'completes successfully' do
        expect(run_application).to be(true)
      end

      it 'renders availability and the configured range', :aggregate_failures do
        html = File.read(paths.fetch(:index))
        expect(html).to include(
          '09:00–10:00',
          '11:30–22:00',
          'Party Cal: availability during the next 2 days',
          '<footer>Particle · last updated:'
        )
      end

      it 'renders Monday-first calendar rows with rounded gradient-accented card styling', :aggregate_failures do
        html = File.read(paths.fetch(:index))

        expect(html.index('data-weekday="monday"')).to be < html.index('Wednesday, 26 August')
        expect(html).to include(
          '--accent: #7c3aed',
          '--accent-start: #7dd3fc',
          '--accent-end: #fef08a',
          '--accent-gradient: linear-gradient(135deg, var(--accent-start), var(--accent-end))'
        )
        expect(html).to include('border-radius: 0.85rem')
      end

      it 'does not expose calendar metadata' do
        html = File.read(paths.fetch(:index))
        expect(html).not_to match(
          /Private strategy meeting|secret-attendee|super-secret|calendar\.test|fixture-event-id/
        )
      end

      it 'discourages crawling', :aggregate_failures do
        expect(File.read(paths.fetch(:index))).to include(
          'noindex, nofollow, noarchive, nosnippet, noimageindex',
          '<meta name="referrer" content="no-referrer">'
        )
        expect(File.read(paths.fetch(:robots))).to eq("User-agent: *\nDisallow: /\n")
      end

      it 'publishes an Nginx-readable index' do
        expect(File.stat(paths.fetch(:index)).mode & 0o777).to eq(0o644)
      end
    end

    context 'when generation is disabled' do
      let(:enabled) { false }
      let(:calendar_urls) { [] }
      let(:fetcher) { instance_spy(Availability::CalendarFetcher) }

      it 'publishes the disabled page without fetching calendars', :aggregate_failures do
        run_application

        expect(fetcher).not_to have_received(:fetch)
        expect(File.read(paths.fetch(:index))).to include('Calendar not available')
      end
    end

    context 'when a calendar fails' do
      let(:fetcher) { instance_double(Availability::CalendarFetcher) }

      before do
        FileUtils.mkdir_p(paths.fetch(:output))
        File.write(paths.fetch(:index), 'known good')
        allow(fetcher).to receive(:fetch).and_raise(Availability::FetchError, 'Calendar 1 failed')
      end

      it 'leaves the previous index untouched', :aggregate_failures do
        expect { run_application }.to raise_error(Availability::FetchError)
        expect(File.read(paths.fetch(:index))).to eq('known good')
      end
    end

    context 'when a calendar contains a malformed event' do
      let(:fixture) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:malformed-private-id
          SUMMARY:Private malformed event
          END:VEVENT
          BEGIN:VEVENT
          UID:valid-event
          DTSTART:20260827T120000Z
          DTEND:20260827T130000Z
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'logs only the sanitized ignored-event count', :aggregate_failures do
        run_application

        expect(output.string).to include('Calendar 1 ignored 1 malformed event')
        expect(output.string).not_to match(/malformed-private-id|Private malformed event/)
      end
    end

    context 'with the Nginx deployment example' do
      subject(:nginx_configuration) do
        File.read(File.expand_path('../../deploy/availability.nginx.conf', __dir__))
      end

      it 'publishes crawler policy at the origin root and suppresses indexing and caches', :aggregate_failures do
        expect(nginx_configuration).to include(
          'location = /robots.txt',
          'X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex"',
          'Cache-Control "private, no-store, max-age=0"',
          'Referrer-Policy "no-referrer"'
        )
      end

      it 'does not rely on a robots file below the private path' do
        expect(nginx_configuration).not_to include('location = /a8f2c9e71d4b/robots.txt')
      end
    end
  end
end
