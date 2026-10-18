# frozen_string_literal: true
require 'sidekiq/killswitch/config'
require 'sidekiq/killswitch/middleware/server'
require 'sidekiq/killswitch/middleware/client'
require 'sidekiq/killswitch/listener'

module Sidekiq
  module Killswitch
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
          redis.hset(BLACKHOLE_WORKERS_KEY_NAME, worker_name, Time.now.to_s)
          redis.publish(Listener::CHANNEL, 'changed')
        end
        logger.warn "#{worker_name} added to blackhole workers"
      end

      def blackhole_remove_worker(worker_name)
        worker_name = class_to_str(worker_name)

        redis_pool do |redis|
          redis.hdel(BLACKHOLE_WORKERS_KEY_NAME, worker_name)
          redis.publish(Listener::CHANNEL, 'changed')
        end
        logger.warn "#{worker_name} removed from blackhole workers"
      end

      def blackhole_worker?(worker_name)
        cached = Listener.fresh_switches
        return cached.blackhole.include?(class_to_str(worker_name)) if cached

        redis_pool do |redis|
          is_true_compat(redis.hexists(BLACKHOLE_WORKERS_KEY_NAME, class_to_str(worker_name)))
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
          redis.hset(DEAD_QUEUE_WORKERS_KEY_NAME, worker_name, Time.now.to_s)
          redis.publish(Listener::CHANNEL, 'changed')
        end
        logger.warn "#{worker_name} added to dead queue workers"
      end

      def dead_queue_remove_worker(worker_name)
        worker_name = class_to_str(worker_name)

        redis_pool do |redis|
          redis.hdel(DEAD_QUEUE_WORKERS_KEY_NAME, worker_name)
          redis.publish(Listener::CHANNEL, 'changed')
        end
        logger.warn "#{worker_name} removed from dead queue workers"
      end

      def dead_queue_worker?(worker_name)
        cached = Listener.fresh_switches
        return cached.dead_queue.include?(class_to_str(worker_name)) if cached

        redis_pool do |redis|
          is_true_compat(redis.hexists(DEAD_QUEUE_WORKERS_KEY_NAME, class_to_str(worker_name)))
        end
      end

      # Returns [dead_queue?, blackhole?] for the worker, from the listener's cache or with one Redis round trip.
      def kill_switches_for(worker_name)
        worker_name = class_to_str(worker_name)
        cached = Listener.fresh_switches
        return cached.for(worker_name) if cached

        dead_queue, blackhole = redis_pool do |redis|
          redis.pipelined do |pipeline|
            pipeline.hexists(DEAD_QUEUE_WORKERS_KEY_NAME, worker_name)
            pipeline.hexists(BLACKHOLE_WORKERS_KEY_NAME, worker_name)
          end
        end

        [is_true_compat(dead_queue), is_true_compat(blackhole)]
      end

      def dead_queue_workers
        redis_pool do |redis|
          redis.hgetall(DEAD_QUEUE_WORKERS_KEY_NAME)
        end
      end

      def class_to_str(class_or_string)
        (class_or_string.is_a?(String) ? class_or_string : class_or_string.name).strip
      end

      private

      def is_true_compat(redis_result_value)
        # Compatibility method for `redis` and `redis-client`.
        redis_result_value == 1 || redis_result_value == true
      end
    end
  end
end
