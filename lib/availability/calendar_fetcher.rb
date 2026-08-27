# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'

require_relative 'calendar_url'

module Availability
  # Downloads private calendar feeds with bounded redirects, timeouts, and size.
  class CalendarFetcher
    MAX_REDIRECTS = 5
    MAX_BYTES = 20 * 1024 * 1024

    def initialize(open_timeout: 10, read_timeout: 30)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def fetch(url, label: 'Calendar', redirects_left: MAX_REDIRECTS)
      uri = URI.parse(CalendarUrl.normalize(url))
      validate_uri!(uri, label)
      response, body = request(uri, label)
      handle_response(response, body, uri, label, redirects_left)
    rescue FetchError
      raise
    rescue URI::InvalidURIError
      raise FetchError, "#{label} has an invalid URL"
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise FetchError, "#{label} download failed (#{e.class})"
    end

    private

    def handle_response(response, body, uri, label, redirects_left)
      return body if response.is_a?(Net::HTTPSuccess)
      return follow_redirect(response, uri, label, redirects_left) if response.is_a?(Net::HTTPRedirection)

      raise FetchError, "#{label} download failed with HTTP #{response.code}"
    end

    def follow_redirect(response, uri, label, redirects_left)
      raise FetchError, "#{label} returned too many redirects" if redirects_left.zero?

      location = response['location']
      raise FetchError, "#{label} returned a redirect without a location" if location.nil? || location.empty?

      fetch(URI.join(uri, location).to_s, label: label, redirects_left: redirects_left - 1)
    end

    def validate_uri!(uri, label)
      return if uri.is_a?(URI::HTTP) && uri.host && %w[http https].include?(uri.scheme)

      raise FetchError, "#{label} has an invalid HTTP(S) URL"
    end

    def request(uri, label)
      request = build_request(uri)
      Net::HTTP.start(uri.host, uri.port, **connection_options(uri)) do |http|
        read_response(http, request, label)
      end
    end

    def build_request(uri)
      Net::HTTP::Get.new(uri.request_uri).tap do |request|
        request['User-Agent'] = 'availability-static-generator/1.0'
        request['Accept'] = 'text/calendar, text/plain;q=0.9, */*;q=0.1'
      end
    end

    def connection_options(uri)
      {
        use_ssl: uri.scheme == 'https',
        open_timeout: @open_timeout,
        read_timeout: @read_timeout
      }
    end

    def read_response(http, request, label)
      result = nil
      http.request(request) do |response|
        body = stream_body(response, label) if response.is_a?(Net::HTTPSuccess)
        result = [response, body]
      end
      result
    end

    def stream_body(response, label)
      body = String.new(encoding: Encoding::BINARY)
      response.read_body do |chunk|
        if body.bytesize + chunk.bytesize > MAX_BYTES
          raise FetchError, "#{label} response exceeded #{MAX_BYTES / 1_048_576} MB"
        end

        body << chunk
      end
      body
    end
  end
end
