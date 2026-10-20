# frozen_string_literal: true

module Sidekiq
  module Killswitch
    module Web
      VIEW_PATH = File.expand_path('../../../web/views', __dir__)

      module Helpers
        def validate_worker_name(worker)
          return true unless Killswitch.config.web_ui_worker_validator

          is_worker_valid = Killswitch.config.web_ui_worker_validator.call(worker)
          session[:worker_name_invalid] = true unless is_worker_valid
          is_worker_valid
        end
      end

      def self.registered(app)
        Sidekiq::Web::Application.helpers Helpers

        app.get '/kill-switches' do
          @worker_name_invalid = session.delete(:worker_name_invalid)
          @blackhole_workers = Killswitch.blackhole_workers
          @dead_queue_workers = Killswitch.dead_queue_workers

          erb File.read(File.join(VIEW_PATH, 'kill_switches.html.erb'))
        end

        # We should not worry about String escaping and NoSQL injection
        # https://redis.io/topics/security#string-escaping-and-nosql-injection
        app.post '/kill-switches/blackhole_add' do
          Killswitch.blackhole_add_worker(params['worker_name']) if validate_worker_name(params['worker_name'])

          redirect "#{root_path}kill-switches"
        end

        app.post '/kill-switches/blackhole_remove' do
          Killswitch.blackhole_remove_worker(params['worker_name']) if validate_worker_name(params['worker_name'])

          redirect "#{root_path}kill-switches"
        end

        app.post '/kill-switches/dead_queue_add' do
          Killswitch.dead_queue_add_worker(params['worker_name']) if validate_worker_name(params['worker_name'])

          redirect "#{root_path}kill-switches"
        end

        app.post '/kill-switches/dead_queue_remove' do
          Killswitch.dead_queue_remove_worker(params['worker_name']) if validate_worker_name(params['worker_name'])

          redirect "#{root_path}kill-switches"
        end
      end
    end
  end
end

require 'sidekiq/web' unless defined?(Sidekiq::Web)
Sidekiq::Web.configure do |config|
  config.register_extension(Sidekiq::Killswitch::Web, name: "kill_switches", tab: ["Kill Switches"], index: ["kill-switches"])
end
Sidekiq::Web.locales << File.expand_path('../../../web/locales', __dir__)
