# frozen_string_literal: true
require 'spec_helper'

RSpec.describe Sidekiq::DeadSet do
  let(:dead_set) { Sidekiq::DeadSet.new }

  describe '#kill' do
    it 'should put passed serialized job to the "dead" sorted set' do
      serialized_job = Sidekiq.dump_json(jid: '123123', class: 'SomeWorker', args: [])
      dead_set.kill(serialized_job)

      expect(dead_set.find_job('123123').value).to eq(serialized_job)
    end

    it 'should remove dead jobs older than Sidekiq::DeadSet.timeout' do
      allow(Sidekiq::DeadSet).to receive(:timeout).and_return(10)
      time_now = Time.now

      stub_time_now(time_now - 11)
      dead_set.kill(Sidekiq.dump_json({jid: '000103', class: 'MyWorker3', args: []})) # the oldest

      stub_time_now(time_now - 9)
      dead_set.kill(Sidekiq.dump_json({jid: '000102', class: 'MyWorker2', args: []}))

      stub_time_now(time_now)
      dead_set.kill(Sidekiq.dump_json({jid: '000101', class: 'MyWorker1', args: []}))

      stub_time_now(time_now)

      expect(dead_set.find_job('000103')).to be_falsey
      expect(dead_set.find_job('000102')).to be_truthy
      expect(dead_set.find_job('000101')).to be_truthy
    end

    it 'should remove all but last Sidekiq::DeadSet.max_jobs-1 jobs' do
      allow(Sidekiq::DeadSet).to receive(:max_jobs).and_return(3)

      dead_set.kill(Sidekiq.dump_json({jid: '000101', class: 'MyWorker1', args: []}))
      dead_set.kill(Sidekiq.dump_json({jid: '000102', class: 'MyWorker2', args: []}))
      dead_set.kill(Sidekiq.dump_json({jid: '000103', class: 'MyWorker3', args: []}))

      expect(dead_set.find_job('000101')).to be_falsey
      expect(dead_set.find_job('000102')).to be_truthy
      expect(dead_set.find_job('000103')).to be_truthy
    end
  end
end
