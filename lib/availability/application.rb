# frozen_string_literal: true

module Availability
  # Coordinates configuration, calendar ingestion, calculation, and publishing.
  class Application
    DEFAULT_CLOCK = -> { Time.now.utc }
    DEFAULT_FAVICON_PATH = Assets.favicon_path

    def initialize(config_path:, output_dir:, template_path:, output: $stdout, clock: DEFAULT_CLOCK,
                   fetcher: CalendarFetcher.new, favicon_path: DEFAULT_FAVICON_PATH)
      @config_path = config_path
      @output_dir = output_dir
      @template_path = template_path
      @favicon_path = favicon_path
      @output = output
      @clock = clock
      @fetcher = fetcher
    end

    def run
      config = Config.load(@config_path)
      now = @clock.call.utc
      today = config.timezone.to_local(now).to_date
      days = config.enabled ? calculate_days(config, now, today) : disabled_days(config, now)

      publish(config, now, today, days)
      true
    end

    private

    def calculate_days(config, now, today)
      log(config, now, "Fetching #{config.calendar_urls.length} calendars")
      range_start, range_end, final_date = expansion_range(config, today)
      parser = CalendarParser.new(timezone: config.timezone)
      busy_periods = fetch_periods(config, parser, range_start, range_end, now)

      log(config, now, "Calculating availability for #{today}..#{final_date - 1}")
      AvailabilityCalculator.new(config).calculate(start_date: today, busy_periods: busy_periods)
    end

    def disabled_days(config, now)
      log(config, now, 'Availability is disabled; calendars were not fetched')
      []
    end

    def expansion_range(config, today)
      final_date = today + config.days_to_show
      range_start = local_midnight(config, today) - (config.buffer_after_minutes * 60)
      range_end = local_midnight(config, final_date) + (config.buffer_before_minutes * 60)
      [range_start, range_end, final_date]
    end

    def local_midnight(config, date)
      config.timezone.local_time(date.year, date.month, date.day, 0, 0, 0).utc
    end

    def publish(config, now, today, days)
      html = render_page(config, now, today, days)
      AtomicWriter.write_all(@output_dir, generated_files(html))
      log(config, now, "Generated #{File.join(@output_dir, 'index.html')}")
    end

    def render_page(config, now, today, days)
      Renderer.new(template_path: @template_path).render(
        days: days,
        generated_at: now,
        timezone: config.timezone,
        enabled: config.enabled,
        today: today,
        days_to_show: config.days_to_show,
        first_day_of_week: config.first_day_of_week
      )
    end

    def generated_files(html)
      {
        'favicon.svg' => File.binread(@favicon_path),
        'robots.txt' => Renderer::ROBOTS,
        'index.html' => html
      }
    end

    def fetch_periods(config, parser, range_start, range_end, now)
      config.calendar_urls.each_with_index.flat_map do |url, index|
        label = "Calendar #{index + 1}"
        body = @fetcher.fetch(url, label: label)
        periods = parser.parse(body, range_start: range_start, range_end: range_end, label: label)
        log_ignored_events(config, now, label, parser.ignored_event_count)
        log(config, now, "#{label} fetched and parsed successfully")
        periods
      end
    end

    def log_ignored_events(config, now, label, count)
      return if count.zero?

      noun = count == 1 ? 'event' : 'events'
      log(config, now, "#{label} ignored #{count} malformed #{noun}")
    end

    def log(config, moment, message)
      timestamp = config.timezone.to_local(moment).strftime('%Y-%m-%d %H:%M:%S')
      @output.puts("[#{timestamp}] #{message}")
    end
  end
end
