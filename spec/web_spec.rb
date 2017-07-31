# frozen_string_literal: true
require 'spec_helper'
require 'rack/test'
require 'rspec-html-matchers'
require 'sidekiq/killswitch/web'

RSpec.describe Sidekiq::Killswitch::Web do
  include Rack::Test::Methods
  include RSpecHtmlMatchers

  let(:app) { Sidekiq::Web }

  def expect_redirect_to_root_page(response)
    expect(response.status).to be(302)
    expect(response.headers['Location']).to eq("http://#{rack_mock_session.default_host}/kill-switches")
  end

  describe 'GET /kill-switches' do
    it 'should list blackholed workers' do
      Sidekiq::Killswitch.blackhole_add_worker('WorkerOne')
      Sidekiq::Killswitch.blackhole_add_worker('WorkerTwo')

      response = get('/kill-switches')
      expect(response.status).to be(200)

      expect(response.body).to have_tag('.blackhole-workers') do
        with_text('WorkerOne')
        with_text('WorkerTwo')
      end
    end

    it 'should list dead-queued workers' do
      Sidekiq::Killswitch.dead_queue_add_worker('DeadWorkerOne')
      Sidekiq::Killswitch.dead_queue_add_worker('DeadWorkerTwo')

      response = get('/kill-switches')

      expect(response.body).to have_tag('.dead-queue-workers') do
        with_text('DeadWorkerOne')
        with_text('DeadWorkerTwo')
      end
    end
  end

  describe 'POST /kill-switches/blackhole_add' do
    it 'should blackhole passed worker' do
      response = post('/kill-switches/blackhole_add', worker_name: 'BlackholedWorker')

      expect_redirect_to_root_page(response)
      expect(Sidekiq::Killswitch.blackhole_worker?('BlackholedWorker')).to be_truthy
    end

    describe 'validation' do
      around do |example|
        default_validator = Sidekiq::Killswitch.config.web_ui_worker_validator
        example.run
        Sidekiq::Killswitch.config.web_ui_worker_validator = default_validator
      end

      it 'should perform basic default validation' do
        post('/kill-switches/blackhole_add', worker_name: '')
        follow_redirect!

        expect(last_response.body).to have_tag('.error-message', text: 'Error: Invalid worker name!')
      end

      it 'should perform custom validation' do
        Sidekiq::Killswitch.config.web_ui_worker_validator = ->(name) { name.end_with?('BlockedWorker') }

        post('/kill-switches/blackhole_add', worker_name: 'BadWorker')
        follow_redirect!
        expect(last_response.body).to have_tag('.error-message', text: 'Error: Invalid worker name!')

        post('/kill-switches/blackhole_add', worker_name: 'MyBlockedWorker')
        expect(Sidekiq::Killswitch.blackhole_worker?('MyBlockedWorker')).to be_truthy
      end
    end
  end

  describe 'POST /kill-switches/blackhole_remove' do
    it 'should remove worker from blackhole' do
      Sidekiq::Killswitch.blackhole_add_worker('BlakcholedWorker')

      response = post('/kill-switches/blackhole_remove', worker_name: 'BlackholedWorker')

      expect_redirect_to_root_page(response)
      expect(Sidekiq::Killswitch.blackhole_worker?('BlackholedWorker')).to be_falsey
    end
  end

  describe 'POST /kill-switches/dead_queue_add' do
    it 'should add passed worker to dead queue' do
      response = post('/kill-switches/dead_queue_add', worker_name: 'DeadWorker')

      expect_redirect_to_root_page(response)
      expect(Sidekiq::Killswitch.dead_queue_worker?('DeadWorker')).to be_truthy
    end
  end

  describe 'POST /kill-switches/dead_queue_remove' do
    it 'should remove worker from dead queue' do
      Sidekiq::Killswitch.dead_queue_add_worker('DeadWorker')

      response = post('/kill-switches/dead_queue_remove', worker_name: 'DeadWorker')

      expect_redirect_to_root_page(response)
      expect(Sidekiq::Killswitch.dead_queue_worker?('DeadWorker')).to be_falsey
    end
  end
end
