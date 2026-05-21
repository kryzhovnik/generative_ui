# frozen_string_literal: true

require 'ruby_llm'

module GenerativeUI
  class Tool < RubyLLM::Tool
    attr_reader :catalog

    def initialize(catalog: :default)
      @catalog = Catalog.coerce(catalog)
      raise ArgumentError, 'generative UI catalog is empty' if @catalog.empty?
    end

    def name
      'generate_ui'
    end

    def description
      <<~TEXT.strip
        Render inline UI from the available component catalog.

        Call this tool at most once per assistant turn. After it returns
        {"status":"ok"}, the UI is shown to the user — do not call it again.

        Arguments:
        - components is a flat array of component instances.
        - Each component is an object: { "id": "...", "component": "<Name>", ...attributes }
          where "component" is the literal component name as a string.
        - One component must have id="root".
        - ComponentId fields reference one component id.
        - ComponentIdList fields reference ordered arrays of component ids.
        - The accepted payload must form one rooted tree.

        Example payload (component names below must be from the catalog;
        ids are arbitrary labels — suffix them with numbers so they are
        clearly distinct from component names):
        {
          "components": [
            { "id": "root",    "component": "<CatalogComponent>", ...attributes },
            { "id": "title-1", "component": "<CatalogComponent>", ...attributes },
            { "id": "body-1",  "component": "<CatalogComponent>", ...attributes }
          ]
        }

        #{catalog.to_prompt}
      TEXT
    end

    def params_schema
      @params_schema ||= JSON.parse(catalog.tool_arguments_schema.to_json)
    end

    def execute(**args)
      unknown = args.keys.map(&:to_s) - %w[components]
      return invalid_arguments("unknown arguments: #{unknown.join(', ')}") if unknown.any?

      components = args[:components]
      return invalid_arguments('components must be an array') unless components.is_a?(Array)

      set = ComponentSet.from_args(components)
      validation = ComponentTreeValidator.call(set, catalog:)

      if validation.valid?
        { status: 'ok' }.to_json
      else
        { status: 'invalid', errors: validation.errors }.to_json
      end
    end

    private

    def invalid_arguments(message)
      { status: 'invalid', errors: { '_arguments' => [message] } }.to_json
    end
  end
end
