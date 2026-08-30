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
        "#{date.strftime('%A')}, #{date.day} #{date.strftime('%B')}"
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

      def period_description
        return 'during the next day' if @days_to_show == 1

        weeks, remaining_days = @days_to_show.divmod(7)
        return "during the next #{weeks} #{weeks == 1 ? 'week' : 'weeks'}" if remaining_days.zero?

        "during the next #{@days_to_show} days"
      end
    end
  end
end
