# frozen_string_literal: true
require 'sidekiq/extensions/dead_set'
require 'sidekiq/killswitch/config'
require 'sidekiq/killswitch/middleware/server'
require 'sidekiq/killswitch/middleware/client'

module Sidekiq::Killswitch
  BLACKHOLE_WORKERS_KEY_NAME = 'sidekiq.disabled-workers'
  DEAD_QUEUE_WORKERS_KEY_NAME = 'sidekiq.dead-queue-workers'

  class << self
    def config
      @config ||= Config.new
    end

    def configure(&block)
      yield config
    end

    def logger
      config.logger
    end

    def redis_pool(&block)
      Sidekiq.redis(&block)
    end

    def blackhole_add_worker(worker_name)
      worker_name = class_to_str(worker_name)

      redis_pool do |redis|
        redis.hset(BLACKHOLE_WORKERS_KEY_NAME, worker_name, Time.now)
      end
      logger.warn "#{worker_name} added to blackhole workers"
    end

    def blackhole_remove_worker(worker_name)
      worker_name = class_to_str(worker_name)

      redis_pool do |redis|
        redis.hdel(BLACKHOLE_WORKERS_KEY_NAME, worker_name)
      end
      logger.warn "#{worker_name} removed from blackhole workers"
    end

    def blackhole_worker?(worker_name)
      redis_pool do |redis|
        redis.hexists(BLACKHOLE_WORKERS_KEY_NAME, class_to_str(worker_name))
      end
    end

    def blackhole_workers
      redis_pool do |redis|
        redis.hgetall(BLACKHOLE_WORKERS_KEY_NAME)
      end
    end

    def dead_queue_add_worker(worker_name)
      worker_name = class_to_str(worker_name)

      redis_pool do |redis|
        redis.hset(DEAD_QUEUE_WORKERS_KEY_NAME, worker_name, Time.now)
      end
      logger.warn "#{worker_name} added to dead queue workers"
    end

    def dead_queue_remove_worker(worker_name)
      worker_name = class_to_str(worker_name)

      redis_pool do |redis|
        redis.hdel(DEAD_QUEUE_WORKERS_KEY_NAME, worker_name)
      end
      logger.warn "#{worker_name} removed from dead queue workers"
    end

    def dead_queue_worker?(worker_name)
      redis_pool do |redis|
        redis.hexists(DEAD_QUEUE_WORKERS_KEY_NAME, class_to_str(worker_name))
      end
    end

    def dead_queue_workers
      redis_pool do |redis|
        redis.hgetall(DEAD_QUEUE_WORKERS_KEY_NAME)
      end
    end

    def class_to_str(class_or_string)
      class_or_string.is_a?(String) ? class_or_string : class_or_string.name
    end
  end
end
