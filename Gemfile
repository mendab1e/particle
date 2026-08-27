# frozen_string_literal: true

source 'https://rubygems.org'

ruby '3.4.8'

gem 'icalendar', '~> 2.10'
gem 'icalendar-recurrence', '~> 1.2'
gem 'tzinfo', '~> 2.0'
# Preserves named time zones while expanding recurrences across DST changes.
gem 'activesupport', '~> 6.1.7'

group :development, :test do
  gem 'rake', '~> 13.0'
  gem 'rspec', '~> 3.12'
  gem 'rubocop', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rake', require: false
  gem 'rubocop-rspec', require: false
  gem 'webmock', '~> 3.19'
end
