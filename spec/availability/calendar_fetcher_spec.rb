# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Availability::CalendarFetcher do
  describe '#fetch' do
    subject(:fetch_calendar) do
      described_class.new(open_timeout: 1, read_timeout: 1).fetch(url, label: label)
    end

    let(:label) { 'Calendar 1' }

    context 'when the endpoint redirects' do
      let(:url) { 'https://calendar.test/start?token=private' }

      before do
        stub_request(:get, url).to_return(status: 302, headers: { 'Location' => '/feed.ics' })
        stub_request(:get, 'https://calendar.test/feed.ics').to_return(status: 200, body: 'calendar body')
      end

      it 'follows the redirect' do
        expect(fetch_calendar).to eq('calendar body')
      end
    end

    context 'with a webcal URL' do
      let(:url) { 'webcal://calendar.test/feed.ics?token=private' }

      before do
        stub_request(:get, 'https://calendar.test/feed.ics?token=private')
          .to_return(status: 200, body: 'calendar body')
      end

      it 'downloads it over HTTPS' do
        expect(fetch_calendar).to eq('calendar body')
      end
    end

    context 'when the endpoint returns an error' do
      let(:url) { 'https://calendar.test/feed.ics?secret=do-not-log' }
      let(:label) { 'Calendar 2' }

      before { stub_request(:get, url).to_return(status: 503) }

      it 'identifies the calendar without leaking URL credentials' do
        expect { fetch_calendar }
          .to raise_error(Availability::FetchError, /Calendar 2 download failed with HTTP 503/)
      end
    end

    context 'when the response exceeds the byte limit' do
      let(:url) { 'https://calendar.test/oversized.ics' }

      before do
        stub_const('Availability::CalendarFetcher::MAX_BYTES', 10)
        stub_request(:get, url).to_return(status: 200, body: 'x' * 11)
      end

      it 'aborts the download' do
        expect { fetch_calendar }
          .to raise_error(Availability::FetchError, /Calendar 1 response exceeded/)
      end
    end
  end
end
