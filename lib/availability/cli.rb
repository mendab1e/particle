# frozen_string_literal: true

require 'optparse'
require 'securerandom'

module Availability
  # Command-line interface exposed by the installed particle executable.
  class CLI
    SUCCESS = 0
    ERROR = 1
    USAGE_ERROR = 2

    def initialize(args:, output: $stdout, error: $stderr, env: ENV, working_directory: Dir.pwd,
                   random_path: -> { SecureRandom.hex(12) })
      @args = args.dup
      @output = output
      @error = error
      @env = env
      @working_directory = working_directory
      @random_path = random_path
    end

    def run
      dispatch(@args.shift)
    rescue OptionParser::ParseError => e
      @error.puts(e.message)
      USAGE_ERROR
    rescue Availability::Error => e
      @error.puts(e.message)
      ERROR
    rescue StandardError => e
      @error.puts("Particle failed unexpectedly (#{e.class}).")
      ERROR
    end

    private

    def dispatch(command)
      return show_help if command.nil? || %w[help --help -h].include?(command)

      case command
      when 'generate' then generate
      when 'setup' then setup
      when 'version', '--version', '-v' then show_version
      else
        @error.puts("Unknown command: #{command}")
        @error.puts(help)
        USAGE_ERROR
      end
    end

    def generate
      options = generation_defaults
      parser = generation_parser(options)
      parser.parse!(@args)
      return show_parser(parser) if options.delete(:help)

      reject_arguments!(parser)
      run_application(options)
      SUCCESS
    rescue Availability::Error => e
      raise e.class, "Generation failed: #{e.message}"
    end

    def run_application(options)
      Application.new(
        config_path: options.fetch(:config),
        output_dir: options.fetch(:output),
        template_path: Assets.index_template_path,
        favicon_path: Assets.favicon_path,
        output: @output
      ).run
    end

    def generation_defaults
      {
        config: @env.fetch('PARTICLE_CONFIG') do
          @env.fetch('AVAILABILITY_CONFIG', File.join(@working_directory, 'particle.yml'))
        end,
        output: @env.fetch('PARTICLE_OUTPUT', File.join(@working_directory, 'public'))
      }
    end

    def generation_parser(options)
      OptionParser.new do |parser|
        parser.banner = 'Usage: particle generate [options]'
        parser.on('-c', '--config PATH', 'Configuration file (or PARTICLE_CONFIG)') do |path|
          options[:config] = path
        end
        parser.on('-o', '--output DIR', 'Static output directory (or PARTICLE_OUTPUT)') do |path|
          options[:output] = path
        end
        parser.on('-h', '--help', 'Show this help') { options[:help] = true }
      end
    end

    def setup
      options = setup_defaults
      parser = setup_parser(options)
      parser.parse!(@args)
      return show_parser(parser) if options.delete(:help)

      reject_arguments!(parser)

      setup = Setup.new(**options)
      setup.run
      print_setup_result(setup)
      SUCCESS
    end

    def setup_defaults
      {
        config_path: File.join(@working_directory, 'particle.yml'),
        nginx_path: File.join(@working_directory, 'particle.nginx.conf'),
        output_dir: File.join(@working_directory, 'public'),
        server_name: 'example.com',
        url_path: "/#{@random_path.call}/"
      }
    end

    def setup_parser(options)
      OptionParser.new do |parser|
        parser.banner = 'Usage: particle setup [options]'
        add_setup_path_options(parser, options)
        add_setup_nginx_options(parser, options)
        parser.on('-h', '--help', 'Show this help') { options[:help] = true }
      end
    end

    def add_setup_path_options(parser, options)
      parser.on('-c', '--config PATH', 'Sample configuration destination') { |path| options[:config_path] = path }
      parser.on('-n', '--nginx PATH', 'Sample Nginx configuration destination') { |path| options[:nginx_path] = path }
      parser.on('-o', '--output DIR', 'Generated static output directory') { |path| options[:output_dir] = path }
    end

    def add_setup_nginx_options(parser, options)
      parser.on('--server-name NAME', 'Nginx server_name value') { |name| options[:server_name] = name }
      parser.on('--url-path PATH', 'Private URL path, including leading/trailing slashes') do |path|
        options[:url_path] = path
      end
    end

    def reject_arguments!(parser)
      return if @args.empty?

      raise OptionParser::InvalidArgument, "Unexpected arguments: #{@args.join(' ')}\n#{parser}"
    end

    def print_setup_result(setup)
      @output.puts("Created #{setup.config_path} (mode 0600)")
      @output.puts("Created #{setup.nginx_path}")
      @output.puts("Created output directory #{setup.output_dir}")
      @output.puts('Next: edit the config, run particle generate, then review and install the Nginx file.')
    end

    def show_help
      @output.puts(help)
      SUCCESS
    end

    def show_parser(parser)
      @output.puts(parser)
      SUCCESS
    end

    def show_version
      @output.puts("Particle #{VERSION}")
      SUCCESS
    end

    def help
      <<~HELP
        Usage: particle COMMAND [options]

        Commands:
          setup       Create sample config and Nginx files
          generate    Fetch calendars and generate static HTML
          version     Print the installed version

        Run `particle COMMAND --help` for command-specific options.
      HELP
    end
  end
end
