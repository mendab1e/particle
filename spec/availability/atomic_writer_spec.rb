# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Availability::AtomicWriter do
  describe '.write_all' do
    subject(:write_files) do
      described_class.write_all(
        directory,
        'robots.txt' => 'User-agent: *',
        'index.html' => invalid_contents
      )
    end

    let(:directory) { Dir.mktmpdir }
    let(:invalid_contents) do
      Object.new.tap do |contents|
        contents.define_singleton_method(:to_s) { raise 'write failed' }
        contents.define_singleton_method(:to_str) { raise 'write failed' }
      end
    end

    after { FileUtils.remove_entry(directory) }

    context 'when preparing a later file fails' do
      it 'cleans every temporary file', :aggregate_failures do
        expect { write_files }.to raise_error(RuntimeError, 'write failed')
        expect(Dir.children(directory)).to be_empty
      end
    end
  end
end
