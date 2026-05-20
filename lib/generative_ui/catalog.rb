# frozen_string_literal: true

module GenerativeUI
  class Catalog
    class InvalidCatalogError < ArgumentError; end

    REF_DEFS = {
      ComponentId: {
        type: 'string',
        description: 'Reference to another component id in this UI tree.'
      },
      ComponentIdList: {
        type: 'array',
        description: 'Ordered list of referenced component ids.',
        items: { "$ref": '#/$defs/ComponentId' }
      }
    }.freeze

    attr_reader :definitions

    class << self
      def component(name, &block)
        definition = ComponentDefinition.build(name, &block)

        if component_definitions.any? { |existing| existing.component == definition.component }
          warn "GenerativeUI: component #{definition.component.inspect} was already declared; replacing previous declaration"
          component_definitions.delete_if { |existing| existing.component == definition.component }
        end

        component_definitions << definition
      end

      def present_with(adapter, target = nil, &block)
        raise ArgumentError, 'present_with at catalog scope requires a block' unless block
        raise ArgumentError, 'present_with at catalog scope does not take a positional target' unless target.nil?

        default_targets[adapter.to_sym] = block
      end

      def component_definitions
        @component_definitions ||= []
      end

      def default_targets
        @default_targets ||= {}
      end
    end

    def self.coerce(value)
      case value
      when Catalog
        value
      when Class
        raise ArgumentError, "expected Catalog subclass, got #{value}" unless value <= Catalog

        value.new
      when Symbol, String
        name = value.to_sym
        configured = GenerativeUI.configuration.catalog(name)
        return instantiate(configured) if configured

        if name == :default
          raise ArgumentError,
                'Default generative UI catalog is not configured. Configure ' \
                '`config.catalog :default, "ApplicationGenerativeCatalog"` in an initializer.'
        end

        raise ArgumentError, "Unknown generative UI catalog: #{name.inspect}"
      else
        raise ArgumentError, 'expected Catalog, catalog class, or catalog name'
      end
    end

    def self.instantiate(value)
      case value
      when Catalog then value
      when Class then value.new
      when String then value.constantize.new
      else
        raise ArgumentError, "cannot instantiate catalog from #{value.inspect}"
      end
    end

    def initialize
      @definitions = self.class.component_definitions.dup
      validate!
    end

    def names
      definitions.map(&:component).sort
    end

    def empty?
      definitions.empty?
    end

    def fetch(component)
      definitions.find { |definition| definition.component == component.to_s }
    end

    def to_prompt_entries
      definitions.sort_by(&:component).map do |definition|
        schema = definition.attributes_json_schema
        required = Array(schema[:required] || schema['required']).map(&:to_s)
        properties = schema[:properties] || schema['properties'] || {}

        props = properties.flat_map do |name, property_schema|
          prompt_properties(name.to_s, property_schema).map { |prop| [name.to_s, prop] }
        end

        {
          component: definition.component,
          description: definition.description_text,
          required: props.select { |name, _| required.include?(name) }.map(&:last),
          optional: props.reject { |name, _| required.include?(name) }.map(&:last)
        }
      end
    end

    def to_prompt
      lines = ['Components:']

      to_prompt_entries.each do |entry|
        description = entry.fetch(:description)
        lines << (description.nil? ? "- #{entry.fetch(:component)}" : "- #{entry.fetch(:component)}: #{description}")

        if entry.fetch(:required).empty? && entry.fetch(:optional).empty?
          lines << '  attributes: none'
        else
          lines << "  required: #{entry.fetch(:required).join(', ')}" if entry.fetch(:required).any?
          lines << "  optional: #{entry.fetch(:optional).join(', ')}" if entry.fetch(:optional).any?
        end
      end

      lines.join("\n")
    end

    def component_schema(component_name)
      definition = fetch(component_name)
      raise ArgumentError, "Unknown generative component: #{component_name}" unless definition

      attributes_schema = definition.attributes_json_schema
      properties = attributes_schema.fetch(:properties, {}).transform_values do |schema|
        compile_provider_schema(schema)
      end
      required = Array(attributes_schema[:required]).map(&:to_sym)

      {
        type: 'object',
        "$defs": REF_DEFS,
        properties: {
          id: { type: 'string' },
          component: { const: definition.component },
          **properties
        },
        required: [:id, :component, *required],
        additionalProperties: attributes_schema.fetch(:additionalProperties, false)
      }
    end

    def tool_arguments_schema
      {
        type: 'object',
        "$defs": REF_DEFS,
        properties: {
          components: {
            type: 'array',
            items: { anyOf: names.map { |name| component_schema(name) } }
          }
        },
        required: [:components],
        additionalProperties: false
      }
    end

    COMPONENT_NAME_REGEX = /\A[A-Z][a-zA-Z0-9]*\z/
    PROPERTY_NAME_REGEX = /\A[a-z][a-zA-Z0-9_]*\z/
    ACRONYM_RUN_REGEX = /[A-Z]{2,}/
    UNDERSCORE_CAP_REGEX = /_[A-Z]/

    def target_for(definition, adapter)
      adapter = adapter.to_sym
      name = definition.respond_to?(:component) ? definition.component : definition.name

      definition.render_target_for(adapter) \
        || resolve_catalog_default(adapter, name) \
        || Conventions.fetch(adapter).call(name)
    end

    private

    def resolve_catalog_default(adapter, name)
      block = self.class.default_targets[adapter]
      return nil unless block

      block.call(name)
    end

    def validate!
      validate_component_names!
      validate_duplicate_components!
      validate_component_fields!
      validate_structural_refs!
      validate_only_targets!
    end

    def validate_component_names!
      definitions.each do |definition|
        next if definition.component.to_s.match?(COMPONENT_NAME_REGEX)

        raise InvalidCatalogError,
              "invalid component name #{definition.component.inspect}: " \
              'use PascalCase (`Text`, `TabPanel`, `URLInput`); ' \
              'must start with uppercase, ASCII alphanumeric only'
      end
    end

    def validate_duplicate_components!
      duplicates = definitions.group_by(&:component).select { |_name, entries| entries.size > 1 }.keys
      return if duplicates.empty?

      raise InvalidCatalogError, "duplicate component: #{duplicates.first}"
    end

    def validate_only_targets!
      available = names

      definitions.each do |definition|
        definition.structural_refs.each do |ref|
          Array(ref.only).each do |target|
            next if available.include?(target)

            path = ref.path.reject { |segment| segment == :* }.join('.')
            raise InvalidCatalogError, "#{definition.component}.#{path} only references missing component #{target}"
          end
        end
      end
    end

    def validate_component_fields!
      definitions.each do |definition|
        raw_schema = definition.attributes_definition&.schema_class&.new&.to_json_schema&.fetch(:schema)
        next unless raw_schema

        validate_schema_fields!(definition, raw_schema)
      end
    end

    def valid_property_name?(name)
      s = name.to_s
      s.match?(PROPERTY_NAME_REGEX) &&
        !s.match?(ACRONYM_RUN_REGEX) &&
        !s.match?(UNDERSCORE_CAP_REGEX)
    end

    def validate_schema_fields!(definition, schema, path = [])
      properties = schema[:properties] || schema['properties'] || {}

      properties.each_key do |name|
        next if valid_property_name?(name)

        field = (path + [name.to_s]).join('.')
        raise InvalidCatalogError,
              "#{definition.component}.#{field} uses unsupported name '#{name}': " \
              'use snake_case (`tab_items`) or lowerCamelCase (`tabItems`); ' \
              'no leading uppercase, no consecutive uppercase letters, ' \
              'no underscore followed by uppercase'
      end

      camelized = properties.keys.map { |name| name.to_s.camelize(:lower) }

      if path.empty? && (reserved = camelized.find { |name| %w[id component].include?(name) })
        field = (path + [reserved]).join('.')
        raise InvalidCatalogError, "#{definition.component}.#{field} uses reserved field #{reserved}"
      end

      if (duplicate = camelized.group_by(&:itself).find { |_name, names| names.size > 1 }&.first)
        field = (path + [duplicate]).join('.')
        raise InvalidCatalogError, "#{definition.component} has duplicate field #{field}"
      end

      properties.each do |name, child|
        camelized_name = name.to_s.camelize(:lower)
        validate_schema_fields!(definition, child, path + [camelized_name]) if child.is_a?(Hash)

        items = child[:items] || child['items'] if child.is_a?(Hash)
        validate_schema_fields!(definition, items, path + [camelized_name, '*']) if items.is_a?(Hash)
      end
    end

    def validate_structural_refs!
      definitions.each do |definition|
        definition.structural_refs.each do |ref|
          path = ref.path.reject { |segment| segment == :* }.join('.')

          raise InvalidCatalogError, "#{definition.component}.#{path} only must not be empty" if ref.only == []

          if ref.cardinality == :many && ref.min_items && ref.max_items && ref.min_items > ref.max_items
            raise InvalidCatalogError, "#{definition.component}.#{path} min_items must be <= max_items"
          end
        end
      end
    end

    def compile_provider_schema(value)
      case value
      when Hash
        if (metadata = value[Attributes::METADATA_KEY])
          return compile_structural_ref(value, metadata)
        end

        value.each_with_object({}) do |(key, child), sanitized|
          next if key == Attributes::METADATA_KEY

          sanitized[key] = compile_provider_schema(child)
        end
      when Array
        value.map { |child| compile_provider_schema(child) }
      else
        value
      end
    end

    def compile_structural_ref(schema, metadata)
      ref =
        if metadata.fetch(:cardinality) == :many
          '#/$defs/ComponentIdList'
        else
          '#/$defs/ComponentId'
        end

      compiled = {
        allOf: [{ "$ref": ref }],
        description: schema[:description] || schema['description'] || default_ref_description(metadata)
      }

      %i[minItems maxItems].each do |key|
        value = schema[key] || schema[key.to_s]
        compiled[key] = value unless value.nil?
      end

      compiled
    end

    def default_ref_description(metadata)
      allowed = Array(metadata[:only])

      if metadata.fetch(:cardinality) == :many
        return 'References to child components.' if allowed.empty?

        "References to #{format_allowed_components(allowed)} components."
      else
        return 'Reference to another component.' if allowed.empty?

        "Reference to a #{format_allowed_components(allowed)} component."
      end
    end

    def format_allowed_components(allowed)
      return allowed.first if allowed.one?

      [allowed[0...-1].join(', '), allowed.last].reject(&:blank?).join(' or ')
    end

    def prompt_properties(path, schema)
      schema = schema.transform_keys(&:to_sym)
      structural_ref = schema[Attributes::METADATA_KEY]

      return [format_prompt_property(path, schema)] if structural_ref

      properties = schema[:properties] || {}
      items = schema[:items]
      lines = [format_prompt_property(path, schema)]

      if schema[:type] == 'array' && items
        item_properties = items[:properties] || items['properties'] || {}
        item_properties.each do |name, child|
          lines.concat(prompt_properties("#{path}[].#{name}", child))
        end
      elsif schema[:type] == 'object'
        properties.each do |name, child|
          lines.concat(prompt_properties("#{path}.#{name}", child))
        end
      end

      lines
    end

    def format_prompt_property(name, schema)
      schema = schema.transform_keys(&:to_sym)
      structural_ref = schema[Attributes::METADATA_KEY]
      type =
        if structural_ref
          allowed = Array(structural_ref[:only]).presence&.join('|')
          if structural_ref[:cardinality] == :many
            allowed ? "components[#{allowed}][]" : 'components[]'
          else
            allowed ? "component[#{allowed}]" : 'component'
          end
        elsif schema[:type] == 'array'
          item_type = schema.dig(:items, :type) || schema.dig(:items, 'type')
          item_type == 'object' ? 'array<object>' : 'array'
        elsif (variants = schema[:anyOf] || schema[:oneOf])
          variants.map { |variant| prompt_schema_type(variant) }.compact.join('|')
        else
          schema[:type]
        end

      parts = ["#{name}:#{type}"]
      parts << "enum[#{schema[:enum].join(',')}]" if schema[:enum]
      parts.join(' ')
    end

    def prompt_schema_type(schema)
      schema = schema.transform_keys(&:to_sym)
      schema[:type]
    end
  end
end
