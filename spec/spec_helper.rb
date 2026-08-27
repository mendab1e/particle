# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'
require 'time'
require 'webmock/rspec'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'availability'

module SpecSupport
  def config_attributes(overrides = {})
    attributes = {
      'enabled' => true,
      'timezone' => 'Europe/Berlin',
      'calendar_urls' => ['https://calendar.example/private.ics'],
      'days_to_show' => 1,
      'minimum_slot_minutes' => 0,
      'event_buffer' => { 'before_minutes' => 0, 'after_minutes' => 0 },
      'availability' => { 'default' => [{ 'start' => '09:00', 'end' => '22:00' }] }
    }
    deep_merge(attributes, overrides)
  end

  def build_config(overrides = {})
    Availability::Config.new(config_attributes(overrides), env: {})
  end

  def deep_merge(left, right)
    left.merge(right) do |_key, old_value, new_value|
      old_value.is_a?(Hash) && new_value.is_a?(Hash) ? deep_merge(old_value, new_value) : new_value
    end
  end

  def local_time(date, hour, minute = 0, zone: 'Europe/Berlin')
    TZInfo::Timezone.get(zone).local_time(date.year, date.month, date.day, hour, minute, 0).utc
  end

  def period(date, start_hour, end_hour, start_minute: 0, end_minute: 0, end_date: date)
    Availability::BusyPeriod.new(
      local_time(date, start_hour, start_minute),
      local_time(end_date, end_hour, end_minute)
    )
  end

  def slot_times(day, zone: TZInfo::Timezone.get('Europe/Berlin'))
    day.slots.map do |slot|
      [zone.to_local(slot.starts_at).strftime('%H:%M'), zone.to_local(slot.ends_at).strftime('%H:%M')]
    end
  end
end

RSpec.configure do |config|
  config.include SpecSupport
  config.disable_monkey_patching!
  config.order = :random
end
