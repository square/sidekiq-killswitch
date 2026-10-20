# frozen_string_literal: true

module Sidekiq
  module Killswitch
    # Keeps the kill switches of a Sidekiq server process in memory, so a job check makes no Redis
    # call. It follows Sidekiq Pro's queue pause: the switches stay in Redis, and a change publishes
    # to CHANNEL with the Redis database number. The listener loads both lists on start, on each
    # message for its database, after a reconnect and every RELOAD_INTERVAL seconds, because
    # pub/sub drops messages while a process is disconnected.
    #
    # Opt in from the server configuration (Sidekiq 7 or later):
    #
    #   Sidekiq.configure_server do |config|
    #     Sidekiq::Killswitch::Listener.register(config)
    #   end
    class Listener
      include Sidekiq::Component

      CHANNEL = 'sidekiq.killswitch'
      RELOAD_INTERVAL = 30
      # A cache older than this is not used, so the checks read Redis when the listener stops.
      MAX_CACHE_AGE = RELOAD_INTERVAL * 3
      PING_TIMEOUT = 5

      ConnectionLost = Class.new(StandardError)

      Switches = Struct.new(:dead_queue, :blackhole, :loaded_at) do
        def fresh?
          Listener.monotonic_now - loaded_at <= MAX_CACHE_AGE
        end

        def for(worker_name)
          [dead_queue.include?(worker_name), blackhole.include?(worker_name)]
        end
      end

      class << self
        # The listener is built at startup, after the app has set config.redis.
        def register(config)
          listener = nil
          config.on(:startup) { listener = new(config).tap(&:start) }
          config.on(:shutdown) { listener&.stop }
        end

        # The fresh cached switches, or nil when the checks must read Redis.
        def fresh_switches
          cached = @switches
          cached if cached&.fresh?
        end

        # Adds the change message to the caller's pipeline, so the write and the message are one round trip.
        def publish(pipeline, db)
          pipeline.publish(CHANNEL, db.to_s)
        end
      end

      def initialize(config)
        @config = config
        @pool = config.new_redis_pool(1, 'killswitch')
        @db = redis { |conn| conn.config.db }
        @done = false
        @thread = nil
      end

      def start
        @thread ||= safe_thread('killswitch', &method(:listen))
      end

      # The listener stops after its current step and writes no cache after this, even if the
      # thread is still in a Redis call.
      def stop
        @done = true
        @thread&.raise(Sidekiq::Shutdown)
        @thread&.join(5)
        self.class.clear
      end

      private

      def listen
        until @done
          subscribed = false
          begin
            @pool.with do |conn|
              pubsub = conn.pubsub
              begin
                subscribe(pubsub)
                subscribed = true
                reload
                event_loop(pubsub)
              ensure
                pubsub.close
              end
            end
          rescue Sidekiq::Shutdown
            break
          rescue StandardError => e
            # As in Sidekiq Pro, a reset of the connection after it subscribed is not reported (#4969).
            handle_exception(e, context: 'Kill switch listener') unless subscribed
            sleep 1 unless @done
          end
        end
      end

      # Waits for the subscribe confirmation, so a change cannot come between the load and the subscription.
      def subscribe(pubsub)
        pubsub.call('SUBSCRIBE', CHANNEL)

        loop do
          event = pubsub.next_event(RELOAD_INTERVAL)
          raise ConnectionLost, 'no subscribe confirmation' if event.nil?
          return if event[0] == 'subscribe'
        end
      end

      def event_loop(pubsub)
        until @done
          event = pubsub.next_event(RELOAD_INTERVAL)

          if event.nil?
            ping(pubsub)
            reload
          elsif event[0] == 'message' && event[2] == @db.to_s
            reload
          end
        end
      end

      # A connection that the network dropped without an error gives only timeouts, so a PING with
      # no reply makes the listener connect again. Messages that come first are covered by the
      # reload after the PING.
      def ping(pubsub)
        pubsub.call('PING')

        loop do
          event = pubsub.next_event(PING_TIMEOUT)
          raise ConnectionLost, 'no reply to PING' if event.nil?
          return if event[0] == 'pong'
        end
      end

      def reload
        dead_queue, blackhole = redis do |conn|
          conn.pipelined do |pipeline|
            pipeline.hkeys(DEAD_QUEUE_WORKERS_KEY_NAME)
            pipeline.hkeys(BLACKHOLE_WORKERS_KEY_NAME)
          end
        end
        return if @done

        self.class.store(Switches.new(dead_queue.to_set.freeze, blackhole.to_set.freeze, self.class.monotonic_now).freeze)
      end

      class << self
        attr_reader :switches

        def store(switches)
          @switches = switches
        end

        def clear
          @switches = nil
        end

        def monotonic_now
          ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
