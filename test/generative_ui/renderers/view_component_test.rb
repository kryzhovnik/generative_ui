# frozen_string_literal: true

require "test_helper"

class ViewComponentRendererTest < Minitest::Test
  ViewComponentRenderer = GenerativeUI::Renderers::ViewComponent

  class FakeViewComponent
    attr_reader :attributes, :additional_properties

    def initialize(**attributes)
      @additional_properties = attributes.delete(:additional_properties)
      @attributes = attributes
    end
  end

  class ViewContext
    attr_reader :rendered

    def render(component)
      @rendered = component
    end
  end

  def test_passes_materialized_attributes_to_component
    catalog = Class.new(GenerativeUI::Catalog) do
      component 'ViewText' do
        attributes { string :display_name }
        present_with :view_component, FakeViewComponent
      end
    end.new

    set = GenerativeUI::ComponentSet.from_args([
      { "id" => "root", "component" => "ViewText", "displayName" => "Ada" }
    ])
    view_context = ViewContext.new

    ViewComponentRenderer.new(view_context:, catalog: catalog).call(set)

    assert_equal({ display_name: "Ada" }, view_context.rendered.attributes)
  end

  def test_passes_open_schema_values_under_additional_properties
    catalog = Class.new(GenerativeUI::Catalog) do
      component 'OpenViewText' do
        attributes do
          string :title
          additional_properties true
        end
        present_with :view_component, FakeViewComponent
      end
    end.new

    set = GenerativeUI::ComponentSet.from_args([
      { "id" => "root", "component" => "OpenViewText", "title" => "Hello", "customValue" => "extra" }
    ])
    view_context = ViewContext.new

    ViewComponentRenderer.new(view_context:, catalog: catalog).call(set)

    assert_equal({ title: "Hello" }, view_context.rendered.attributes)
    assert_equal({ "custom_value" => "extra" }, view_context.rendered.additional_properties)
  end
end
