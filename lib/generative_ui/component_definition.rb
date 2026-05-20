# frozen_string_literal: true

require 'ruby_llm/schema'

module GenerativeUI
  class ComponentDefinition
    attr_reader :name, :description_text, :attributes_definition

    def self.build(name, &block)
      definition = new(name)
      definition.instance_eval(&block) if block
      definition
    end

    def initialize(name)
      @name = name.to_s
      @description_text = nil
      @attributes_definition = nil
      @render_targets = {}
    end

    def component
      @name
    end

    def desc(value)
      @description_text = value.to_s
    end
    alias description desc

    def attributes(&block)
      return @attributes_definition unless block
      raise ArgumentError, "attributes already defined for #{@name}" if @attributes_definition

      @attributes_definition = Attributes.build(&block)
    end

    def present_with(adapter, target)
      adapter = adapter.to_sym
      if @render_targets.key?(adapter)
        raise ArgumentError, "#{@name}: adapter :#{adapter} already declared"
      end

      @render_targets[adapter] = target
    end

    def render_target_for(adapter)
      @render_targets[adapter.to_sym]
    end

    def structural_refs
      @attributes_definition&.structural_refs || []
    end

    def attributes_json_schema
      return empty_attributes_schema if @attributes_definition.nil?

      @attributes_definition.json_schema
    end

    private

    def empty_attributes_schema
      {
        type: 'object',
        properties: {},
        required: [],
        additionalProperties: false,
        strict: true
      }
    end
  end
end
