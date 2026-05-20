# frozen_string_literal: true

require 'test_helper'

class ValidatorTest < Minitest::Test
  ComponentSet = GenerativeUI::ComponentSet
  Validator = GenerativeUI::ComponentTreeValidator

  def ui_catalog
    @ui_catalog ||= Class.new(GenerativeUI::Catalog) do
      component 'Text' do
        attributes { string :text }
      end
      component 'Button' do
        attributes do
          one_component :label, only: 'Text'
          string :action
        end
      end
      component 'Column' do
        attributes { many_components :children }
      end
      component 'Tabs' do
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

  def demo_catalog
    @demo_catalog ||= Class.new(GenerativeUI::Catalog) do
      component 'Weather' do
        attributes do
          string :location
          number :temperature
          string :unit, enum: %w[c f], required: false
        end
      end
      component 'Row' do
      end
    end.new
  end

  def validate_components(components)
    Validator.call(ComponentSet.from_args(components), catalog: ui_catalog)
  end

  def assert_error_at(result, path, *tokens)
    refute result.valid?, 'expected validation to fail'
    assert result.errors.key?(path), "expected errors keyed at #{path.inspect}, got #{result.errors.keys.inspect}"
    message = result.errors.fetch(path).join("\n")
    tokens.each do |token|
      assert_includes message, token, "expected error at #{path.inspect} to mention #{token.inspect}"
    end
  end

  def test_accepts_a_valid_rooted_component_tree
    result = validate_components([
                                   { 'id' => 'root', 'component' => 'Column', 'children' => ['text-1'] },
                                   { 'id' => 'text-1', 'component' => 'Text', 'text' => 'Hello' }
                                 ])

    assert result.valid?, result.errors.inspect
  end

  def test_rejects_missing_root
    result = validate_components([
                                   { 'id' => 'text-1', 'component' => 'Text', 'text' => 'Hello' }
                                 ])

    assert_error_at result, '_tree', 'root'
  end

  def test_rejects_dangling_reference_at_parent_path
    result = validate_components([
                                   { 'id' => 'root', 'component' => 'Button', 'label' => 'ghost', 'action' => 'go' }
                                 ])

    assert_error_at result, 'root.label', 'ghost'
  end

  def test_rejects_only_mismatch_at_parent_field_path
    result = validate_components([
                                   { 'id' => 'root', 'component' => 'Button', 'label' => 'button-2', 'action' => 'go' },
                                   { 'id' => 'button-2', 'component' => 'Button', 'label' => 'text-1',
                                     'action' => 'go' },
                                   { 'id' => 'text-1', 'component' => 'Text', 'text' => 'Hello' }
                                 ])

    assert_error_at result, 'root.label', 'Text', 'Button'
  end

  def test_rejects_shared_child
    result = validate_components([
                                   { 'id' => 'root', 'component' => 'Column', 'children' => %w[button-1 button-2] },
                                   { 'id' => 'button-1', 'component' => 'Button', 'label' => 'text-1',
                                     'action' => 'one' },
                                   { 'id' => 'button-2', 'component' => 'Button', 'label' => 'text-1',
                                     'action' => 'two' },
                                   { 'id' => 'text-1', 'component' => 'Text', 'text' => 'Shared' }
                                 ])

    assert_error_at result, '_tree', 'text-1', 'button-1', 'button-2'
  end

  def test_rejects_orphan_components
    result = validate_components([
                                   { 'id' => 'root', 'component' => 'Text', 'text' => 'Hello' },
                                   { 'id' => 'orphan', 'component' => 'Text', 'text' => 'Lost' }
                                 ])

    assert_error_at result, '_tree', 'orphan'
  end

  def test_rejects_cycles
    result = validate_components([
                                   { 'id' => 'root', 'component' => 'Column', 'children' => ['column-2'] },
                                   { 'id' => 'column-2', 'component' => 'Column', 'children' => ['root'] }
                                 ])

    assert_error_at result, '_tree', 'root', 'column-2'
  end

  def test_resolves_nested_structural_refs
    result = validate_components([
                                   {
                                     'id' => 'root',
                                     'component' => 'Tabs',
                                     'tabItems' => [
                                       { 'title' => 'General', 'content' => 'text-1' }
                                     ]
                                   },
                                   { 'id' => 'text-1', 'component' => 'Text', 'text' => 'Panel' }
                                 ])

    assert result.valid?, result.errors.inspect
  end

  def test_rejects_duplicate_ids
    result = validate_components([
                                   { 'id' => 'root', 'component' => 'Text', 'text' => 'One' },
                                   { 'id' => 'root', 'component' => 'Text', 'text' => 'Two' }
                                 ])

    assert_error_at result, '_tree', 'root'
  end

  def test_rejects_invalid_component_attributes
    result = validate_components([
                                   { 'id' => 'root', 'component' => 'Text' }
                                 ])

    assert_error_at result, 'root', 'text'
  end

  def test_component_attribute_errors_identify_each_offending_field
    result = Validator.call(
      ComponentSet.from_args([
                               { 'id' => 'root', 'component' => 'Weather', 'location' => 123, 'temperature' => 'hot',
                                 'unit' => 'k' }
                             ]),
      catalog: demo_catalog
    )

    assert_error_at result, 'root', 'location', 'temperature', 'unit'
  end

  def test_accepts_additional_component_attributes_when_schema_allows_them
    catalog = Class.new(GenerativeUI::Catalog) do
      component 'OpenComponent' do
        attributes do
          additional_properties true
        end
      end
    end.new

    result = Validator.call(
      ComponentSet.from_args([
                               { 'id' => 'root', 'component' => 'OpenComponent', 'customValue' => 'ok' }
                             ]),
      catalog:
    )

    assert result.valid?, result.errors.inspect
  end

  def test_rejects_component_sets_over_the_component_limit
    components = [{ 'id' => 'root', 'component' => 'Text', 'text' => 'root' }]
    500.times do |i|
      components << { 'id' => "text-#{i}", 'component' => 'Text', 'text' => 'x' }
    end

    result = validate_components(components)

    assert_error_at result, '_tree', Validator::MAX_COMPONENTS.to_s
  end

  def test_rejects_trees_over_the_depth_limit
    components = []
    65.times do |i|
      id = i.zero? ? 'root' : "column-#{i}"
      child_id = i == 64 ? nil : "column-#{i + 1}"
      components << { 'id' => id, 'component' => 'Column', 'children' => child_id ? [child_id] : [] }
    end

    result = validate_components(components)

    assert_error_at result, '_tree', Validator::MAX_DEPTH.to_s
  end

  def test_rejects_component_sets_over_the_reference_limit
    result = validate_components([
                                   { 'id' => 'root', 'component' => 'Column',
                                     'children' => Array.new(2_001, 'text-1') },
                                   { 'id' => 'text-1', 'component' => 'Text', 'text' => 'x' }
                                 ])

    assert_error_at result, '_tree', Validator::MAX_REFS.to_s
  end
end
