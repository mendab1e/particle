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

    context 'when publishing the index fails' do
      subject(:write_files) do
        described_class.write_all(
          directory,
          'robots.txt' => 'new robots',
          'index.html' => 'new index'
        )
      end

      before do
        File.write(File.join(directory, 'index.html'), 'known good')
        allow(File).to receive(:rename).and_wrap_original do |method, source, destination|
          raise Errno::EACCES, destination if File.basename(destination) == 'index.html'

          method.call(source, destination)
        end
      end

      it 'retains the known-good index and removes temporary files', :aggregate_failures do
        expect { write_files }.to raise_error(Errno::EACCES)
        expect(File.read(File.join(directory, 'index.html'))).to eq('known good')
        expect(Dir.children(directory).grep(/\.tmp\z/)).to be_empty
      end
    end

    context 'when publishing an earlier asset fails' do
      subject(:write_files) do
        described_class.write_all(
          directory,
          'robots.txt' => 'new robots',
          'index.html' => 'new index'
        )
      end

      before do
        File.write(File.join(directory, 'index.html'), 'known good')
        allow(File).to receive(:rename).and_wrap_original do |method, source, destination|
          raise Errno::EACCES, destination if File.basename(destination) == 'robots.txt'

          method.call(source, destination)
        end
      end

      it 'does not attempt to replace the index', :aggregate_failures do
        expect { write_files }.to raise_error(Errno::EACCES)
        expect(File.read(File.join(directory, 'index.html'))).to eq('known good')
        expect(Dir.children(directory).grep(/\.tmp\z/)).to be_empty
      end
    end
  end
end
