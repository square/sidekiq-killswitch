# frozen_string_literal: true
require 'spec_helper'

RSpec.describe Sidekiq::Killswitch::Listener do
  let(:worker_name) { 'SomeWorker' }

  def wait_for(timeout: 3)
    deadline = Time.now + timeout
    sleep 0.02 until yield || Time.now > deadline
    yield
  end

  describe '.reload' do
    it 'should cache both lists of workers' do
      Sidekiq::Killswitch.dead_queue_add_worker('DeadWorker')
      Sidekiq::Killswitch.blackhole_add_worker('DisabledWorker')

      described_class.reload

      expect(Sidekiq::Killswitch.kill_switches_for('DeadWorker')).to eq([true, false])
      expect(Sidekiq::Killswitch.kill_switches_for('DisabledWorker')).to eq([false, true])
    end
  end

  context 'with fresh cached switches' do
    before do
      Sidekiq::Killswitch.dead_queue_add_worker(worker_name)
      described_class.reload
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
    let(:listener) { described_class.new(Sidekiq.default_configuration.new_redis_pool(1, 'killswitch')) }

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

    it 'should clear the cache when it stops' do
      listener.start
      wait_for { described_class.fresh_switches }

      listener.stop

      expect(described_class.fresh_switches).to be_nil
    end
  end

  describe '.register' do
    it 'should start on startup and stop on shutdown' do
      config = Sidekiq::Config.new
      allow(config).to receive(:new_redis_pool).and_return(Sidekiq.default_configuration.new_redis_pool(1, 'killswitch'))
      listener = described_class.register(config)

      expect(config[:lifecycle_events][:startup]).not_to be_empty
      expect(config[:lifecycle_events][:shutdown]).not_to be_empty
      listener.stop
    end
  end
end
