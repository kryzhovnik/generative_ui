# frozen_string_literal: true

module GenerativeUI
  module Renderers
    class ViewComponent < Renderer
      ADAPTER = :view_component

      def initialize(view_context:, catalog: :default)
        super(catalog:)
        @view_context = view_context
      end

      def render_component(definition:, attributes:, additional_properties:)
        component_class = resolve(catalog.target_for(definition, ADAPTER))
        kwargs = attributes.dup
        kwargs[:additional_properties] = additional_properties unless additional_properties.nil?
        @view_context.render(component_class.new(**kwargs))
      end

      private

      def resolve(target)
        target.is_a?(String) ? target.constantize : target
      end
    end
  end
end
