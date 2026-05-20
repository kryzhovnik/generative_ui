# frozen_string_literal: true

require 'test_helper'
require_relative '../../app/helpers/generative_ui/view_helper'

class ViewHelperTest < Minitest::Test
  class ViewContext
    include GenerativeUI::ViewHelper
  end

  def setup
    GenerativeUI.reset_configuration!
    ui_catalog = Class.new(GenerativeUI::Catalog) do
      component 'Text' do
        attributes { string :text }
      end
      component 'Column' do
        attributes { many_components :children }
      end
    end
    GenerativeUI.configure { |config| config.catalog :ui, ui_catalog }
  end

  def teardown
    GenerativeUI.reset_configuration!
  end

  def test_render_generative_ui_uses_explicit_renderer
    renderer = Struct.new(:set, :catalog) do
      def call(set)
        self.set = set
        'rendered'
      end
    end.new

    GenerativeUI.configure do |config|
      config.register_renderer(:phlex) { |_view_context| renderer }
    end

    result = ViewContext.new.render_generative_ui(
      { 'components' => [{ 'id' => 'root', 'component' => 'Text', 'text' => 'Hello' }] },
      catalog: :ui,
      renderer: :phlex
    )

    assert_equal 'rendered', result
    assert_equal 'root', renderer.set.root.id
  end

  def test_render_generative_ui_raises_for_invalid_payload
    error = assert_raises(GenerativeUI::InvalidComponentTreeError) do
      ViewContext.new.render_generative_ui(
        { 'components' => [{ 'id' => 'root', 'component' => 'Column', 'children' => ['ghost'] }] },
        catalog: :ui
      )
    end

    assert error.errors.key?('root.children')
    assert_includes error.errors['root.children'].join, 'ghost'
  end

  def test_render_generative_ui_raises_argument_error_for_non_hash_arguments
    assert_raises(ArgumentError) { ViewContext.new.render_generative_ui(nil, catalog: :ui) }
    assert_raises(ArgumentError) { ViewContext.new.render_generative_ui('oops', catalog: :ui) }
  end

  def test_render_generative_ui_raises_for_unknown_top_level_keys
    error = assert_raises(GenerativeUI::InvalidComponentTreeError) do
      ViewContext.new.render_generative_ui(
        { 'components' => [], 'tool_call_id' => 'abc' },
        catalog: :ui
      )
    end

    assert error.errors.key?('_arguments')
    assert_includes error.errors['_arguments'].join, 'tool_call_id'
  end

  def test_render_generative_ui_raises_when_components_missing
    error = assert_raises(GenerativeUI::InvalidComponentTreeError) do
      ViewContext.new.render_generative_ui({}, catalog: :ui)
    end

    assert error.errors.key?('_arguments')
  end
end
