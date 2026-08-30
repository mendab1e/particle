# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Availability::CalendarParser do
  describe '#parse' do
    subject(:periods) do
      parser.parse(
        ics,
        range_start: range_start,
        range_end: range_end,
        label: 'Calendar 1'
      )
    end

    let(:parser) { described_class.new(timezone: timezone) }
    let(:timezone) { TZInfo::Timezone.get('Europe/Berlin') }
    let(:range_start) { Time.utc(2026, 3, 20) }
    let(:range_end) { Time.utc(2026, 4, 10) }

    context 'with a recurring event that has an exclusion' do
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:recurring-secret-id
          DTSTART;TZID=Europe/Berlin:20260323T100000
          DTEND;TZID=Europe/Berlin:20260323T110000
          RRULE:FREQ=WEEKLY;COUNT=4
          EXDATE;TZID=Europe/Berlin:20260406T100000
          SUMMARY:Private appointment
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'expands valid occurrences while retaining wall time through DST', :aggregate_failures do
        local_starts = periods.map { |item| timezone.to_local(item.starts_at) }

        expect(local_starts.map { |time| [time.to_date, time.hour] }).to eq([
                                                                              [Date.new(2026, 3, 23), 10],
                                                                              [Date.new(2026, 3, 30), 10]
                                                                            ])
        expect(periods.map { |item| item.starts_at.hour }).to eq([9, 8])
      end
    end

    context 'with an all-day event' do
      let(:range_start) { Time.utc(2026, 8, 25) }
      let(:range_end) { Time.utc(2026, 8, 30) }
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:all-day
          DTSTART;VALUE=DATE:20260827
          DTEND;VALUE=DATE:20260828
          SUMMARY:Secret holiday
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'uses local midnight boundaries', :aggregate_failures do
        expect(timezone.to_local(periods.first.starts_at).to_date).to eq(Date.new(2026, 8, 27))
        expect(timezone.to_local(periods.first.ends_at).to_date).to eq(Date.new(2026, 8, 28))
      end
    end

    context 'with UTC and foreign-zone events' do
      let(:range_start) { Time.utc(2026, 8, 25) }
      let(:range_end) { Time.utc(2026, 8, 30) }
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:utc-event
          DTSTART:20260827T120000Z
          DTEND:20260827T130000Z
          END:VEVENT
          BEGIN:VEVENT
          UID:new-york-event
          DTSTART;TZID=America/New_York:20260827T120000
          DTEND;TZID=America/New_York:20260827T130000
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'normalizes both into the configured timezone' do
        local_times = periods.map { |item| timezone.to_local(item.starts_at).strftime('%H:%M') }

        expect(local_times).to eq(['14:00', '18:00'])
      end
    end

    context 'with a floating timed event' do
      let(:range_start) { Time.utc(2026, 8, 25) }
      let(:range_end) { Time.utc(2026, 8, 30) }
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:floating-event
          DTSTART:20260827T120000
          DTEND:20260827T130000
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'interprets wall time in the configured timezone' do
        local_start = timezone.to_local(periods.first.starts_at).strftime('%H:%M')

        expect(local_start).to eq('12:00')
      end
    end

    context 'with a timed event that omits its end and duration' do
      let(:range_start) { Time.utc(2026, 8, 25) }
      let(:range_end) { Time.utc(2026, 8, 30) }
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:instant-event
          DTSTART:20260827T120000Z
          END:VEVENT
          BEGIN:VEVENT
          UID:ordinary-event
          DTSTART:20260827T130000Z
          DTEND:20260827T140000Z
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'ignores the zero-duration event' do
        expected_period = [Time.utc(2026, 8, 27, 13), Time.utc(2026, 8, 27, 14)]

        expect(periods.map { |item| [item.starts_at, item.ends_at] }).to eq([expected_period])
      end
    end

    context 'with a moved detached recurrence' do
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:series-1
          DTSTART;TZID=Europe/Berlin:20260323T100000
          DTEND;TZID=Europe/Berlin:20260323T110000
          RRULE:FREQ=WEEKLY;COUNT=2
          END:VEVENT
          BEGIN:VEVENT
          UID:series-1
          RECURRENCE-ID;TZID=Europe/Berlin:20260330T100000
          DTSTART;TZID=Europe/Berlin:20260330T150000
          DTEND;TZID=Europe/Berlin:20260330T160000
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'suppresses the original instance' do
        expect(periods.map { |item| timezone.to_local(item.starts_at).hour }).to eq([10, 15])
      end
    end

    context 'with invalid ICS content' do
      let(:ics) { 'definitely not a calendar' }

      it 'raises a labeled parse error' do
        expect { periods }.to raise_error(Availability::ParseError, /Calendar 1/)
      end
    end

    context 'with a non-cancelled event that has no start time' do
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:missing-start
          SUMMARY:Incomplete event
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'ignores the event' do
        expect(periods).to be_empty
      end
    end

    context 'with an event that has a non-positive duration' do
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:invalid-duration
          DTSTART:20260323T100000Z
          DTEND:20260323T090000Z
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'ignores the event' do
        expect(periods).to be_empty
      end
    end

    context 'with an event whose explicit end equals its start' do
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:invalid-zero-duration
          DTSTART:20260323T100000Z
          DTEND:20260323T100000Z
          END:VEVENT
          BEGIN:VEVENT
          UID:valid-after-invalid
          DTSTART:20260323T110000Z
          DTEND:20260323T120000Z
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'ignores the malformed event and retains valid events' do
        expected_period = [Time.utc(2026, 3, 23, 11), Time.utc(2026, 3, 23, 12)]

        expect(periods.map { |item| [item.starts_at, item.ends_at] }).to eq([expected_period])
      end
    end

    context 'with a property value that makes the dependency logger fail noisily' do
      let(:dependency_log) { StringIO.new }
      let(:range_start) { Time.utc(2026, 8, 25) }
      let(:range_end) { Time.utc(2026, 8, 30) }
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:private-malformed-id
          DTSTART;VALUE=PRIVATE/SECRET:20260827T120000Z
          DTEND:20260827T130000Z
          SUMMARY:Private malformed event
          END:VEVENT
          BEGIN:VEVENT
          UID:valid-event
          DTSTART:20260828T120000Z
          DTEND:20260828T130000Z
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      around do |example|
        previous_logger = Icalendar.logger
        Icalendar.logger = Icalendar::Logger.new(dependency_log, Logger::DEBUG)
        example.run
      ensure
        Icalendar.logger = previous_logger
      end

      it 'suppresses dependency output and ignores only the malformed event', :aggregate_failures do
        expect(periods.length).to eq(1)
        expect(parser.ignored_event_count).to eq(1)
        expect(dependency_log.string).to be_empty
      end
    end

    context 'with an invalid date inside one event' do
      let(:range_start) { Time.utc(2026, 8, 25) }
      let(:range_end) { Time.utc(2026, 8, 30) }
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:invalid-date
          DTSTART:20261340T120000Z
          DTEND:20261340T130000Z
          END:VEVENT
          BEGIN:VEVENT
          UID:valid-after-invalid-date
          DTSTART:20260828T120000Z
          DTEND:20260828T130000Z
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'retains valid events and reports a sanitized ignored count', :aggregate_failures do
        expect(periods.map(&:starts_at)).to eq([Time.utc(2026, 8, 28, 12)])
        expect(parser.ignored_event_count).to eq(1)
      end
    end

    context 'with a structurally malformed line inside one event' do
      let(:range_start) { Time.utc(2026, 8, 25) }
      let(:range_end) { Time.utc(2026, 8, 30) }
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:invalid-structure
          @@@:
          DTSTART:20260827T120000Z
          DTEND:20260827T130000Z
          END:VEVENT
          BEGIN:VEVENT
          UID:valid-after-invalid-structure
          DTSTART:20260828T120000Z
          DTEND:20260828T130000Z
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'discards the malformed event and resumes at the next event', :aggregate_failures do
        expect(periods.map(&:starts_at)).to eq([Time.utc(2026, 8, 28, 12)])
        expect(parser.ignored_event_count).to eq(1)
      end
    end

    context 'with an unresolved timezone identifier' do
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:unknown-zone
          DTSTART;TZID=Private/Unknown:20260827T120000
          DTEND;TZID=Private/Unknown:20260827T130000
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'ignores the event instead of silently treating it as UTC', :aggregate_failures do
        expect(periods).to be_empty
        expect(parser.ignored_event_count).to eq(1)
      end
    end

    context 'with a cancelled override that has an unresolved timezone' do
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:series-with-invalid-cancellation
          DTSTART;TZID=Europe/Berlin:20260323T100000
          DTEND;TZID=Europe/Berlin:20260323T110000
          RRULE:FREQ=WEEKLY;COUNT=1
          END:VEVENT
          BEGIN:VEVENT
          UID:series-with-invalid-cancellation
          RECURRENCE-ID;TZID=Private/Unknown:20260323T090000
          STATUS:CANCELLED
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'keeps the safely interpreted master occurrence busy', :aggregate_failures do
        expect(periods.map(&:starts_at)).to eq([Time.utc(2026, 3, 23, 9)])
        expect(parser.ignored_event_count).to eq(1)
      end
    end

    context 'with a custom timezone defined by the calendar' do
      let(:range_start) { Time.utc(2026, 8, 25) }
      let(:range_end) { Time.utc(2026, 8, 30) }
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VTIMEZONE
          TZID:Custom/Fixed
          BEGIN:STANDARD
          DTSTART:19700101T000000
          TZOFFSETFROM:+0230
          TZOFFSETTO:+0230
          TZNAME:CUSTOM
          END:STANDARD
          END:VTIMEZONE
          BEGIN:VEVENT
          UID:custom-zone
          DTSTART;TZID=Custom/Fixed:20260827T120000
          DTEND;TZID=Custom/Fixed:20260827T130000
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it 'uses the supplied VTIMEZONE definition' do
        expect(periods.map(&:starts_at)).to eq([Time.utc(2026, 8, 27, 9, 30)])
      end
    end

    context 'when a recurrence exceeds the safe occurrence limit' do
      let(:range_start) { Time.utc(2026, 8, 27) }
      let(:range_end) { Time.utc(2026, 8, 28) }
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:private-dense-recurrence
          DTSTART:20260827T000000Z
          DTEND:20260827T000001Z
          RRULE:FREQ=SECONDLY
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      before { stub_const('Availability::RecurrenceExpander::MAX_OCCURRENCES_PER_EVENT', 2) }

      it 'fails the feed with a sanitized error' do
        expect { periods }
          .to raise_error(Availability::ParseError, 'Calendar 1 exceeded the safe recurrence expansion limit')
      end
    end

    context 'when the feed exceeds the safe event limit' do
      let(:range_start) { Time.utc(2026, 8, 27) }
      let(:range_end) { Time.utc(2026, 8, 28) }
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:first-event
          DTSTART:20260827T100000Z
          DTEND:20260827T110000Z
          END:VEVENT
          BEGIN:VEVENT
          UID:second-event
          DTSTART:20260827T120000Z
          DTEND:20260827T130000Z
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      before { stub_const('Availability::CalendarParser::MAX_EVENTS_PER_CALENDAR', 1) }

      it 'fails the feed with a sanitized error' do
        expect { periods }.to raise_error(Availability::ParseError, 'Calendar 1 exceeded the safe event limit')
      end
    end

    context 'when all events together exceed the calendar occurrence limit' do
      let(:range_start) { Time.utc(2026, 8, 27) }
      let(:range_end) { Time.utc(2026, 8, 28) }
      let(:ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//EN
          BEGIN:VEVENT
          UID:first-occurrence
          DTSTART:20260827T100000Z
          DTEND:20260827T110000Z
          END:VEVENT
          BEGIN:VEVENT
          UID:second-occurrence
          DTSTART:20260827T120000Z
          DTEND:20260827T130000Z
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      before { stub_const('Availability::RecurrenceExpander::MAX_OCCURRENCES_PER_CALENDAR', 1) }

      it 'fails the feed with the same sanitized recurrence error' do
        expect { periods }
          .to raise_error(Availability::ParseError, 'Calendar 1 exceeded the safe recurrence expansion limit')
      end
    end
  end
end
