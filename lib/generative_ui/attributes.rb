# frozen_string_literal: true

module GenerativeUI
  class Attributes
    METADATA_KEY = :_generative_ui_structural_ref

    module StructuralDsl
      def one_component(name, description: nil, required: true, only: nil)
        add_property(
          name,
          {
            type: 'string',
            description: description,
            Attributes::METADATA_KEY => {
              cardinality: :one,
              only: Attributes.normalize_only(only)
            }
          }.compact,
          required: required
        )
      end

      def many_components(name, description: nil, required: true, only: nil, min_items: nil, max_items: nil)
        add_property(
          name,
          {
            type: 'array',
            items: { type: 'string' },
            description: description,
            minItems: min_items,
            maxItems: max_items,
            Attributes::METADATA_KEY => {
              cardinality: :many,
              only: Attributes.normalize_only(only)
            }
          }.compact,
          required: required
        )
      end
    end

    module LocalSchemaBuilders
      def object_schema(description: nil, of: nil, &block)
        return determine_object_reference(of, description) if of

        sub_schema = Class.new(self)
        result = sub_schema.class_eval(&block)

        if result.is_a?(Hash) && result['$ref'] && sub_schema.properties.empty?
          result.merge(description ? { description: description } : {})
        elsif schema_class?(result) && sub_schema.properties.empty?
          schema_class_to_inline_schema(result).merge(description ? { description: description } : {})
        else
          {
            type: 'object',
            properties: sub_schema.properties,
            required: sub_schema.required_properties,
            additionalProperties: sub_schema.additional_properties,
            description: description
          }.compact
        end
      end
    end

    class Schema < RubyLLM::Schema
      extend StructuralDsl
      extend LocalSchemaBuilders

      class << self
        def create(&block)
          Class.new(self).tap { |schema_class| schema_class.class_eval(&block) }
        end
      end
    end

    class << self
      def build(&block)
        schema_class = Schema.create(&block)
        new(schema_class)
      end

      def normalize_only(value)
        return nil if value.nil?

        Array(value).map(&:to_s)
      end
    end

    attr_reader :schema_class

    def initialize(schema_class)
      @schema_class = schema_class
    end

    def json_schema
      @json_schema ||= camelize_schema(schema_class.new.to_json_schema.fetch(:schema))
    end

    def structural_refs
      @structural_refs ||= extract_structural_refs(json_schema)
    end

    private

    def camelize_schema(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), transformed|
          transformed[key] = case key.to_sym
                             when :properties
                               child.each_with_object({}) do |(property, schema), properties|
                                 properties[camelize_name(property)] = camelize_schema(schema)
                               end
                             when :required
                               child.map { |name| camelize_name(name) }
                             else
                               camelize_schema(child)
                             end
        end
      when Array
        value.map { |child| camelize_schema(child) }
      else
        value
      end
    end

    def camelize_name(name)
      name.to_s.camelize(:lower).to_sym
    end

    def extract_structural_refs(schema)
      refs = []
      walk_schema(schema, [], refs)
      refs
    end

    def walk_schema(schema, path, refs)
      return unless schema.is_a?(Hash)

      if (metadata = schema[METADATA_KEY])
        refs << StructuralRef.new(
          path: path,
          cardinality: metadata.fetch(:cardinality),
          required: required_path?(path),
          only: metadata[:only],
          description: schema[:description] || schema['description'],
          min_items: schema[:minItems] || schema['minItems'],
          max_items: schema[:maxItems] || schema['maxItems']
        )
      end

      properties = schema[:properties] || schema['properties'] || {}
      properties.each do |name, child|
        walk_schema(child, path + [name.to_sym], refs)
      end

      items = schema[:items] || schema['items']
      walk_schema(items, path + [:*], refs) if items

      Array(schema[:oneOf] || schema['oneOf']).each { |child| walk_schema(child, path, refs) }
      Array(schema[:anyOf] || schema['anyOf']).each { |child| walk_schema(child, path, refs) }
    end

    def required_path?(path)
      current = json_schema

      path.each do |segment|
        if segment == :*
          current = current[:items] || current['items']
          next
        end

        required = current[:required] || current['required'] || []
        return false unless required.map(&:to_sym).include?(segment)

        current = (current[:properties] || current['properties']).fetch(segment)
      end

      true
    end
  end
end
