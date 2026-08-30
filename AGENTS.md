# Particle: agent context

## Purpose

Particle is a small Ruby 3.4.8 command-line static-site generator. It fetches one or more private iCalendar subscriptions and publishes a read-only availability page for the upcoming configured date range.

The core calculation is:

```text
configured potential availability
- union of busy periods from every calendar
= displayed free periods
```

This is deliberately not a web application. Do not introduce Rails, a database, accounts, booking, forms, a browser API, background-job frameworks, or a JavaScript SPA. Nginx serves the generated files in `public/`; Ruby is not involved at request time.

## Non-negotiable invariants

Preserve these properties in every change:

1. **Fail on feed-level errors.** If any enabled calendar cannot be fetched or parsed as a calendar, generation must fail. Individual malformed events are ignored, accepting the risk of potentially false free time.
2. **Keep the known-good page.** Prepare output before publishing and replace `public/index.html` atomically only after the complete run succeeds.
3. **Never leak calendar data.** Generated HTML, robots files, logs, errors, comments, hidden attributes, and client-side data must never contain calendar URLs, ICS contents, event titles, descriptions, locations, attendees, UIDs, or source names.
4. **Never fetch calendars in the browser.** Only the generator may contact private calendar endpoints.
5. **Union all valid busy time.** Every safely interpreted event in any configured calendar makes that period unavailable. Merge overlapping and adjacent busy intervals before subtraction.
6. **Use configured-zone wall time.** Normalize calculations through UTC while constructing and formatting boundaries in the configured IANA timezone. Preserve correct behavior across DST.
7. **Apply configuration in this order.** Choose the weekday window replacement, apply event buffers, clip/merge busy intervals, subtract them, then discard slots shorter than `minimum_slot_minutes`.
8. **Disabled means no feed access.** With `enabled: false`, do not resolve calendar secrets or perform network requests; render the unavailable page.

## Secret handling

`config/availability.yml` is ignored by Git and may contain real private subscription URLs. Treat it as a secret:

- Do not read, print, copy, summarize, or modify it unless the user explicitly asks.
- Never move its values into source, fixtures, documentation, shell output, or generated HTML.
- Use `config/availability.example.yml` and `spec/fixtures/` for development.
- Tests must use reserved/example hosts and obvious fake tokens.
- Logs and errors identify feeds only as `Calendar 1`, `Calendar 2`, and so on.

Configuration accepts literal `http:`, `https:`, or `webcal:` URLs and exact `${UPPERCASE_ENV_VAR}` placeholders. `webcal:` is normalized to `https:` before validation/fetching. YAML is loaded safely; do not add ERB evaluation.

## Architecture and data flow

```text
bin/generate
  -> Availability::Application
      -> Config
      -> CalendarFetcher (once per URL)
      -> CalendarParser (ICS -> BusyPeriod[])
      -> AvailabilityCalculator (BusyPeriod[] -> DayAvailability[])
      -> Renderer (DayAvailability[] -> HTML)
      -> AtomicWriter (HTML + robots.txt -> public/)
```

### Entry and orchestration

- `bin/generate`: parses `--config` and `--output`, invokes the application, prints sanitized failures, and exits non-zero on errors.
- `lib/availability.rb`: requires project components in dependency order.
- `lib/availability/application.rb`: owns one complete generation run, logs high-level progress, expands the event query range for buffers, and enforces all-or-nothing feed processing.

### Configuration and input

- `lib/availability/config.rb`: safely loads YAML; validates strict keys, timezone, URLs, bounded day/calendar counts, buffers, weekday definitions, time syntax, window ordering, and environment placeholders. Weekday definitions replace `default`; they do not merge with it.
- `lib/availability/config_value_parser.rb`: contains reusable scalar and strict-key configuration validation helpers.
- `lib/availability/calendar_url.rb`: converts `webcal:` to `https:` without exposing the original value.
- `lib/availability/calendar_fetcher.rb`: uses `Net::HTTP`, follows bounded redirects, applies connection/read timeouts, streams successful bodies under `MAX_BYTES`, and sanitizes failures.

### Calendar domain

- `lib/availability/tolerant_icalendar_parser.rb`: isolates malformed properties and lines to their containing event.
- `lib/availability/event_timezone_validator.rb`: rejects unresolved source `TZID` values while accepting mapped IANA/Windows zones and usable `VTIMEZONE` definitions.
- `lib/availability/recurrence_expander.rb`: chunks dense recurrence expansion and enforces per-event and per-calendar occurrence limits.
- `lib/availability/calendar_parser.rb`: silences dependency diagnostics and uses the parser helpers plus `icalendar-recurrence`/`ice_cube`; handles UTC, named-zone, floating, all-day, multi-day, recurring, exclusion, cancellation, and detached recurrence events. Malformed individual events are ignored and reported only as sanitized counts.
- `lib/availability/busy_period.rb`: defines immutable UTC-backed `BusyPeriod`, `Slot`, and `DayAvailability` value objects.
- `lib/availability/availability_calculator.rb`: applies buffers, builds per-day local boundaries, clips and merges busy periods, subtracts them from configured windows, and filters short slots.

### Output

- `lib/availability/renderer.rb`: exposes only display-safe availability values to ERB and formats local dates/times.
- `templates/index.html.erb`: self-contained responsive HTML/CSS; no JavaScript or external assets. It displays only free periods and includes `noindex, nofollow, noarchive`.
- `lib/availability/atomic_writer.rb`: prepares same-filesystem tempfiles, cleans partial failures, publishes `index.html` last, and sets static files to mode `0644`.
- `public/`: generated output. Do not hand-edit it; regenerate it.

### Deployment assets

- `deploy/availability.nginx.conf`: example exact-path Nginx exposure that maps only generated public files.
- `deploy/availability.logrotate`: generator log rotation example.
- The intended production flow is `/opt/availability/public -> Nginx -> HTTPS`, regenerated hourly by cron at a non-zero minute.

## Dependencies

- Ruby 3.4.8 and Bundler 2.6+
- `icalendar` for ICS parsing
- `icalendar-recurrence`/`ice_cube` for bounded recurrence expansion
- `activesupport` and `tzinfo` for named timezone/DST behavior
- standard-library `Net::HTTP`, YAML, ERB, and filesystem APIs
- RSpec, WebMock, RuboCop, rubocop-rspec, rubocop-rake, and rubocop-performance for development

Do not implement recurrence rules manually. If changing recurrence behavior, first verify the library semantics and add focused fixtures/specs, especially around DST and exceptions.

## Commands

From the repository root:

```bash
bundle install
bundle exec bin/generate
bundle exec bin/generate --config /path/to/config.yml --output /path/to/public
bundle exec rspec
bundle exec rubocop
bundle exec rake
```

`bundle exec rake` is the required final quality gate; it runs both RSpec and RuboCop. The project is pinned to Ruby 3.4.8 through `.ruby-version` and `Gemfile`.

## Testing conventions

- Production specs live under `spec/availability/` and mirror the class path.
- Use `RSpec.describe ClassName`, then method-level `describe '.class_method'` or `describe '#instance_method'`.
- Use `context` blocks beginning with `when`, `with`, or `without` to express changed inputs/state.
- Prefer `let`, named subjects, verified doubles/spies, WebMock, and behavior-level assertions.
- Use `:aggregate_failures` only when multiple assertions describe one coherent artifact or outcome.
- Do not expose real feed data in tests. `spec/fixtures/sample.ics` is intentionally synthetic and includes fake sensitive metadata so privacy tests can assert it is absent from output.
- Every bug fix should add a regression example that fails before the fix.
- Important coverage areas: interval subtraction/merging, multiple calendars, boundaries, midnight/all-day events, weekday replacements, unavailable days, split windows, minimum duration, buffers, recurrence/exclusions/overrides and limits, UTC/source/floating/custom/unresolved zones, tolerant event parsing, sanitized diagnostics, DST, atomic preparation/publish failure cleanup, streaming limits, disabled mode, and privacy scans.

## Style and change workflow

1. Read the relevant production class, its matching spec, and the applicable README section.
2. Preserve unrelated user changes and never inspect the real secret config casually.
3. Add or update a behavior-focused spec first for correctness-sensitive changes.
4. Keep responsibilities in the existing component boundaries; add a class only when it removes a real mixed responsibility.
5. Run focused specs while iterating.
6. Run `bundle exec rake` before handing off.
7. If generated behavior changed, regenerate with synthetic fixtures and scan `public/` for fixture secrets and ICS metadata.

RuboCop targets Ruby 3.4 with new cops enabled and the RSpec/Rake/performance plugins. Do not add blanket disables or generated TODO baselines. Prefer small refactors; document any narrow rule exception in `.rubocop.yml`.

## Known limits

- Rare recurrence features such as `RANGE=THISANDFUTURE` are not fully supported.
- Custom/non-IANA timezone definitions may be rejected if the parser cannot map them safely.
- HTTP validators (`ETag`, `Last-Modified`) are not persisted; every successful run fetches every feed.
- `robots.txt`, `noindex`, and a long random path are not authentication.

Consult `README.md` for user-facing configuration, deployment, cron, troubleshooting, and privacy documentation. Keep this file focused on implementation context and agent guardrails.
