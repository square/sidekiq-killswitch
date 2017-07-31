# frozen_string_literal: true
require 'spec_helper'

RSpec.describe Sidekiq::Killswitch::Middleware::Client do
  let(:client_middleware) { Sidekiq::Killswitch::Middleware::Client.new }

  describe '#call' do
    it 'should return false for blackholed workers' do
      stub_const('DisabledWorker', Class.new {})

      Sidekiq::Killswitch.blackhole_add_worker(DisabledWorker)
      Sidekiq::Killswitch.blackhole_add_worker('MyWorker')

      expect(client_middleware.call(DisabledWorker, {}, nil, nil) { 123 }).to eq(false)
      expect(client_middleware.call('MyWorker', {}, nil, nil) { 123 }).to eq(false)
    end

    it 'should return block result for not blockholed workers' do
      stub_const('EnabledWorker', Class.new {})

      expect(client_middleware.call(EnabledWorker, {}, nil, nil) { 'result' }).to eq('result')
      expect(client_middleware.call('EnabledWorker', {}, nil, nil) { 123 }).to eq(123)
    end
  end
end
