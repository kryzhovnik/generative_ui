# frozen_string_literal: true

require 'rails/engine'

module GenerativeUI
  class Engine < ::Rails::Engine
    initializer 'generative_ui.active_support_inflections', before: :load_config_initializers do
      ActiveSupport::Inflector.inflections(:en) do |inflect|
        inflect.acronym 'UI'
      end
    end

    initializer 'generative_ui.inflections', before: :set_autoload_paths do
      next unless defined?(Rails.autoloaders) && Rails.autoloaders.zeitwerk_enabled?

      Rails.autoloaders.main.inflector.inflect(
        'generative_ui' => 'GenerativeUI'
      )
    end

    initializer 'generative_ui.view_helper' do
      ActiveSupport.on_load(:action_view) do
        include GenerativeUI::ViewHelper
      end
    end
  end
end
