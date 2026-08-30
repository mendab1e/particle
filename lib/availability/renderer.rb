# frozen_string_literal: true

require 'cgi'
require 'erb'

module Availability
  # Renders calculated availability into a self-contained static HTML page.
  class Renderer
    ROBOTS = "User-agent: *\nDisallow: /\n"

    def initialize(template_path:)
      @template = ERB.new(File.read(template_path), trim_mode: '-')
    end

    def render(days:, generated_at:, timezone:, enabled:, today:, days_to_show:)
      view = View.new(
        days: days,
        generated_at: generated_at,
        timezone: timezone,
        enabled: enabled,
        today: today,
        days_to_show: days_to_show
      )
      @template.result(view.template_binding)
    end

    # Exposes only display-safe availability values and formatting helpers to ERB.
    class View
      WEEKDAYS = %w[monday tuesday wednesday thursday friday saturday sunday].freeze

      attr_reader :enabled, :today

      def initialize(days:, generated_at:, timezone:, enabled:, today:, days_to_show:)
        @days = days
        @generated_at = generated_at
        @timezone = timezone
        @enabled = enabled
        @today = today
        @days_to_show = days_to_show
      end

      def template_binding
        binding
      end

      def h(value)
        CGI.escapeHTML(value.to_s)
      end

      def format_date(date)
        "#{date.strftime('%A')}, #{date.day} #{date.strftime('%B %Y')}"
      end

      def format_compact_date(date)
        date.strftime('%a %-d %b')
      end

      def format_week_label(week)
        first_date = week.compact.first.date
        monday = first_date - (first_date.cwday - 1)
        "Week of #{monday.day} #{monday.strftime('%B %Y')}"
      end

      def format_time(time)
        @timezone.to_local(time.getutc).strftime('%H:%M')
      end

      def weeks
        return [] if @days.empty?

        padded_days = Array.new(@days.first.date.cwday - 1) + @days
        padded_days.concat(Array.new((7 - padded_days.length) % 7))
        padded_days.each_slice(7).to_a
      end

      def weekdays
        WEEKDAYS
      end

      def updated_at
        @timezone.to_local(@generated_at.getutc).strftime('%-d %b %Y, %H:%M %Z')
      end

      def timezone_name
        @timezone.identifier
      end

      def period_description
        final_date = @today + @days_to_show - 1
        return @today.strftime('%-d %b %Y') if final_date == @today

        start_with_year = @today.strftime('%-d %b %Y')
        final_with_year = final_date.strftime('%-d %b %Y')
        return "#{start_with_year}–#{final_with_year}" if @today.year != final_date.year

        return "#{@today.day}–#{final_with_year}" if @today.month == final_date.month

        "#{@today.strftime('%-d %b')}–#{final_with_year}"
      end
    end
  end
end
