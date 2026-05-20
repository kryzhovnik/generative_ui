# frozen_string_literal: true

require 'test_helper'

class ToolTest < Minitest::Test
  Catalog = GenerativeUI::Catalog
  Tool = GenerativeUI::Tool

  def ui_catalog
    @ui_catalog ||= Class.new(GenerativeUI::Catalog) do
      component 'Text' do
        desc 'Render text'
        attributes { string :text }
      end
      component 'Button' do
        attributes do
          one_component :label, only: 'Text'
          string :action
        end
      end
      component 'Column' do
        attributes { many_components :children }
      end
      component 'Tabs' do
        attributes do
          array :tab_items do
            object do
              string :title
              one_component :content, only: 'Text'
            end
          end
        end
      end
    end.new
  end

  def test_tool_schema_is_compiled_from_catalog
    schema = Tool.new(catalog: ui_catalog).params_schema

    assert_equal 'object', schema.fetch('type')
    assert schema.dig('properties', 'components', 'items', 'anyOf')
  end

  def test_tool_uses_default_catalog_by_default
    default_catalog = Class.new(GenerativeUI::Catalog) do
      component 'DefaultToolText' do
        attributes { string :text }
      end
    end
    GenerativeUI.configure { |c| c.catalog :default, default_catalog }
    tool = Tool.new

    assert_equal ['DefaultToolText'], tool.catalog.names
  end

  def test_tool_raises_when_catalog_is_empty
    empty_catalog = Class.new(GenerativeUI::Catalog).new

    assert_raises(ArgumentError) { Tool.new(catalog: empty_catalog) }
  end

  def test_tool_has_stable_name
    tool = Tool.new(catalog: ui_catalog)

    assert_equal 'generate_ui', tool.name
  end

  def test_description_advertises_every_component_from_the_catalog
    tool = Tool.new(catalog: ui_catalog)

    %w[Text Button Column Tabs].each do |name|
      assert_includes tool.description, name, "description should advertise #{name}"
    end
    assert_includes tool.description, 'Render text', 'description should include component descriptions'
  end

  def test_execute_returns_ok_for_valid_components
    result = JSON.parse(tool.execute(components: valid_components))

    assert_equal 'ok', result.fetch('status')
  end

  def test_execute_returns_compact_errors_for_invalid_components
    result = JSON.parse(tool.execute(components: [
                                       { 'id' => 'root', 'component' => 'Column', 'children' => ['ghost'] }
                                     ]))

    assert_equal 'invalid', result.fetch('status')
    assert result.fetch('errors').key?('root.children')
  end

  def test_execute_returns_structured_error_when_components_kwarg_missing
    result = JSON.parse(tool.call({}))

    assert_equal 'invalid', result.fetch('status')
    assert result['errors'].key?('_arguments')
  end

  def test_execute_returns_structured_error_when_components_is_not_an_array
    result = JSON.parse(tool.call('components' => 'oops'))

    assert_equal 'invalid', result.fetch('status')
    assert result['errors'].key?('_arguments')
  end

  def test_execute_rejects_unknown_top_level_keys
    result = JSON.parse(tool.call('components' => [], 'foo' => 'bar', 'baz' => 1))

    assert_equal 'invalid', result.fetch('status')
    message = result.dig('errors', '_arguments').join("\n")
    assert_includes message, 'foo'
    assert_includes message, 'baz'
  end

  private

  def tool
    Tool.new(catalog: ui_catalog)
  end

  def valid_components
    [
      { 'id' => 'root', 'component' => 'Column', 'children' => ['text-1'] },
      { 'id' => 'text-1', 'component' => 'Text', 'text' => 'Hello' }
    ]
  end
end
