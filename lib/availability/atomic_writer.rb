# frozen_string_literal: true

require 'fileutils'
require 'tempfile'

module Availability
  # Writes generated assets through same-filesystem temporary files and renames.
  class AtomicWriter
    def self.write_all(output_dir, files)
      FileUtils.mkdir_p(output_dir)
      temporary = prepare_files(output_dir, files)
      publish_files(output_dir, files.keys, temporary)
    ensure
      cleanup(temporary)
    end

    def self.prepare_files(output_dir, files)
      temporary = {}
      files.each do |name, contents|
        temporary[name] = prepare_file(output_dir, name, contents)
      end
      temporary
    rescue StandardError
      cleanup(temporary)
      raise
    end

    def self.prepare_file(output_dir, name, contents)
      file = Tempfile.new([".#{name}", '.tmp'], output_dir)
      write_contents(file, contents)
      file
    rescue StandardError
      file&.close!
      raise
    end

    def self.write_contents(file, contents)
      file.binmode
      file.write(contents)
      file.flush
      file.fsync
      file.chmod(0o644)
      file.close
    end

    def self.publish_files(output_dir, names, temporary)
      # Publishing index last keeps the known-good page if preparation fails.
      (names - ['index.html'] + ['index.html']).each do |name|
        File.rename(temporary.fetch(name).path, File.join(output_dir, name))
      end
    end

    def self.cleanup(temporary)
      temporary&.each_value do |file|
        file.close unless file.closed?
        file.unlink if File.exist?(file.path)
      end
    end

    private_class_method :prepare_files, :prepare_file, :write_contents, :publish_files, :cleanup
  end
end
