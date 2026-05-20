# frozen_string_literal: true

module GenerativeUI
  module Renderers
    class Json < Renderer
      def initialize(catalog: :default, mode: :materialized)
        super(catalog:)
        @mode = mode
      end

      def call(component_set)
        return { 'components' => component_set.components.map(&:to_h) } if @mode == :flat
        raise ArgumentError, "Unknown JSON render mode: #{@mode}" unless @mode == :materialized

        super
      end

      def render_component(definition:, attributes:, additional_properties:)
        props = attributes.dup
        props.merge!(additional_properties) if additional_properties

        { 'component' => definition.component, 'props' => props }.deep_stringify_keys
      end
    end
  end
end
