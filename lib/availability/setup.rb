# frozen_string_literal: true

require 'erb'
require 'fileutils'

module Availability
  # Creates deployment starter files without replacing existing configuration.
  class Setup
    SERVER_NAME_PATTERN = /\A[a-zA-Z0-9.-]+\z/
    URL_PATH_PATTERN = %r{\A/[a-zA-Z0-9_-]+/\z}

    def initialize(config_path:, nginx_path:, output_dir:, log_dir:, server_name:, url_path:)
      @config_path = File.expand_path(config_path)
      @nginx_path = File.expand_path(nginx_path)
      @output_dir = File.expand_path(output_dir)
      @log_dir = File.expand_path(log_dir)
      @server_name = server_name
      @url_path = url_path
    end

    attr_reader :config_path, :nginx_path, :output_dir, :log_dir

    def run
      validate!
      ensure_targets_are_available!
      create_files
      FileUtils.mkdir_p(output_dir)
      FileUtils.mkdir_p(log_dir)
      true
    rescue SystemCallError => e
      cleanup_created_files
      raise SetupError, "Setup failed: #{e.message}"
    end

    private

    def validate!
      raise SetupError, 'Config and Nginx paths must be different' if config_path == nginx_path
      raise SetupError, 'Output directory path must not contain newlines' if output_dir.match?(/[\r\n]/)
      raise SetupError, 'Server name must contain only letters, numbers, dots, and hyphens' unless valid_server_name?
      raise SetupError, 'URL path must look like /private-path/' unless @url_path.match?(URL_PATH_PATTERN)
    end

    def valid_server_name?
      !@server_name.empty? && @server_name.match?(SERVER_NAME_PATTERN)
    end

    def ensure_targets_are_available!
      existing = [config_path, nginx_path].select { |path| File.exist?(path) || File.symlink?(path) }
      return if existing.empty?

      raise SetupError, "Refusing to overwrite existing file: #{existing.first}"
    end

    def create_files
      @created_files = []
      write_exclusive(config_path, File.binread(Assets.example_config_path), 0o600)
      write_exclusive(nginx_path, rendered_nginx, 0o644)
    end

    def write_exclusive(path, contents, mode)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, mode) { |file| file.write(contents) }
      @created_files << path
      File.chmod(mode, path)
    end

    def rendered_nginx
      template = ERB.new(File.read(Assets.nginx_template_path), trim_mode: '-')
      template.result(binding)
    end

    def escaped_output_dir
      output_dir.gsub('\\', '\\\\').gsub('"', '\\"')
    end

    def cleanup_created_files
      @created_files&.each { |path| File.unlink(path) if File.file?(path) }
    end
  end
end
