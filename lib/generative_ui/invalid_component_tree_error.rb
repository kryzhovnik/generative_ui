# frozen_string_literal: true

module GenerativeUI
  class InvalidComponentTreeError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super("Invalid generative UI component tree: #{errors.inspect}")
    end
  end
end
