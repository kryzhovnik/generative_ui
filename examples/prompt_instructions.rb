# frozen_string_literal: true

# Example tool guidance for GenerativeUI::Tool.
#
# Copy this snippet into your application and adapt the wording for
# your domain. It is not part of the gem's public API — the canonical
# tool description lives on GenerativeUI::Tool.
# The text below mirrors that description and adds top-level chat
# guidance ("don't add a final text answer"); copy and customise it
# when you need model-level `with_instructions` context that is
# separate from the tool's own schema description.
#
# Usage:
#
#   require_relative "examples/prompt_instructions"  # adjust to your project layout
#   instructions = GenerativeUIPromptInstructions.call(catalog: :default)
#   chat.with_instructions(instructions)

module GenerativeUIPromptInstructions
  module_function

  def call(catalog:)
    catalog = GenerativeUI::Catalog.coerce(catalog)

    <<~PROMPT.strip
      Use generate_ui for responses that should be rendered as UI.
      After calling generate_ui, do not add a final text answer.
      The tool call itself is the user-visible UI response.

      Tool argument format:
      - components is a flat array of component instances.
      - One component must have id="root".
      - Each component has id, component, and declared attributes.
      - component must be one of the component names below.
      - Attributes must match that component's required and optional attributes.
      - ComponentId fields reference one component id.
      - ComponentIdList fields reference ordered arrays of component ids.
      - The accepted payload must form one rooted tree.

      #{catalog.to_prompt}
    PROMPT
  end
end
