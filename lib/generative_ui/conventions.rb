# frozen_string_literal: true

module GenerativeUI
  module Conventions
    @rules = {}

    class << self
      def register(adapter, &block)
        @rules[adapter.to_sym] = block
      end

      def fetch(adapter)
        @rules.fetch(adapter.to_sym) do
          raise ArgumentError, "No convention registered for adapter: #{adapter.inspect}"
        end
      end
    end

    register(:partial)        { |name| "generative_ui/#{name.underscore}" }
    register(:view_component) { |name| "GenerativeUI::#{name.camelize}Component" }
  end
end
