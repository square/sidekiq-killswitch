# frozen_string_literal: true
require 'spec_helper'

RSpec.describe Sidekiq::Killswitch do
  # !!!!! HERE BE DRAGONS !!!!!
  # Make sure to return test config to the working state after testing ...
  # ... consider using Rspec.around wrapper:
  #
  # around do |example|
  #   original_test_logger = Sidekiq::Killswitch.logger
  #   example.run
  #   Sidekiq::Killswitch.logger = original_test_logger
  # end

  around do |example|
    original_test_logger = Sidekiq::Killswitch.config.logger

    example.run

    Sidekiq::Killswitch.config.logger = original_test_logger
  end

  let(:worker_name) { 'SomeWorker' }

  describe '.configure' do
    describe '.logger= ' do
      it 'should allow to set the logger' do
        logger = double

        Sidekiq::Killswitch.configure do |config|
          config.logger = logger
        end

        expect(Sidekiq::Killswitch.logger).to eq(logger)
      end
    end
  end

  describe '.blackhole_add_worker' do
    it 'should mark a worker as blackholed in Redis' do
      time_now = stub_time_now

      Sidekiq::Killswitch.blackhole_add_worker(worker_name)

      Sidekiq::Killswitch.redis_pool do |redis|
        expect(redis.hget(Sidekiq::Killswitch::BLACKHOLE_WORKERS_KEY_NAME, worker_name)).to eq(time_now.to_s)
      end
    end

    it 'should accept class object as a parameter' do
      time_now = stub_time_now
      stub_const('AnotherWorker', Class.new {})

      Sidekiq::Killswitch.blackhole_add_worker(AnotherWorker)

      Sidekiq::Killswitch.redis_pool do |redis|
        expect(redis.hget(Sidekiq::Killswitch::BLACKHOLE_WORKERS_KEY_NAME, 'AnotherWorker')).to eq(time_now.to_s)
      end
    end

    it 'trims whitespaces off worker names' do
      time_now = stub_time_now

      Sidekiq::Killswitch.blackhole_add_worker("   #{worker_name}   ")

      Sidekiq::Killswitch.redis_pool do |redis|
        expect(redis.hget(Sidekiq::Killswitch::BLACKHOLE_WORKERS_KEY_NAME, worker_name)).to eq(time_now.to_s)
      end
    end
  end

  describe '.blackhole_remove_worker' do
    it 'should remove worker from the list of blackholed workers' do
      Sidekiq::Killswitch.blackhole_add_worker(worker_name)
      Sidekiq::Killswitch.blackhole_remove_worker(worker_name)

      Sidekiq::Killswitch.redis_pool do |redis|
        expect(redis.hexists(Sidekiq::Killswitch::BLACKHOLE_WORKERS_KEY_NAME, worker_name)).to eq(0)
      end
    end

    it 'trims whitespaces off worker names' do
      Sidekiq::Killswitch.blackhole_add_worker(worker_name)
      Sidekiq::Killswitch.blackhole_remove_worker("   #{worker_name}   ")

      Sidekiq::Killswitch.redis_pool do |redis|
        expect(redis.hexists(Sidekiq::Killswitch::BLACKHOLE_WORKERS_KEY_NAME, worker_name)).to eq(0)
      end
    end
  end

  describe '.blackhole_worker?' do
    it 'should return true for blackholed workers' do
      Sidekiq::Killswitch.blackhole_add_worker(worker_name)
      expect(Sidekiq::Killswitch.blackhole_worker?(worker_name)).to be_truthy
    end

    it 'should return false for non-blackholed workers' do
      expect(Sidekiq::Killswitch.blackhole_worker?(worker_name)).to be_falsey
    end
  end

  describe '.blackhole_workers' do
    it 'should return a list of all blackholed workers with "added at" timestamps' do
      first_worker_added_at = stub_time_now
      Sidekiq::Killswitch.blackhole_add_worker('FirstWorker')
      second_worker_added_at = stub_time_now(first_worker_added_at + 1)
      Sidekiq::Killswitch.blackhole_add_worker('SecondWorker')

      expect(Sidekiq::Killswitch.blackhole_workers).to eq({
        'FirstWorker' => first_worker_added_at.to_s,
        'SecondWorker' => second_worker_added_at.to_s
      })
    end
  end

  describe '.dead_queue_add_worker' do
    it 'should mark a worker as a "dead queue worker" in Redis' do
      time_now = stub_time_now

      Sidekiq::Killswitch.dead_queue_add_worker(worker_name)

      Sidekiq::Killswitch.redis_pool do |redis|
        expect(redis.hget(Sidekiq::Killswitch::DEAD_QUEUE_WORKERS_KEY_NAME, worker_name)).to eq(time_now.to_s)
      end
    end

    it 'trims whitespaces off worker names' do
      time_now = stub_time_now

      Sidekiq::Killswitch.dead_queue_add_worker("   #{worker_name}   ")

      Sidekiq::Killswitch.redis_pool do |redis|
        expect(redis.hget(Sidekiq::Killswitch::DEAD_QUEUE_WORKERS_KEY_NAME, worker_name)).to eq(time_now.to_s)
      end
    end
  end

  describe '.dead_queue_remove_worker' do
    it 'should remove worker from the list of dead queue workers' do
      Sidekiq::Killswitch.dead_queue_add_worker(worker_name)
      Sidekiq::Killswitch.dead_queue_remove_worker(worker_name)

      Sidekiq::Killswitch.redis_pool do |redis|
        expect(redis.hexists(Sidekiq::Killswitch::DEAD_QUEUE_WORKERS_KEY_NAME, worker_name)).to eq(0)
      end
    end

    it 'trims whitespaces off worker names' do
      Sidekiq::Killswitch.dead_queue_add_worker(worker_name)
      Sidekiq::Killswitch.dead_queue_remove_worker("   #{worker_name}   ")

      Sidekiq::Killswitch.redis_pool do |redis|
        expect(redis.hexists(Sidekiq::Killswitch::DEAD_QUEUE_WORKERS_KEY_NAME, worker_name)).to eq(0)
      end
    end
  end

  describe '.dead_queue_worker?' do
    it 'should return true for dead queue workers' do
      Sidekiq::Killswitch.dead_queue_add_worker(worker_name)
      expect(Sidekiq::Killswitch.dead_queue_worker?(worker_name)).to be_truthy
    end

    it 'should return false for non-dead-queue workers' do
      expect(Sidekiq::Killswitch.dead_queue_worker?(worker_name)).to be_falsey
    end
  end

  describe '.dead_queue_workers' do
    it 'should return a list of all dead queue workers with "added at" timestamps' do
      first_worker_added_at = stub_time_now
      Sidekiq::Killswitch.dead_queue_add_worker('FirstWorker')
      second_worker_added_at = stub_time_now(first_worker_added_at + 1)
      Sidekiq::Killswitch.dead_queue_add_worker('SecondWorker')

      expect(Sidekiq::Killswitch.dead_queue_workers).to eq({
        'FirstWorker' => first_worker_added_at.to_s,
        'SecondWorker' => second_worker_added_at.to_s
      })
    end
  end
end
