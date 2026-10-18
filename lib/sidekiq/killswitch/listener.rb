# frozen_string_literal: true
require 'set'

module Sidekiq
  module Killswitch
    # Keeps the kill switches of a Sidekiq server process in memory, so a job check makes no Redis
    # call. A switch change publishes to CHANNEL, and the listener loads both lists again. It also
    # loads them on start, after a reconnect and every RELOAD_INTERVAL seconds, because pub/sub drops
    # messages while a process is disconnected.
    #
    # Opt in from the server configuration:
    #
    #   Sidekiq.configure_server do |config|
    #     Sidekiq::Killswitch::Listener.register(config)
    #   end
    class Listener
      CHANNEL = 'sidekiq.killswitch'
      RELOAD_INTERVAL = 30
      # A cache older than this is not used, so the checks read Redis when the listener stops.
      MAX_CACHE_AGE = RELOAD_INTERVAL * 3

      Switches = Struct.new(:dead_queue, :blackhole, :loaded_at) do
        def fresh?
          Listener.monotonic_now - loaded_at <= MAX_CACHE_AGE
        end

        def for(worker_name)
          [dead_queue.include?(worker_name), blackhole.include?(worker_name)]
        end
      end

      class << self
        attr_reader :switches

        def register(config)
          listener = new(config.new_redis_pool(1, 'killswitch'))
          config.on(:startup) { listener.start }
          config.on(:shutdown) { listener.stop }
          listener
        end

        # The fresh cached switches, or nil when the checks must read Redis.
        def fresh_switches
          cached = @switches
          cached if cached&.fresh?
        end

        def reload
          dead_queue, blackhole = Killswitch.redis_pool do |redis|
            redis.pipelined do |pipeline|
              pipeline.hkeys(DEAD_QUEUE_WORKERS_KEY_NAME)
              pipeline.hkeys(BLACKHOLE_WORKERS_KEY_NAME)
            end
          end

          @switches = Switches.new(dead_queue.to_set.freeze, blackhole.to_set.freeze, monotonic_now).freeze
        end

        def clear
          @switches = nil
        end

        def monotonic_now
          ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        end
      end

      def initialize(pool)
        @pool = pool
        @done = false
        @thread = nil
      end

      def start
        @done = false
        @thread ||= Thread.new { listen }
      end

      def stop
        @done = true
        @thread&.raise(Sidekiq::Shutdown)
        @thread&.join(1)
        @thread = nil
        self.class.clear
      end

      private

      def listen
        until @done
          begin
            @pool.with { |conn| subscribe(conn) }
          rescue Sidekiq::Shutdown
            break
          rescue StandardError => e
            Killswitch.logger.warn "Kill switch listener failed, retrying: #{e.class}: #{e.message}"
            sleep 1 unless @done
          end
        end
      end

      def subscribe(conn)
        pubsub = conn.pubsub
        pubsub.call('SUBSCRIBE', CHANNEL)
        self.class.reload

        until @done
          event = pubsub.next_event(RELOAD_INTERVAL)
          # nil means no message for RELOAD_INTERVAL seconds.
          self.class.reload if event.nil? || event[0] == 'message'
        end
      ensure
        pubsub&.close
      end
    end
  end
end
