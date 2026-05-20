# frozen_string_literal: true

require 'test_helper'
require 'action_controller/railtie'
require 'action_view/railtie'

module DummyApp
  class Application < Rails::Application
    config.eager_load = false
    config.api_only = false
    config.secret_key_base = 'test'
    config.logger = Logger.new(IO::NULL)
    config.hosts.clear if config.respond_to?(:hosts)
  end
end

DummyApp::Application.initialize! unless DummyApp::Application.initialized?

class RailsEngineIntegrationTest < Minitest::Test
  def test_engine_registers_active_support_inflections_for_rails_constantize_paths
    assert_equal 'GenerativeUI', 'generative_ui'.camelize
    assert_same GenerativeUI, 'generative_ui'.camelize.constantize
  end

  def test_tool_call_partial_renders_through_actionview
    default_catalog = Class.new(GenerativeUI::Catalog) do
      component('Text') { attributes { string :text } }
    end
    GenerativeUI.configure { |config| config.catalog :default, default_catalog }
    GenerativeUI.configuration.default_renderer = :json

    tool_call = Struct.new(:arguments).new(
      { 'components' => [{ 'id' => 'root', 'component' => 'Text', 'text' => 'integration-marker' }] }
    )

    output = ActionController::Base.renderer.render(
      partial: 'messages/tool_calls/generate_ui',
      locals: { tool_call: tool_call }
    )

    assert_includes output, 'integration-marker',
                    'rendered partial should contain the json-rendered component text'
  end

  def test_invalid_tool_call_partial_emits_notification
    default_catalog = Class.new(GenerativeUI::Catalog) do
      component('Text') { attributes { string :text } }
    end
    GenerativeUI.configure { |config| config.catalog :default, default_catalog }
    GenerativeUI.configuration.default_renderer = :json

    tool_call = Struct.new(:arguments).new(
      { 'components' => [{ 'id' => 'wrong-root', 'component' => 'Text', 'text' => 'x' }] }
    )

    events = []
    subscriber = ActiveSupport::Notifications.subscribe('invalid_tree.generative_ui') do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    output = ActionController::Base.renderer.render(
      partial: 'messages/tool_calls/generate_ui',
      locals: { tool_call: tool_call }
    )

    assert_equal '', output.strip, 'invalid tree should render nothing'
    assert_equal 1, events.size
    assert_kind_of GenerativeUI::InvalidComponentTreeError, events.first.payload[:error]
    assert_same tool_call, events.first.payload[:tool_call]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
