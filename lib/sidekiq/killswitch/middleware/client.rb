# frozen_string_literal: true

module Sidekiq
  module Killswitch
    module Middleware
      class Client
        def call(worker_class, job, _queue, _redis_pool)
          worker_name = Sidekiq::Killswitch.class_to_str(worker_class)

          if Killswitch.blackhole_worker?(worker_name)
            Killswitch.logger.info "#{worker_name} is currently disabled. Job #{job} was not executed."
            false
          else
            yield
          end
        end
      end
    end
  end
end
