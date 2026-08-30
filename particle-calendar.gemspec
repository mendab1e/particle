# frozen_string_literal: true

require_relative 'lib/availability/version'

Gem::Specification.new do |spec|
  spec.name = 'particle-calendar'
  spec.version = Availability::VERSION
  spec.authors = ['Timur']
  spec.email = ['yanberdint@gmail.com']

  spec.summary = 'Publish private calendar availability as static HTML'
  spec.description = 'A command-line static-site generator that subtracts private iCalendar busy time ' \
                     'from configured availability.'
  spec.homepage = 'https://github.com/mendab1e/particle'
  spec.license = nil
  spec.required_ruby_version = '>= 3.4.0'

  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir[
    'README.md',
    'assets/favicon.svg',
    'config/availability.example.yml',
    'exe/particle',
    'lib/**/*.rb',
    'templates/*.erb'
  ]
  spec.bindir = 'exe'
  spec.executables = ['particle']
  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', '~> 6.1.7'
  spec.add_dependency 'icalendar', '~> 2.10'
  spec.add_dependency 'icalendar-recurrence', '~> 1.2'
  spec.add_dependency 'tzinfo', '~> 2.0'
end
