# frozen_string_literal: true
require 'spec_helper'

RSpec.describe Sidekiq::Killswitch::Middleware::Server do
  let(:server_middleware) { Sidekiq::Killswitch::Middleware::Server.new }

  before do
    stub_const('MyWorker', Class.new {
      include Sidekiq::Worker
      def perform; end
    })
  end

  describe '#call' do
    context 'for blackholed workers' do
      it 'should not run block' do
        Sidekiq::Killswitch.blackhole_add_worker(MyWorker)

        expect do
          server_middleware.call(MyWorker.new, {}, nil) { raise 'Should not run' }
        end.to_not raise_error
      end
    end

    context 'for dead-queued workers' do
      it 'should send a job to the morgue' do
        Sidekiq::Killswitch.dead_queue_add_worker(MyWorker)

        job_data = {job: :details}
        serialized_job = Sidekiq.dump_json(job_data)
        expect_any_instance_of(Sidekiq::DeadSet).to receive(:kill).with(serialized_job)

        expect do
          server_middleware.call(MyWorker.new, job_data, nil) { raise 'Should not run' }
        end.to_not raise_error
      end
    end

    context 'for non-marked workers' do
      it 'should run passed block' do
        checkpoint = double
        expect(checkpoint).to receive(:check)
        server_middleware.call(MyWorker.new, {}, nil) { checkpoint.check }
      end
    end
  end
end
