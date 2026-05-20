# frozen_string_literal: true

require 'active_support'
require 'active_support/concern'
require 'active_support/core_ext'
require 'ruby_llm/schema'
require 'json'

require_relative 'generative_ui/version'
require_relative 'generative_ui/structural_ref'
require_relative 'generative_ui/attributes'
require_relative 'generative_ui/component_definition'
require_relative 'generative_ui/component'
require_relative 'generative_ui/component_set'
require_relative 'generative_ui/component_validator'
require_relative 'generative_ui/component_tree_validator'
require_relative 'generative_ui/invalid_component_tree_error'
require_relative 'generative_ui/tool'
require_relative 'generative_ui/conventions'
require_relative 'generative_ui/catalog'
require_relative 'generative_ui/renderer'
require_relative 'generative_ui/renderers/partial'
require_relative 'generative_ui/renderers/view_component'
require_relative 'generative_ui/renderers/json'
require_relative 'generative_ui/engine' if defined?(::Rails::Engine)

module GenerativeUI
  class Configuration
    attr_accessor :default_renderer
    attr_reader :renderers

    def initialize
      @renderers = {}
      @catalogs = {}
      @default_renderer = :partial

      register_renderer(:partial) do |view_context|
        GenerativeUI::Renderers::Partial.new(view_context: view_context)
      end

      register_renderer(:view_component) do |view_context|
        GenerativeUI::Renderers::ViewComponent.new(view_context: view_context)
      end

      register_renderer(:json) do |_view_context|
        GenerativeUI::Renderers::Json.new
      end
    end

    def register_renderer(name, &factory)
      renderers[name.to_sym] = factory
    end

    def catalog(name, catalog_class = nil)
      if catalog_class.nil?
        @catalogs[name.to_sym]
      else
        @catalogs[name.to_sym] = normalize_catalog_value(catalog_class)
      end
    end

    private

    def normalize_catalog_value(value)
      value.is_a?(Class) && value.name ? value.name : value
    end
  end

  class << self
    def configure
      yield configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def renderer_for(view_context, renderer: nil, catalog: nil)
      name = (renderer || configuration.default_renderer).to_sym
      factory = configuration.renderers[name]
      raise ArgumentError, "Unknown renderer: #{name}" unless factory

      factory.call(view_context).tap do |renderer|
        renderer.catalog = catalog if catalog && renderer.respond_to?(:catalog=)
      end
    end

    def render(arguments, renderer:, catalog: :default, view_context: nil)
      raise ArgumentError, 'arguments must be a Hash' unless arguments.is_a?(Hash)

      unknown = arguments.keys.map(&:to_s) - %w[components]
      raise InvalidComponentTreeError, { '_arguments' => ["unknown arguments: #{unknown.join(', ')}"] } if unknown.any?

      components = arguments['components'] || arguments[:components]
      raise InvalidComponentTreeError, { '_arguments' => ['components must be an array'] } unless components.is_a?(Array)

      catalog = Catalog.coerce(catalog)
      raise ArgumentError, 'generative UI catalog is empty' if catalog.empty?

      set = ComponentSet.from_args(components)
      validation = ComponentTreeValidator.call(set, catalog:)
      raise InvalidComponentTreeError, validation.errors unless validation.valid?

      resolve_renderer(renderer, view_context:, catalog:).call(set)
    end

    private

    def resolve_renderer(renderer, view_context:, catalog:)
      if renderer.is_a?(Symbol)
        renderer_for(view_context, renderer:, catalog:)
      else
        renderer.tap { |instance| instance.catalog = catalog if instance.respond_to?(:catalog=) }
      end
    end
  end
end
