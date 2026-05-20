# frozen_string_literal: true

require_relative "lib/generative_ui/version"

Gem::Specification.new do |spec|
  spec.name          = "generative_ui"
  spec.version       = GenerativeUI::VERSION
  spec.authors       = [ "Andrey Samsonov" ]
  spec.email         = [ "me@samsonov.io" ]

  spec.summary       = "Catalog-driven generative UI for RubyLLM and Rails"
  spec.description   = "Define a safe component catalog, expose it as a RubyLLM tool schema, validate model-generated component trees, and render them with Rails partials, ViewComponent, or JSON."
  spec.homepage      = "https://github.com/kryzhovnik/generative_ui"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir[
    "lib/**/*",
    "app/**/*",
    "README.md",
    "LICENSE*",
    "generative_ui.gemspec"
  ]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "ruby_llm",      "~> 1.15"
  spec.add_dependency "json_schemer",  "~> 2.5"
end
