# frozen_string_literal: true

require 'test_helper'

class JsonRendererTest < Minitest::Test
  ComponentSet = GenerativeUI::ComponentSet
  Json = GenerativeUI::Renderers::Json

  UiCatalog = Class.new(GenerativeUI::Catalog) do
    component 'Text' do
      desc 'Render text'
      attributes { string :text }
    end

    component 'Column' do
      desc 'Stack children'
      attributes { many_components :children }
    end

    component 'Tabs' do
      desc 'Render tabs'
      attributes do
        array :tab_items do
          object do
            string :title
            one_component :content, only: 'Text'
          end
        end
      end
    end
  end

  def test_renders_leaf_as_hash
    set = component_set([
                          { 'id' => 'root', 'component' => 'Text', 'text' => 'Hello' }
                        ])

    assert_equal(
      { 'component' => 'Text', 'props' => { 'text' => 'Hello' } },
      Json.new(catalog: UiCatalog).call(set)
    )
  end

  def test_raises_when_component_is_not_in_catalog
    set = component_set([
                          { 'id' => 'root', 'component' => 'NotInCatalog', 'text' => 'x' }
                        ])

    error = assert_raises(ArgumentError) { Json.new(catalog: UiCatalog).call(set) }
    assert_includes error.message, 'NotInCatalog'
  end

  def test_renders_many_children_in_order
    set = component_set([
                          { 'id' => 'root', 'component' => 'Column', 'children' => %w[text-a text-b text-c] },
                          { 'id' => 'text-a', 'component' => 'Text', 'text' => 'A' },
                          { 'id' => 'text-b', 'component' => 'Text', 'text' => 'B' },
                          { 'id' => 'text-c', 'component' => 'Text', 'text' => 'C' }
                        ])

    result = Json.new(catalog: UiCatalog).call(set)

    assert_equal(%w[A B C], result.dig('props', 'children').map { |child| child.dig('props', 'text') })
  end

  def test_materializes_nested_child_refs_by_default
    set = component_set([
                          {
                            'id' => 'root',
                            'component' => 'Tabs',
                            'tabItems' => [
                              { 'title' => 'General', 'content' => 'text-1' }
                            ]
                          },
                          { 'id' => 'text-1', 'component' => 'Text', 'text' => 'Panel' }
                        ])

    result = Json.new(catalog: UiCatalog).call(set)

    assert_equal 'General', result.dig('props', 'tab_items', 0, 'title')
    assert_equal 'Text', result.dig('props', 'tab_items', 0, 'content', 'component')
  end

  def test_can_emit_flat_graph
    set = component_set([
                          {
                            'id' => 'root',
                            'component' => 'Tabs',
                            'tabItems' => [
                              { 'title' => 'General', 'content' => 'text-1' }
                            ]
                          },
                          { 'id' => 'text-1', 'component' => 'Text', 'text' => 'Panel' }
                        ])

    result = Json.new(catalog: UiCatalog, mode: :flat).call(set)

    assert_equal(%w[root text-1], result.fetch('components').map { |component| component.fetch('id') })
    assert_equal 'text-1', result.fetch('components').first.fetch('tabItems').first.fetch('content')
  end

  private

  def component_set(raw)
    ComponentSet.from_args(raw)
  end
end
