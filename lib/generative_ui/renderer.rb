# frozen_string_literal: true

module GenerativeUI
  class Renderer
    def initialize(catalog: :default)
      @catalog_spec = catalog
    end

    def catalog=(value)
      @catalog_spec = value
      @catalog = nil
    end

    def catalog
      @catalog ||= Catalog.coerce(@catalog_spec)
    end

    def call(component_set)
      render_component_instance(component_set, component_set.root)
    end

    def render_component_instance(component_set, component)
      definition = catalog.fetch(component.name)
      raise ArgumentError, "Unknown generative component: #{component.name}" unless definition

      attributes, additional_properties = materialized_attributes(component_set, component, definition)
      render_component(definition:, attributes:, additional_properties:)
    end

    def render_component(definition:, attributes:, additional_properties:)
      raise NotImplementedError, "#{self.class} must implement #render_component"
    end

    private

    def materialized_attributes(component_set, component, definition)
      props = deep_dup(component.attributes)
      Array(definition&.structural_refs).each do |ref|
        replace_ref!(props, ref.path) do |child_id|
          render_component_instance(component_set, component_set.fetch(child_id))
        end
      end
      split_declared_attributes(underscore_string_keys(props), definition)
    end

    def split_declared_attributes(props, definition)
      declared_names = declared_attribute_names(definition)
      attributes = {}
      additional_properties = {}

      props.each do |key, value|
        if declared_names.include?(key)
          attributes[key.to_sym] = deep_symbolize_keys(value)
        else
          additional_properties[key] = value
        end
      end

      [attributes, additional_properties_enabled?(definition) ? additional_properties : nil]
    end

    def declared_attribute_names(definition)
      schema = definition&.attributes_json_schema || {}
      properties = schema[:properties] || schema['properties'] || {}
      properties.keys.map { |key| key.to_s.underscore }
    end

    def additional_properties_enabled?(definition)
      schema = definition&.attributes_json_schema || {}
      schema[:additionalProperties] || schema['additionalProperties']
    end

    def replace_ref!(value, path, &block)
      return if value.nil?

      segment, *rest = path
      if segment == :*
        Array(value).each { |item| replace_ref!(item, rest, &block) }
        return
      end

      key = matching_key(value, segment)
      return unless key

      if rest.empty?
        child = value[key]
        value[key] =
          if child.is_a?(Array)
            child.map(&block)
          else
            block.call(child)
          end
      else
        replace_ref!(value[key], rest, &block)
      end
    end

    def deep_dup(value)
      case value
      when Hash then value.transform_values { |child| deep_dup(child) }
      when Array then value.map { |child| deep_dup(child) }
      else value
      end
    end

    def underscore_string_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), transformed|
          normalized = key.is_a?(String) ? key.underscore : key
          transformed[normalized] = underscore_string_keys(child)
        end
      when Array
        value.map { |child| underscore_string_keys(child) }
      else
        value
      end
    end

    def matching_key(hash, segment)
      return unless hash.is_a?(Hash)

      [segment.to_s, segment.to_sym].find { |candidate| hash.key?(candidate) }
    end

    def deep_symbolize_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), transformed|
          transformed[key.to_sym] = deep_symbolize_keys(child)
        end
      when Array
        value.map { |child| deep_symbolize_keys(child) }
      else
        value
      end
    end
  end
end
