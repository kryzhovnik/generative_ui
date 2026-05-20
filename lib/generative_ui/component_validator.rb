# frozen_string_literal: true

require 'json_schemer'

module GenerativeUI
  class ComponentValidator
    Result = Data.define(:valid, :errors) do
      alias_method :valid?, :valid
    end

    def self.call(component, catalog:)
      new(component, catalog).call
    end

    def initialize(component, catalog)
      @component = component
      @catalog = catalog
    end

    def call
      unless component.name.is_a?(String) && component.name.present?
        return invalid(['component must be a non-empty string'])
      end
      return invalid(["unknown component: #{component.name}"]) unless catalog.fetch(component.name)

      errors = JSONSchemer.schema(schema).validate(component.to_h).flat_map { |error| format_error(error) }
      Result.new(valid: errors.empty?, errors:)
    end

    private

    attr_reader :component, :catalog

    def schema
      JSON.parse(catalog.component_schema(component.name).to_json)
    end

    def invalid(errors)
      Result.new(valid: false, errors:)
    end

    def format_error(error)
      pointer = error.fetch('data_pointer', '')
      property = pointer.delete_prefix('/').presence
      type = error.fetch('type', 'invalid')

      if type == 'required'
        missing = error.dig('details', 'missing_keys') || []
        missing.map { |key| "#{[property, key].compact.join('.')} required" }
      elsif type == 'enum'
        expected = error.fetch('schema', {}).fetch('enum', [])
        ["#{property || 'component'} expected one of #{expected.inspect}, got #{error.fetch('data').inspect}"]
      elsif %w[string number integer boolean array object].include?(type)
        ["#{property || 'component'} expected #{type}, got #{value_type(error.fetch('data', nil))}"]
      elsif type == 'schema' && error['schema'] == false
        ["#{property || 'component'} is not allowed"]
      else
        ["#{property || 'component'} #{type}"]
      end
    end

    def value_type(value)
      case value
      when String then 'string'
      when Integer then 'integer'
      when Numeric then 'number'
      when TrueClass, FalseClass then 'boolean'
      when Array then 'array'
      when Hash
        'object'
      when NilClass
        'null'
      else
        value.class.name
      end
    end
  end
end
