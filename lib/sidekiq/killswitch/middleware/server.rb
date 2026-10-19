# frozen_string_literal: true

module Sidekiq
  module Killswitch
    module Middleware
      class Server
        include Sidekiq::ServerMiddleware

        def call(worker, job, _queue)
          dead_queue, blackhole = Killswitch.kill_switches_for(worker.class)

          if dead_queue
            serialized_job = Sidekiq.dump_json(job)
            DeadSet.new.kill(serialized_job)
            Killswitch.logger.warn "#{worker.class.name} marked as dead queue worker. Job #{serialized_job} was killed."
          elsif blackhole
            Killswitch.logger.warn "#{worker.class.name} is currently disabled. Job #{Sidekiq.dump_json(job)} was not executed."
          else
            yield
          end
        end
      end
    end
  end
end
