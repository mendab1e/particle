# Particle

Particle, from Party Cal, is a small Ruby command-line static-site generator. It downloads one or more private iCalendar subscriptions, treats every valid event in every feed as busy, merges the busy periods, subtracts them from configured availability hours, and writes a mobile-friendly four-week view containing only free time.

There is no Rails application, database, browser API, booking flow, or Ruby process at request time. Nginx serves the files in `public/` directly.

```text
private ICS feeds → Ruby generator → public/index.html → Nginx → HTTPS
```

## Privacy and failure model

Calendar URLs are used only by the generator. The generated HTML contains dates, calculated free intervals, and an update timestamp. It never renders titles, descriptions, locations, attendees, UIDs, calendar names, source URLs, or raw ICS. Logs refer to feeds only as `Calendar 1`, `Calendar 2`, and so on.

All configured feeds must download and be parseable as calendars. If any feed fails, generation exits non-zero before publishing. Individual malformed events are silently ignored, which can display false free time if a skipped event was intended to be busy. Output is prepared in temporary files on the same filesystem and `index.html` is atomically renamed only after the complete calculation and render succeed, preserving the previously known-good page.

The page includes `noindex, nofollow, noarchive`, and `public/robots.txt` disallows crawling. These are requests to well-behaved crawlers, **not authentication or access control**. A long random path reduces accidental discovery but does not prevent a recipient from sharing the URL.

## Requirements and installation

- Ruby 3.4.8 (pinned in `.ruby-version`)
- Bundler 2.6 or newer
- A normal Linux VPS for production

Install dependencies:

```bash
git clone YOUR_REPOSITORY_URL availability
cd availability
gem install bundler
bundle config set --local path vendor/bundle
bundle install
cp config/availability.example.yml config/availability.yml
```

The core libraries are:

- [`icalendar`](https://github.com/icalendar/icalendar) to parse RFC 5545 data;
- [`icalendar-recurrence`](https://github.com/icalendar/icalendar-recurrence), backed by `ice_cube`, to expand only occurrences intersecting the output range;
- `ActiveSupport::TimeWithZone` and `tzinfo` to retain named time zones and wall-clock recurrence times across DST;
- standard-library `Net::HTTP`, ERB, YAML, and filesystem primitives;
- RSpec and WebMock for tests.

`icalendar` parses recurrence properties but does not itself produce occurrence instances. `icalendar-recurrence` supplies bounded `occurrences_between` expansion, including common `RRULE`, `RDATE`, and `EXDATE` behavior. The generator also handles exact detached `RECURRENCE-ID` overrides and cancellations so a moved instance replaces its original occurrence.

## Configuration

The default path is `config/availability.yml`. That file is ignored by Git; only `config/availability.example.yml` is committed. Select another file with `--config PATH` or `AVAILABILITY_CONFIG`.

```yaml
enabled: true
timezone: Europe/Berlin

calendar_urls:
  - "${CALENDAR_MAIN_URL}"
  - "${CALENDAR_EXTRA_URL}"

days_to_show: 28
minimum_slot_minutes: 60

event_buffer:
  before_minutes: 30
  after_minutes: 30

availability:
  default:
    - start: "09:00"
      end: "13:00"
    - start: "14:00"
      end: "00:00"

  sunday:
    - start: "10:00"
      end: "18:00"

  monday:
    unavailable: true
```

### Calendar feeds and secrets

`calendar_urls` accepts HTTPS, HTTP, or `webcal://` subscription URLs. Webcal URLs are downloaded over HTTPS. Every feed contributes busy time with OR semantics: if any calendar is busy, the shared view is busy. Overlapping and adjacent periods are merged before subtraction.

A URL may be literal, or an exact `${UPPERCASE_ENV_NAME}` placeholder. No ERB is evaluated, so the YAML file cannot execute Ruby code.

For simple VPS use, put literal URLs only in the ignored production file and protect it:

```bash
chmod 600 config/availability.yml
```

For environment-based configuration:

```bash
export CALENDAR_MAIN_URL='https://calendar.example/private-a.ics?token=...'
export CALENDAR_EXTRA_URL='https://calendar.example/private-b.ics?token=...'
bundle exec bin/generate
```

Do not paste private subscription URLs into source control, shell history, issue trackers, or Nginx configuration. The generator never prints them, even when a request fails.

### Availability windows

`availability.default` is required and defines potential availability. Times use strict local 24-hour `HH:MM` syntax. One mapping is accepted for convenience, but the documented array form supports split windows without redesign:

```yaml
availability:
  default:
    - start: "09:00"
      end: "13:00"
    - start: "14:00"
      end: "00:00"
```

The 13:00–14:00 gap is intentionally unavailable. `00:00` is accepted as a window end and means midnight at the end of that calendar day, matching calendar UI conventions. Windows may touch but cannot overlap, and each start must be earlier than its end. Other overnight availability windows are deliberately not accepted; express availability on each calendar day separately.

Any weekday can replace the default for that entire weekday: `monday`, `tuesday`, `wednesday`, `thursday`, `friday`, `saturday`, or `sunday`. An override is a replacement, not a merge with `default`.

```yaml
availability:
  default:
    - start: "09:00"
      end: "00:00"
  sunday:
    - start: "10:00"
      end: "18:00"
  monday:
    unavailable: true
```

### Minimum slots and event buffers

`minimum_slot_minutes` removes shorter free fragments after subtraction. The default is `0`.

`event_buffer.before_minutes` and `after_minutes` enlarge each event before busy periods are merged. Both default to `0`. Buffers are clipped during subtraction and can never create free time outside configured windows.

### Disabling the page

Set `enabled: false` to skip all network access and render a “Calendar not available” page. `calendar_urls` may be empty in this mode. This is useful when availability should be withdrawn without changing Nginx.

## Running and testing

Generate manually:

```bash
bundle exec bin/generate
```

Useful options:

```bash
bundle exec bin/generate --config /etc/availability.yml --output /var/www/availability
```

Successful output looks like:

```text
[2026-08-26 09:17:01] Fetching 2 calendars
[2026-08-26 09:17:02] Calendar 1 fetched and parsed successfully
[2026-08-26 09:17:02] Calendar 2 fetched and parsed successfully
[2026-08-26 09:17:02] Calculating availability for 2026-08-26..2026-09-22
[2026-08-26 09:17:02] Generated /opt/availability/public/index.html
```

Run the complete test suite:

```bash
bundle exec rspec
bundle exec rubocop

# Runs both RSpec and RuboCop:
bundle exec rake
```

RuboCop targets Ruby 3.4 and loads the official RSpec, Rake, and performance plugins. New cops are enabled. To apply safe formatting corrections locally, run `bundle exec rubocop -a`; review behavior-changing corrections from `bundle exec rubocop -A` before keeping them.

Tests cover interval subtraction, overlap and adjacency merging, multiple-calendar semantics, availability boundaries, events spanning midnight, all-day events, weekday replacement/unavailable days, minimum duration, buffers, split windows, recurrence exclusions and detached overrides, UTC/source-zone conversion, and the Europe/Berlin DST transition. Integration tests also assert that fixture metadata and source URL secrets never reach HTML.

## VPS deployment

The following example keeps the repository out of Nginx's document tree:

```text
Ruby generator
      ↓
/opt/availability/public
      ↓
Nginx
      ↓
HTTPS
```

Create a dedicated account or deploy as an unprivileged service user, install Ruby 3.4.8, and place the project at `/opt/availability`:

```bash
cd /opt/availability
bundle config set --local path vendor/bundle
bundle config set --local without development:test
bundle install
cp config/availability.example.yml config/availability.yml
chmod 600 config/availability.yml
mkdir -p log public
bundle exec bin/generate
```

Ensure the generator user can replace files in `public/`, while the Nginx worker can read them. Do not set Nginx `root` or `alias` to `/opt/availability`; only map its `public` files.

### Nginx and a random path

[`deploy/availability.nginx.conf`](deploy/availability.nginx.conf) contains a complete server-block example. Its exact-match locations expose only `public/index.html` and `public/robots.txt` at a path such as:

```text
https://example.com/a8f2c9e71d4b/
```

Copy and edit it, then validate and reload:

```bash
sudo cp deploy/availability.nginx.conf /etc/nginx/sites-available/availability
sudo ln -s /etc/nginx/sites-available/availability /etc/nginx/sites-enabled/availability
sudo nginx -t
sudo systemctl reload nginx
```

Configure TLS certificates separately. The random path belongs only in Nginx; calendar calculation and generated links do not depend on it. On a dedicated hostname, you may additionally serve the generated `robots.txt` at the origin-wide `/robots.txt`. On a shared hostname, take care not to change crawling policy for unrelated pages.

### Hourly cron regeneration

Confirm the absolute Bundler path with `command -v bundle`, then add a crontab entry for the unprivileged generator user. It intentionally does not run at minute zero:

```cron
PATH=/usr/local/bin:/usr/bin:/bin
17 * * * * cd /opt/availability && bundle exec bin/generate >> /opt/availability/log/generator.log 2>&1
```

If the Ruby installation lives elsewhere, put its `bin` directory first in `PATH` or use the absolute `bundle` path. Cron has a minimal environment. When YAML uses `${...}` placeholders, load protected environment values through a small root-owned wrapper or use a systemd timer with `EnvironmentFile=`; do not put secret URLs directly in the crontab.

Install [`deploy/availability.logrotate`](deploy/availability.logrotate) as `/etc/logrotate.d/availability`, or send output to syslog/systemd instead. A failed cron run exits non-zero and leaves the last successfully generated page online; monitor the exit code or log rather than assuming hourly freshness.

## Troubleshooting

- **Configuration file not found / invalid YAML:** verify `AVAILABILITY_CONFIG` or `--config`, indentation, and that secrets are readable by the generator user.
- **Missing environment variable:** an exact `${NAME}` URL placeholder requires `NAME` in the generator process, including cron/systemd.
- **Unknown timezone:** use an IANA identifier such as `Europe/Berlin`, not an informal abbreviation.
- **Calendar download failed:** test outbound DNS/TLS access from the generator account and confirm the subscription was not revoked. Logs intentionally omit the URL and query token.
- **Calendar parse failed:** download the feed securely and validate that it is ICS, not an HTML sign-in/error page. Individual malformed events are ignored, but a feed that cannot be parsed as a calendar still fails. Never paste it into public diagnostics.
- **Old update timestamp:** inspect cron logs. A stale page usually means a later run failed safely.
- **Permission denied while publishing:** the generator needs write permission on `public/`; Nginx needs read permission only.

## Known limits

The generator supports normal timed, all-day, overnight, multi-day, recurring, `EXDATE`, `RDATE`, and exact detached `RECURRENCE-ID` events. Floating timed events without a `TZID` are interpreted in the configured timezone. Malformed individual events are ignored. Rare recurrence features such as `RANGE=THISANDFUTURE`, non-IANA/custom time-zone definitions that cannot be mapped by the parser, and malformed feeds may be rejected or require feed-specific work.

HTTP validators (`ETag` and `Last-Modified`) are not persisted in this intentionally stateless version. Every successful run downloads every feed, prioritizing freshness and safe all-or-nothing generation.
