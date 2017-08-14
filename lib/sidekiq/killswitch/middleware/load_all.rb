# frozen_string_literal: true
require 'sidekiq'

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add Sidekiq::Killswitch::Middleware::Server
  end

  config.client_middleware do |chain|
    # The jobs running in the Sidekiq server can themselves push new jobs to Sidekiq.
    chain.add Sidekiq::Killswitch::Middleware::Client
  end
end

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Killswitch::Middleware::Client
  end
end
