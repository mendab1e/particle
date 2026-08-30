# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gem::Specification do
  subject(:specification) do
    described_class.load(File.expand_path('../../particle-calendar.gemspec', __dir__))
  end

  it 'uses the publishable package name and particle executable', :aggregate_failures do
    expect(specification.name).to eq('particle-calendar')
    expect(specification.executables).to eq(['particle'])
    expect(specification.version.to_s).to eq(Availability::VERSION)
  end

  it 'packages every runtime asset', :aggregate_failures do
    expect(specification.files).to include(
      'assets/favicon.svg',
      'config/availability.example.yml',
      'exe/particle',
      'templates/index.html.erb',
      'templates/nginx.conf.erb'
    )
  end

  it 'does not package production configuration or generated output', :aggregate_failures do
    expect(specification.files).not_to include('config/availability.yml')
    expect(specification.files.grep(%r{\Apublic/})).to be_empty
  end

  it 'declares the generator libraries as runtime dependencies' do
    expect(specification.runtime_dependencies.map(&:name)).to contain_exactly(
      'activesupport', 'icalendar', 'icalendar-recurrence', 'tzinfo'
    )
  end
end
