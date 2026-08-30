# frozen_string_literal: true

module Availability
  # Resolves runtime files both from a source checkout and an installed gem.
  module Assets
    ROOT = File.expand_path('../..', __dir__)

    module_function

    def example_config_path
      File.join(ROOT, 'config', 'availability.example.yml')
    end

    def favicon_path
      File.join(ROOT, 'assets', 'favicon.svg')
    end

    def index_template_path
      File.join(ROOT, 'templates', 'index.html.erb')
    end

    def nginx_template_path
      File.join(ROOT, 'templates', 'nginx.conf.erb')
    end
  end
end
