# frozen_string_literal: true

require 'test_helper'

class ComponentDefinitionTest < Minitest::Test
  ComponentDefinition = GenerativeUI::ComponentDefinition

  def test_dsl_block_sets_desc_and_attributes
    definition = ComponentDefinition.build('Text') do
      desc 'Render plain text.'
      attributes { string :text }
    end

    assert_equal 'Text', definition.component
    assert_equal 'Text', definition.name
    assert_equal 'Render plain text.', definition.description_text
    refute_nil definition.attributes_definition
    assert_equal 'string', definition.attributes_json_schema.dig(:properties, :text, :type)
  end

  def test_render_target_for_returns_per_component_target
    definition = ComponentDefinition.build('Text') do
      attributes { string :text }
      present_with :partial, 'shared/widgets/text'
    end

    assert_equal 'shared/widgets/text', definition.render_target_for(:partial)
    assert_nil definition.render_target_for(:view_component)
  end

  def test_multiple_adapters_coexist
    definition = ComponentDefinition.build('Card') do
      present_with :partial, 'shared/card'
      present_with :view_component, 'CardComponent'
    end

    assert_equal 'shared/card', definition.render_target_for(:partial)
    assert_equal 'CardComponent', definition.render_target_for(:view_component)
  end

  def test_duplicate_adapter_raises
    error = assert_raises(ArgumentError) do
      ComponentDefinition.build('Text') do
        present_with :partial, 'first'
        present_with :partial, 'second'
      end
    end

    assert_includes error.message, ':partial'
    assert_includes error.message, 'Text'
  end

  def test_structural_refs_delegates_to_attributes_definition
    definition = ComponentDefinition.build('Card') do
      attributes do
        one_component :title, only: 'Text'
        many_components :children
      end
    end

    refs = definition.structural_refs

    assert_equal 2, refs.length
    assert_equal %i[title], refs.first.path
  end
end
