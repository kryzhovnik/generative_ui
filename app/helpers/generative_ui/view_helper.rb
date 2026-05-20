# frozen_string_literal: true

module GenerativeUI
  module ViewHelper
    def render_generative_ui(arguments, catalog: :default, renderer: nil)
      renderer ||= GenerativeUI.configuration.default_renderer
      GenerativeUI.render(arguments, catalog:, renderer:, view_context: self)
    end
  end
end
