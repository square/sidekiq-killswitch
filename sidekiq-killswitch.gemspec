# frozen_string_literal: true
require File.expand_path('lib/sidekiq/killswitch/version', __dir__)

Gem::Specification.new do |gem|
  gem.name          = 'sidekiq-killswitch'
  gem.version       = Sidekiq::Killswitch::VERSION
  gem.summary       = 'Cross-host Sidekiq worker killswitches'
  gem.authors       = ['Yuriy Naidyon']
  gem.email         = 'yurokle@gmail.com'
  gem.license       = 'Apache-2.0'
  gem.homepage      = 'https://github.com/square/sidekiq-killswitch'

  gem.files         = `git ls-files`.split($RS)
  gem.test_files    = gem.files.grep(%r{spec/})
  gem.require_paths = ['lib']
  gem.required_ruby_version = '>= 3.2'
  gem.metadata['allowed_push_host'] = 'https://rubygems.org'

  gem.add_runtime_dependency 'sidekiq', '~> 8.0'

  gem.add_development_dependency 'rack-test'
  gem.add_development_dependency 'rspec', '~> 3.6'
  gem.add_development_dependency 'rspec-html-matchers'
  gem.add_development_dependency 'rubocop', '~> 1.92'
end
