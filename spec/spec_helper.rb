# frozen_string_literal: true
require 'rspec'
require 'logger'
require 'rack/test'
require 'sidekiq/testing'
require 'sidekiq/killswitch'

ENV['RACK_ENV'] = 'test' # Disable CSRF protection for Sidekiq Web app
$TESTING = true

Sidekiq::Killswitch.configure do |config|
  config.logger = Logger.new('/dev/null')
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.before do
    Sidekiq::Killswitch.redis_pool { |c| c.flushdb }
  end
end

def stub_time_now(time_now = Time.now)
  allow(Time).to receive(:now).and_return(time_now)
  time_now
end
