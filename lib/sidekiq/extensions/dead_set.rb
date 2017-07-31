# frozen_string_literal: true
require 'sidekiq/api'

# this is a monkey-patch!
# TODO: delete this patch after we explicitly depend on Sidekiq version that
# includes this PR: https://github.com/mperham/sidekiq/pull/3573

module Sidekiq
  module DeadSetKill
    def kill(message)
      now = Time.now.to_f
      Sidekiq.redis do |conn|
        conn.multi do
          conn.zadd(name, now.to_f.to_s, message)
          conn.zremrangebyscore(name, '-inf', now - self.class.timeout)
          conn.zremrangebyrank(name, 0, - self.class.max_jobs)
        end
      end
    end
  end
end

Sidekiq::DeadSet.include(Sidekiq::DeadSetKill) unless Sidekiq::DeadSet.method_defined?(:kill)
