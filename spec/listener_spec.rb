# frozen_string_literal: true
require 'spec_helper'

RSpec.describe Sidekiq::Killswitch::Listener do
  let(:worker_name) { 'SomeWorker' }
  let(:listener) { described_class.new(Sidekiq.default_configuration) }

  def wait_for(timeout: 3)
    deadline = Time.now + timeout
    sleep 0.02 until yield || Time.now > deadline
    yield
  end

  describe '#reload' do
    it 'should cache both lists of workers' do
      Sidekiq::Killswitch.dead_queue_add_worker('DeadWorker')
      Sidekiq::Killswitch.blackhole_add_worker('DisabledWorker')

      listener.send(:reload)

      expect(Sidekiq::Killswitch.kill_switches_for('DeadWorker')).to eq([true, false])
      expect(Sidekiq::Killswitch.kill_switches_for('DisabledWorker')).to eq([false, true])
    end

    it 'should not write the cache after the listener stops' do
      listener.stop
      listener.send(:reload)

      expect(described_class.switches).to be_nil
    end
  end

  context 'with fresh cached switches' do
    before do
      Sidekiq::Killswitch.dead_queue_add_worker(worker_name)
      listener.send(:reload)
    end

    it 'should answer every check without Redis' do
      expect(Sidekiq).not_to receive(:redis)

      expect(Sidekiq::Killswitch.kill_switches_for(worker_name)).to eq([true, false])
      expect(Sidekiq::Killswitch.dead_queue_worker?(worker_name)).to be(true)
      expect(Sidekiq::Killswitch.blackhole_worker?(worker_name)).to be(false)
    end

    it 'should read Redis when the cache is older than MAX_CACHE_AGE' do
      loaded_at = described_class.switches.loaded_at
      allow(described_class).to receive(:monotonic_now).and_return(loaded_at + described_class::MAX_CACHE_AGE + 1)
      Sidekiq.redis { |c| c.hdel(Sidekiq::Killswitch::DEAD_QUEUE_WORKERS_KEY_NAME, worker_name) }

      expect(Sidekiq::Killswitch.dead_queue_worker?(worker_name)).to be(false)
    end
  end

  describe 'a running listener' do
    after { listener.stop }

    it 'should load the switches on start and apply a published change' do
      Sidekiq::Killswitch.dead_queue_add_worker('DeadWorker')
      listener.start

      expect(wait_for { described_class.fresh_switches }).to be_truthy
      expect(Sidekiq::Killswitch.dead_queue_worker?('DeadWorker')).to be(true)

      Sidekiq::Killswitch.blackhole_add_worker(worker_name)
      expect(wait_for { described_class.fresh_switches&.blackhole&.include?(worker_name) }).to be(true)

      Sidekiq::Killswitch.dead_queue_remove_worker('DeadWorker')
      expect(wait_for { !described_class.fresh_switches.dead_queue.include?('DeadWorker') }).to be(true)
    end

    it 'should ignore a message for another Redis database' do
      listener.start
      loaded_at = wait_for { described_class.fresh_switches }.loaded_at

      Sidekiq.redis { |c| c.publish(described_class::CHANNEL, '99') }
      sleep 0.3

      expect(described_class.switches.loaded_at).to eq(loaded_at)
    end

    it 'should clear the cache when it stops' do
      listener.start
      wait_for { described_class.fresh_switches }

      listener.stop

      expect(described_class.fresh_switches).to be_nil
    end
  end

  describe 'connection checks' do
    it 'should connect again when a PING gets no reply' do
      pubsub = double('pubsub', call: nil, next_event: nil)

      expect { listener.send(:ping, pubsub) }.to raise_error(described_class::ConnectionLost)
    end

    it 'should wait for the PING reply past other messages' do
      pubsub = double('pubsub', call: nil)
      allow(pubsub).to receive(:next_event).and_return(['message', described_class::CHANNEL, '15'], ['pong', ''])

      expect { listener.send(:ping, pubsub) }.not_to raise_error
    end

    it 'should connect again when the subscription is not confirmed' do
      pubsub = double('pubsub', call: nil, next_event: nil)

      expect { listener.send(:subscribe, pubsub) }.to raise_error(described_class::ConnectionLost)
    end
  end

  describe '.register' do
    # A fresh copy, so the hooks do not go into the lifecycle arrays that Sidekiq's DEFAULTS share.
    let(:config) do
      Sidekiq::Config.new.tap do |c|
        c[:lifecycle_events] = c[:lifecycle_events].transform_values { [] }
      end
    end

    it 'should build the listener at startup and stop it at shutdown' do
      allow(config).to receive(:new_redis_pool).and_call_original
      described_class.register(config)
      expect(config).not_to have_received(:new_redis_pool).with(1, 'killswitch')

      config[:lifecycle_events][:startup].each(&:call)
      expect(config).to have_received(:new_redis_pool).with(1, 'killswitch').once
      expect(wait_for { described_class.fresh_switches }).to be_truthy

      config[:lifecycle_events][:shutdown].each(&:call)
      expect(described_class.fresh_switches).to be_nil
    end
  end
end
