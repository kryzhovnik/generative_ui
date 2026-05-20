# frozen_string_literal: true

require "test_helper"

class PartialRendererTest < Minitest::Test
  Partial = GenerativeUI::Renderers::Partial

  class ViewContext
    attr_reader :calls

    def initialize
      @calls = []
    end

    def render(**kwargs)
      @calls << kwargs
      return "<text>#{kwargs.fetch(:locals).fetch(:text)}</text>" if kwargs[:partial] == "generative_ui/text"

      kwargs
    end
  end

  def test_uses_catalog_to_resolve_render_target
    catalog = Class.new(GenerativeUI::Catalog) do
      component 'Weather' do
        desc 'Test fixture'
        attributes do
          string :location
          number :temperature
          string :unit, enum: %w[c f], required: false
        end
      end
    end.new

    view_context = ViewContext.new
    renderer = Partial.new(view_context: view_context, catalog: catalog)

    renderer.render_component(
      definition: catalog.fetch('Weather'),
      attributes: { 'location' => 'Belgrade' },
      additional_properties: {}
    )

    assert_equal "generative_ui/weather", view_context.calls.first[:partial]
  end

  def test_receives_materialized_snake_case_locals
    catalog = Class.new(GenerativeUI::Catalog) do
      component 'Text' do
        desc 'Render text'
        attributes { string :text }
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
    end.new

    set = GenerativeUI::ComponentSet.from_args([
      {
        "id" => "root",
        "component" => "Tabs",
        "tabItems" => [
          { "title" => "General", "content" => "text-1" }
        ]
      },
      { "id" => "text-1", "component" => "Text", "text" => "Panel" }
    ])

    view_context = ViewContext.new
    Partial.new(view_context: view_context, catalog: catalog).call(set)

    tabs_call = view_context.calls.last
    assert_equal(
      {
        tab_items: [
          { title: "General", content: "<text>Panel</text>" }
        ]
      },
      tabs_call[:locals]
    )
  end

  def test_collects_undeclared_keys_under_additional_properties
    catalog = Class.new(GenerativeUI::Catalog) do
      component 'OpenPartial' do
        attributes do
          string :title
          additional_properties true
        end
      end
    end.new

    set = GenerativeUI::ComponentSet.from_args([
      { "id" => "root", "component" => "OpenPartial", "title" => "Hello", "customValue" => "extra" }
    ])

    view_context = ViewContext.new
    Partial.new(view_context:, catalog: catalog).call(set)

    assert_equal(
      {
        title: "Hello",
        additional_properties: { "custom_value" => "extra" }
      },
      view_context.calls.last[:locals]
    )
  end
end
