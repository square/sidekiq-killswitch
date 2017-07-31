# frozen_string_literal: true
require 'spec_helper'

RSpec.describe Sidekiq::Killswitch::Config do
  let(:config) { Sidekiq::Killswitch::Config.new }

  describe '#web_ui_worker_validator' do
    it 'should to string presence validation by default' do
      expect(config.web_ui_worker_validator.call(nil)).to be_falsey
      expect(config.web_ui_worker_validator.call('')).to be_falsey
      expect(config.web_ui_worker_validator.call('MyWorker')).to be_truthy
    end
  end

  describe '#validate_worker_class_in_web' do
    it 'should set Sidekiq::Worker module inclusion check as validator' do
      stub_const('GoodWorker', Class.new {
        include Sidekiq::Worker
      })
      stub_const('AlsoGoodWorker', Class.new(GoodWorker) {})
      stub_const('BadWorker', Class.new {})

      config.validate_worker_class_in_web

      expect(config.web_ui_worker_validator.call('GoodWorker')).to be_truthy
      expect(config.web_ui_worker_validator.call('AlsoGoodWorker')).to be_truthy

      expect(config.web_ui_worker_validator.call('BadWorker')).to be_falsey
      expect(config.web_ui_worker_validator.call('')).to be_falsey
      expect(config.web_ui_worker_validator.call('Sidekiq::Worker')).to be_falsey
    end
  end
end
