# frozen_string_literal: true

def safe_load(&block)
  yield
rescue LoadError
end

safe_load do
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
end

safe_load do
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new
end

task default: %w(spec rubocop)
