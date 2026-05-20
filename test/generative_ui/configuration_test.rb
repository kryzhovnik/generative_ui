# frozen_string_literal: true

require 'test_helper'

class ConfigurationTest < Minitest::Test
  def setup
    GenerativeUI.reset_configuration!
    ui_catalog = Class.new(GenerativeUI::Catalog) do
      component 'Text' do
        attributes { string :text }
      end
    end
    GenerativeUI.configure { |c| c.catalog :ui, ui_catalog }
  end

  def teardown
    GenerativeUI.reset_configuration!
  end

  def test_uses_registered_renderer
    custom_renderer = Object.new

    GenerativeUI.configure do |config|
      config.register_renderer(:phlex) { |_view_context| custom_renderer }
    end

    assert_same custom_renderer, GenerativeUI.renderer_for(Object.new, renderer: :phlex)
  end

  def test_render_accepts_renderer_symbol
    result = GenerativeUI.render(
      { 'components' => [{ 'id' => 'root', 'component' => 'Text', 'text' => 'Hello' }] },
      catalog: :ui,
      renderer: :json
    )

    assert_equal(
      {
        'component' => 'Text',
        'props' => { 'text' => 'Hello' }
      },
      result
    )
  end

  def test_render_accepts_renderer_instance
    renderer = GenerativeUI::Renderers::Json.new(mode: :flat)

    result = GenerativeUI.render(
      { 'components' => [{ 'id' => 'root', 'component' => 'Text', 'text' => 'Hello' }] },
      catalog: :ui,
      renderer:
    )

    assert_equal(
      {
        'components' => [{ 'id' => 'root', 'component' => 'Text', 'text' => 'Hello' }]
      },
      result
    )
  end

  def test_render_raises_when_catalog_is_empty
    assert_raises(ArgumentError) do
      GenerativeUI.render(
        { 'components' => [] },
        catalog: Class.new(GenerativeUI::Catalog).new,
        renderer: :json
      )
    end
  end

  def test_configure_registers_named_catalog
    support_catalog = Class.new(GenerativeUI::Catalog) do
      component 'SupportText' do
        attributes { string :text }
      end
    end

    GenerativeUI.configure do |config|
      config.catalog :support, support_catalog
    end

    catalog = GenerativeUI::Catalog.coerce(:support)

    assert_equal ['SupportText'], catalog.names
  end

  def test_coerce_accepts_catalog_subclass
    klass = Class.new(GenerativeUI::Catalog) do
      component('Inline') {}
    end

    catalog = GenerativeUI::Catalog.coerce(klass)

    assert_equal ['Inline'], catalog.names
  end

  def test_named_catalog_resolves_lazily_to_survive_class_reload
    Object.const_set(:ReloadableSupportCatalog, Class.new(GenerativeUI::Catalog) do
      component('OldName') { attributes { string :text } }
    end)

    GenerativeUI.configure { |c| c.catalog :reloadable, ReloadableSupportCatalog }

    Object.send(:remove_const, :ReloadableSupportCatalog)
    Object.const_set(:ReloadableSupportCatalog, Class.new(GenerativeUI::Catalog) do
      component('NewName') { attributes { string :text } }
    end)

    assert_equal ['NewName'], GenerativeUI::Catalog.coerce(:reloadable).names
  ensure
    Object.send(:remove_const, :ReloadableSupportCatalog) if Object.const_defined?(:ReloadableSupportCatalog)
  end
end
