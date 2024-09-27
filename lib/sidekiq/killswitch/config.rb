# frozen_string_literal: true

module Sidekiq
  module Killswitch
    class Config
      attr_accessor :web_ui_worker_validator
      attr_writer :logger

      def initialize
        self.web_ui_worker_validator = ->(worker_name) { !worker_name.nil? && worker_name != '' }
      end

      def logger
        @logger ||= Sidekiq.logger
      end

      def validate_worker_class_in_web
        self.web_ui_worker_validator = proc do |worker_name|
          begin
            constantize(worker_name).include?(Sidekiq::Worker)
          rescue NameError
            false
          end
        end
      end

      private

      def constantize(str)
        names = str.split('::')
        names.shift if names.empty? || names.first.empty?

        names.inject(Object) do |constant, name|
          constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
        end
      end
    end
  end
end
