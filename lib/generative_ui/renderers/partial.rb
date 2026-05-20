# frozen_string_literal: true

module GenerativeUI
  module Renderers
    class Partial < Renderer
      ADAPTER = :partial

      def initialize(view_context:, catalog: :default)
        super(catalog:)
        @view_context = view_context
      end

      def render_component(definition:, attributes:, additional_properties:)
        locals = attributes.dup
        locals[:additional_properties] = additional_properties unless additional_properties.nil?

        @view_context.render(
          partial: catalog.target_for(definition, ADAPTER),
          locals:
        )
      end
    end
  end
end
