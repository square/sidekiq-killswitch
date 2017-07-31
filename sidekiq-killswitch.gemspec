# frozen_string_literal: true
require File.expand_path('../lib/sidekiq/killswitch/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = 'sidekiq-killswitch'
  gem.version       = Sidekiq::Killswitch::VERSION
  gem.summary       = 'Cross-host Sidekiq worker killswitches'
  gem.authors       = ['Yuriy Naidyon']
  gem.email         = 'ynaidyon@squareup.com'

  gem.files         = `git ls-files`.split($RS)
  gem.test_files    = gem.files.grep(%r{spec/})
  gem.require_paths = ['lib']
  gem.required_ruby_version = '>= 2.2.2'
  # gem.metadata['allowed_push_host'] = '???' # TODO: set this attribute

  gem.add_runtime_dependency 'sidekiq', '>= 3'

  gem.add_development_dependency 'rspec', '~> 3.6'
  gem.add_development_dependency 'rack-test'
  gem.add_development_dependency 'rspec-html-matchers'
  gem.add_development_dependency 'rubocop', '~> 0.49.1'
end
