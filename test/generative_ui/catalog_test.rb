# frozen_string_literal: true

require 'test_helper'

class CatalogTest < Minitest::Test
  Catalog = GenerativeUI::Catalog

  # ---------------------------------------------------------------------------
  # Helpers — shared inline catalog shapes
  # ---------------------------------------------------------------------------

  def weather_catalog
    @weather_catalog ||= Class.new(Catalog) do
      component 'Weather' do
        desc 'Test fixture'
        attributes do
          string :location
          number :temperature
          string :unit, enum: %w[c f], required: false
        end
      end
    end.new
  end

  def ui_catalog
    @ui_catalog ||= Class.new(Catalog) do
      component 'Text' do
        desc 'Render text'
        attributes { string :text }
      end

      component 'Button' do
        desc 'Render a button'
        attributes do
          one_component :label, only: 'Text'
          string :action
        end
      end

      component 'Column' do
        desc 'Stack children'
        attributes { many_components :children }
      end

      component 'Tabs' do
        desc 'Render tabs'
        attributes do
          array :tab_items do
            object do
              string :title
              one_component :content, only: 'Text'
            end
          end
        end
      end
    end.new
  end

  def assert_raises_with_token(error_class, *tokens, &block)
    error = assert_raises(error_class, &block)
    tokens.each do |token|
      assert_includes error.message, token, "expected error to mention #{token.inspect}"
    end
    error
  end

  # ---------------------------------------------------------------------------
  # coerce / fetch
  # ---------------------------------------------------------------------------

  def test_coerce_accepts_catalog_instances
    catalog = weather_catalog

    assert_same catalog, Catalog.coerce(catalog)
  end

  def test_coerce_rejects_invalid_values
    assert_raises(ArgumentError) { Catalog.coerce(Object.new) }
  end

  def test_fetch_returns_nil_for_unknown_component
    assert_nil weather_catalog.fetch('NoSuchComponent')
  end

  def test_fetch_returns_definition_for_known_component
    defn = weather_catalog.fetch('Weather')

    assert_equal 'Weather', defn.component
  end

  # ---------------------------------------------------------------------------
  # to_prompt
  # ---------------------------------------------------------------------------

  def test_to_prompt_mentions_each_component_name_and_description
    prompt = ui_catalog.to_prompt

    assert_includes prompt, 'Text'
    assert_includes prompt, 'Render text'
    assert_includes prompt, 'Button'
    assert_includes prompt, 'Render a button'
    assert_includes prompt, 'Column'
    assert_includes prompt, 'Tabs'
  end

  def test_to_prompt_mentions_every_attribute_name
    prompt = weather_catalog.to_prompt

    assert_includes prompt, 'location'
    assert_includes prompt, 'temperature'
    assert_includes prompt, 'unit'
  end

  def test_to_prompt_does_not_leak_raw_json_schema
    prompt = ui_catalog.to_prompt

    refute_includes prompt, 'additionalProperties'
    refute_includes prompt, '"properties"'
    refute_includes prompt, '"$ref"'
  end

  def test_to_prompt_describes_nested_structural_refs
    prompt = ui_catalog.to_prompt

    assert_includes prompt, 'tabItems'
    assert_includes prompt, 'title'
    assert_includes prompt, 'content'
    assert_includes prompt, 'children'
  end

  def test_to_prompt_omits_trailing_colon_when_component_has_no_desc
    prompt = Class.new(Catalog) do
      component 'Undocumented' do
        attributes { string :text }
      end
    end.new.to_prompt

    refute_match(/^-\s*Undocumented:/, prompt, 'no trailing colon should follow a component with no description')
    assert_match(/Undocumented/, prompt)
  end

  def test_to_prompt_describes_union_types
    prompt = Class.new(Catalog) do
      component 'UnionValue' do
        attributes do
          any_of :value do
            string
            number
          end
        end
      end
    end.new.to_prompt

    value_line = prompt.lines.find { |line| line.include?('value') }
    refute_nil value_line, 'prompt should mention the value field'
    assert_includes value_line, 'string'
    assert_includes value_line, 'number'
  end

  # ---------------------------------------------------------------------------
  # component_schema
  # ---------------------------------------------------------------------------

  def test_component_schema_flattens_attributes_and_structural_refs
    schema = Class.new(Catalog) do
      component 'SchemaText' do
        attributes { string :text }
      end
      component 'SchemaButton' do
        attributes do
          one_component :label, only: 'SchemaText'
          string :action
        end
      end
    end.new.component_schema('SchemaButton')

    assert_equal 'SchemaButton', schema.dig(:properties, :component, :const)
    assert_equal '#/$defs/ComponentId', schema.dig(:properties, :label, :allOf, 0, :"$ref")
    assert_equal 'string', schema.dig(:properties, :action, :type)
    assert_equal %i[id component label action], schema.fetch(:required)
  end

  # ---------------------------------------------------------------------------
  # tool_arguments_schema
  # ---------------------------------------------------------------------------

  def test_tool_schema_uses_component_ref_defs
    schema = ui_catalog.tool_arguments_schema

    assert_equal 'string', schema.dig(:"$defs", :ComponentId, :type)
    assert_equal 'array', schema.dig(:"$defs", :ComponentIdList, :type)
    assert_equal '#/$defs/ComponentId', schema.dig(:"$defs", :ComponentIdList, :items, :"$ref")

    button = schema.dig(:properties, :components, :items, :anyOf).find do |entry|
      entry.dig(:properties, :component, :const) == 'Button'
    end
    assert_equal '#/$defs/ComponentId', button.dig(:properties, :label, :allOf, 0, :"$ref")
    assert_includes button.dig(:properties, :label, :description), 'Text'

    column = schema.dig(:properties, :components, :items, :anyOf).find do |entry|
      entry.dig(:properties, :component, :const) == 'Column'
    end
    assert_equal '#/$defs/ComponentIdList', column.dig(:properties, :children, :allOf, 0, :"$ref")
  end

  def test_nested_structural_refs_keep_component_ref_semantics
    schema = ui_catalog.component_schema('Tabs')

    content = schema.dig(:properties, :tabItems, :items, :properties, :content)
    assert_equal '#/$defs/ComponentId', content.dig(:allOf, 0, :"$ref")
    assert_includes content[:description], 'Text'
  end

  # ---------------------------------------------------------------------------
  # Validation — component name format
  # ---------------------------------------------------------------------------

  def test_rejects_non_pascal_case_component_names
    %w[text tab_panel Tab-Panel 2Tabs].each do |bad_name|
      assert_raises_with_token(Catalog::InvalidCatalogError, bad_name) do
        Class.new(Catalog) do
          component bad_name do
          end
        end.new
      end
    end
  end

  def test_accepts_pascal_case_with_consecutive_capitals
    catalog = Class.new(Catalog) do
      component 'URLInput' do
      end
    end.new

    assert_equal ['URLInput'], catalog.names
  end

  # ---------------------------------------------------------------------------
  # Validation — duplicate components
  # ---------------------------------------------------------------------------

  def test_redeclaring_component_replaces_previous_definition
    catalog = Class.new(Catalog) do
      component 'ReplaceableComponent' do
        desc 'First declaration'
        attributes { string :first_value }
      end

      component 'ReplaceableComponent' do
        desc 'Second declaration'
        attributes { string :second_value }
      end
    end.new

    assert_equal ['ReplaceableComponent'], catalog.names
    assert_equal 'Second declaration', catalog.fetch('ReplaceableComponent').description_text

    schema = catalog.component_schema('ReplaceableComponent')
    refute schema.fetch(:properties).key?(:firstValue)
    assert schema.fetch(:properties).key?(:secondValue)
  end

  # ---------------------------------------------------------------------------
  # Validation — structural-ref `only:` targets
  # ---------------------------------------------------------------------------

  def test_rejects_only_targets_missing_from_catalog
    assert_raises_with_token(Catalog::InvalidCatalogError, 'MissingTargetButton', 'label', 'MissingText') do
      Class.new(Catalog) do
        component 'MissingTargetButton' do
          attributes do
            one_component :label, only: 'MissingText'
          end
        end
      end.new
    end
  end

  def test_rejects_inline_catalog_only_targets_missing_from_catalog
    assert_raises_with_token(Catalog::InvalidCatalogError, 'BadButton', 'NoSuchText') do
      Class.new(Catalog) do
        component 'BadButton' do
          attributes { one_component :label, only: 'NoSuchText' }
        end
      end.new
    end
  end

  # ---------------------------------------------------------------------------
  # Validation — reserved / unsupported field names
  # ---------------------------------------------------------------------------

  def test_rejects_reserved_protocol_fields
    assert_raises_with_token(Catalog::InvalidCatalogError, 'ReservedField', 'id') do
      Class.new(Catalog) do
        component 'ReservedField' do
          attributes { string :id }
        end
      end.new
    end
  end

  def test_nested_value_objects_may_use_id_fields
    catalog = Class.new(Catalog) do
      component 'NestedValue' do
        attributes do
          array :items do
            object do
              string :id
            end
          end
        end
      end
    end.new

    assert catalog
  end

  def test_rejects_camelized_field_name_collisions
    assert_raises_with_token(Catalog::InvalidCatalogError, 'CollidingFields', 'tabItems') do
      Class.new(Catalog) do
        component 'CollidingFields' do
          attributes do
            string :tab_items
            string :tabItems
          end
        end
      end.new
    end
  end

  def test_catalog_rejects_all_caps_property_name
    assert_raises_with_token(Catalog::InvalidCatalogError, 'URL') do
      Class.new(Catalog) do
        component 'UrlComponent' do
          attributes { string :URL }
        end
      end.new
    end
  end

  def test_catalog_validates_nested_property_names
    assert_raises_with_token(Catalog::InvalidCatalogError, 'nested', 'URL') do
      Class.new(Catalog) do
        component 'NestedBad' do
          attributes do
            object :nested do
              string :URL
            end
          end
        end
      end.new
    end
  end

  # ---------------------------------------------------------------------------
  # Validation — structural-ref constraints
  # ---------------------------------------------------------------------------

  def test_rejects_empty_only_array
    assert_raises_with_token(Catalog::InvalidCatalogError, 'EmptyOnly', 'label') do
      Class.new(Catalog) do
        component 'EmptyOnly' do
          attributes { one_component :label, only: [] }
        end
      end.new
    end
  end

  def test_rejects_min_items_greater_than_max_items
    assert_raises_with_token(Catalog::InvalidCatalogError, 'BadRange', 'children') do
      Class.new(Catalog) do
        component 'BadRange' do
          attributes { many_components :children, min_items: 5, max_items: 2 }
        end
      end.new
    end
  end

  # ---------------------------------------------------------------------------
  # Class-level DSL
  # ---------------------------------------------------------------------------

  def test_class_level_component_dsl_builds_definitions
    catalog_class = Class.new(GenerativeUI::Catalog) do
      component 'InlineText' do
        desc 'Render inline text.'
        attributes { string :text }
      end
    end

    catalog = catalog_class.new

    assert_equal ['InlineText'], catalog.names
    schema = catalog.component_schema('InlineText')
    assert_equal 'InlineText', schema.dig(:properties, :component, :const)
    assert_equal 'string', schema.dig(:properties, :text, :type)
  end

  def test_target_for_resolves_per_component_then_catalog_default_then_conventions
    catalog_class = Class.new(GenerativeUI::Catalog) do
      present_with :partial do |name|
        "catalog_default/#{name.underscore}"
      end

      component 'PerComponent' do
        present_with :partial, 'custom/per_component'
      end

      component 'CatalogDefault' do
      end

      component 'Convention' do
      end
    end

    catalog = catalog_class.new

    assert_equal 'custom/per_component',
                 catalog.target_for(catalog.fetch('PerComponent'), :partial)
    assert_equal 'catalog_default/catalog_default',
                 catalog.target_for(catalog.fetch('CatalogDefault'), :partial)

    fresh_catalog = Class.new(GenerativeUI::Catalog) do
      component 'Convention' do
      end
    end.new

    convention_target = fresh_catalog.target_for(fresh_catalog.fetch('Convention'), :partial)
    assert_equal 'generative_ui/convention', convention_target
  end

  def test_catalog_subclass_inherits_default_targets_per_subclass
    parent_calls = 0
    parent = Class.new(GenerativeUI::Catalog) do
      present_with(:partial) do |name|
        parent_calls += 1
        "parent/#{name}"
      end
      component('X') {}
    end

    child = Class.new(GenerativeUI::Catalog) do
      component('Y') {}
    end

    refute_equal parent.default_targets.object_id, child.default_targets.object_id
    parent.new
    assert_equal({}, child.default_targets)
  end

  # ---------------------------------------------------------------------------
  # coerce — explicit :default catalog configuration
  # ---------------------------------------------------------------------------

  def test_default_catalog_uses_explicit_configuration
    Object.const_set(:ApplicationGenerativeCatalog, Class.new(GenerativeUI::Catalog) do
      component 'DefaultText' do
        attributes { string :text }
      end
    end)
    GenerativeUI.configure { |c| c.catalog :default, 'ApplicationGenerativeCatalog' }

    catalog = GenerativeUI::Catalog.coerce(:default)

    assert_equal ['DefaultText'], catalog.names
  ensure
    Object.send(:remove_const, :ApplicationGenerativeCatalog) if Object.const_defined?(:ApplicationGenerativeCatalog)
  end

  def test_missing_default_catalog_raises
    GenerativeUI.reset_configuration!
    error = assert_raises(ArgumentError) { GenerativeUI::Catalog.coerce(:default) }

    assert_includes error.message, 'Default generative UI catalog is not configured'
    assert_includes error.message, 'config.catalog :default'
  end
end
