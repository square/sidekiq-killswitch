# frozen_string_literal: true

module Sidekiq
  module Killswitch
    module Middleware
      class Server
        def call(worker, job, _queue)
          if Killswitch.dead_queue_worker?(worker.class)
            DeadSet.new.kill(job)
            Killswitch.logger.info "#{worker.class.name} marked as dead queue worker. Job #{job} was killed."
          elsif Killswitch.blackhole_worker?(worker.class)
            Killswitch.logger.info "#{worker.class.name} is currently disabled. Job #{job} was not executed."
          else
            yield
          end
        end
      end
    end
  end
end
