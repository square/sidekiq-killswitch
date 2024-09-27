# frozen_string_literal: true

module Sidekiq
  module Killswitch
    module Middleware
      class Server
        include Sidekiq::ServerMiddleware

        def call(worker, job, _queue)
          serialized_job = Sidekiq.dump_json(job)

          if Killswitch.dead_queue_worker?(worker.class)
            DeadSet.new.kill(serialized_job)
            Killswitch.logger.warn "#{worker.class.name} marked as dead queue worker. Job #{serialized_job} was killed."
          elsif Killswitch.blackhole_worker?(worker.class)
            Killswitch.logger.warn "#{worker.class.name} is currently disabled. Job #{serialized_job} was not executed."
          else
            yield
          end
        end
      end
    end
  end
end
