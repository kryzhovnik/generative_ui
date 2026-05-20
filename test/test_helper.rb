# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'rails'
require 'generative_ui'
require 'minitest/autorun'

module ConfigurationIsolation
  def setup
    GenerativeUI.reset_configuration!
    super
  end

  def teardown
    super
  ensure
    GenerativeUI.reset_configuration!
  end
end

Minitest::Test.prepend(ConfigurationIsolation)
