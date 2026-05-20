# GenerativeUI

GenerativeUI lets RubyLLM apps render model-generated UI from a declared component catalog. The wire shape is inspired by A2UI: the model emits a validated component tree, and your app renders it with Rails partials, ViewComponent, JSON, or a custom renderer.

> Disclaimer: GenerativeUI is currently experimental and under active development. Its APIs, behavior, and integration patterns may change without notice, and it is not recommended for production use yet.

## Installation

```ruby
# Gemfile
gem "generative_ui"
```

## Quick start

Create `app/models/application_generative_catalog.rb`:

```ruby
class ApplicationGenerativeCatalog < GenerativeUI::Catalog
  component "Text" do
    desc "Render plain text."
    attributes { string :text }
  end

  component "Card" do
    desc "Group a title with generated body content."
    attributes do
      one_component :title, only: "Text"
      many_components :children, only: "Text"
    end
  end
end
```

Component attributes use `RubyLLM::Schema`. Structural refs use `one_component` for one child id and `many_components` for ordered child ids.

Register the default catalog explicitly:

```ruby
# config/initializers/generative_ui.rb
GenerativeUI.configure do |config|
  config.catalog :default, "ApplicationGenerativeCatalog"
end
```

Use a string in the initializer so Rails can autoload/reload the catalog class normally.

The default `:partial` renderer maps component names to partials. For this quick start, create the two partials used by the catalog above:

```erb
<%# app/views/generative_ui/_card.html.erb %>
<%# locals: (title:, children:) %>
<section style="border:2px solid #7c3aed;border-radius:16px;padding:16px;background:#faf5ff">
  <header style="font-size:22px;font-weight:700;color:#5b21b6"><%= title %></header>
  <% children.each do |child| %>
    <div style="margin-top:10px"><%= child %></div>
  <% end %>
</section>
```

```erb
<%# app/views/generative_ui/_text.html.erb %>
<%# locals: (text:) %>
<p style="margin:0;color:#111827;line-height:1.45"><%= text %></p>
```

Give a RubyLLM Rails chat a catalog-bound generate-UI tool. This assumes RubyLLM's Rails chat UI is installed:

```bash
bin/rails generate ruby_llm:install
bin/rails db:migrate
bin/rails generate ruby_llm:chat_ui
```

```ruby
tool = GenerativeUI::Tool.new

chat = Chat.create!
chat.with_instructions(<<~PROMPT)
  Tool guidance:
  - Use generate_ui for responses that should be rendered as UI from the available components.
  - IMPORTANT: after calling generate_ui, do not add a final text answer.
    The tool call itself is the user-visible UI response.
PROMPT
chat.with_tool(tool)

chat.ask("What programming language was designed to make developers happy and also turned out to be especially token-efficient for LLMs? Name its iconic web framework too, and present the answer as a titled card with one short explanation.")
```

`GenerativeUI::Tool.new` and `render_generative_ui` use the configured `:default` catalog unless you pass `catalog:`.

The `Tool guidance` section tells the model **when** to use the tool and that the tool call is the user-visible answer. The tool description itself tells the model **how** to construct valid arguments from the selected catalog.

Render the chat transcript:

```erb
<%= render @chat.messages %>
```

The gem ships two Rails chat partials for RubyLLM's default message views:

```text
app/views/messages/tool_calls/_generate_ui.html.erb
app/views/messages/tool_results/_generate_ui.html.erb
```

The shipped tool-call partial renders valid `generate_ui` calls. The tool-result partial is empty so validation status payloads stay out of the transcript.

The partial hides only `InvalidComponentTreeError`; configuration and rendering errors still raise.

**Catalog identity in Rails.** Persisted tool-call arguments do not store catalog identity. If you use named catalogs, build the tool and render with the same catalog:

```ruby
tool = GenerativeUI::Tool.new(catalog: :support)
chat.with_tool(tool)
```

```erb
<%# app/views/messages/tool_calls/_generate_ui.html.erb %>
<% begin %>
  <%= render_generative_ui tool_call.arguments, catalog: :support %>
<% rescue GenerativeUI::InvalidComponentTreeError %>
<% end %>
```

If one transcript can contain UI calls from different catalogs, use a shared render catalog or route catalogs in your overridden partial.

Renderers receive materialized Ruby attributes: declared fields are `snake_case`, `one_component` refs become one rendered fragment, and `many_components` refs become arrays.

## How it works

The gem is built around the bundled [`GenerativeUI::Tool`](lib/generative_ui/tool.rb). It uses a tool call as the transport for the generated UI tree. The call arguments contain the full payload: component names, declared attributes, and structural references between components.

```json
{
  "components": [
    { "id": "root", "component": "Card", "title": "title-1", "children": ["body-1"] },
    { "id": "title-1", "component": "Text", "text": "Ruby and Ruby on Rails" },
    { "id": "body-1", "component": "Text", "text": "Ruby was designed to make developers happy, and Rails became its iconic web framework." }
  ]
}
```

JSON Schema constrains each component's attributes. Runtime validation handles tree rules that schema cannot express: root, refs, cycles, reachability, and `only:` targets.

The tool returns only validation status, not rendered UI:

```json
{ "status": "ok" }
```

or:

```json
{ "status": "invalid", "errors": { "...": ["..."] } }
```

Each component declaration contributes one component to the catalog. It declares the component name, its model-facing description, its attribute schema, structural references to other components, and optional render-target metadata. The selected catalog is then compiled into both tool guidance and the provider-facing schema for `GenerativeUI::Tool`.

## Plain RubyLLM

Rails chat views are just one integration path. Plain RubyLLM uses the same catalog and tool; capture the `generate_ui` call and render its arguments yourself:

```ruby
tool = GenerativeUI::Tool.new(catalog: MyCatalog)
ui_call = nil

chat = RubyLLM.chat
  .with_instructions(<<~PROMPT)
    Tool guidance:
    - Use generate_ui for responses that should be rendered as UI from the available components.
    - IMPORTANT: after calling generate_ui, do not add a final text answer.
      The tool call itself is the user-visible UI response.
  PROMPT
  .with_tools(tool)
  .before_tool_call do |call|
    ui_call = call if call.name == "generate_ui"
  end

chat.ask("What programming language was designed to make developers happy and also turned out to be especially token-efficient for LLMs? Name its iconic web framework too, and present the answer as a titled card with one short explanation.")

GenerativeUI.render(ui_call.arguments, catalog: MyCatalog, renderer: :json)
# => {
#      "component" => "Card",
#      "props" => {
#        "title" => { "component" => "Text", "props" => { "text" => "Ruby and Ruby on Rails" } },
#        "children" => [
#          {
#            "component" => "Text",
#            "props" => {
#              "text" => "Ruby was created to make developers happy, and its concise style is often very token-efficient; its iconic framework is Ruby on Rails."
#            }
#          }
#        ]
#      }
#    }
```

`Renderers::Json` returns nested JSON by default; pass a renderer instance for options such as `mode: :flat`:

```ruby
renderer = GenerativeUI::Renderers::Json.new(mode: :flat)
GenerativeUI.render(ui_call.arguments, catalog: MyCatalog, renderer:)
```

## Named catalogs

```ruby
class SupportCatalog < GenerativeUI::Catalog
  component "TicketSummary" do
    attributes { string :summary }
  end
end

GenerativeUI.configure do |config|
  config.catalog :support, SupportCatalog
end
```

Pass the registered name where the default would go:

```ruby
GenerativeUI::Tool.new(catalog: :support)
render_generative_ui(args, catalog: :support)
```

Prefer `snake_case` in the Ruby DSL. Tool schemas and payloads use `camelCase`; unsafe acronym forms such as `imageURL` are rejected.

```ruby
attributes do
  array :tab_items do
    object do
      string :display_name
    end
  end
end
```

```json
{
  "tabItems": [
    { "displayName": "..." }
  ]
}
```

Structural references can also appear inside nested value schemas:

```ruby
attributes do
  array :tab_items do
    object do
      string :title
      one_component :content
    end
  end
end
```

**Subclassing.** Catalog declarations are per class; subclasses do not inherit components. Share declarations with a module if needed:

```ruby
module SharedComponents
  def self.included(base)
    base.component("Text") { attributes { string :text } }
  end
end

class ChatCatalog < GenerativeUI::Catalog
  include SharedComponents
  component("ChatBubble") { attributes { string :text } }
end
```

## `present_with` and the resolution chain

`present_with` binds a component to a render target at two scopes:

1. **Per-component override** — `present_with :adapter, target` inside a `component` block.
2. **Catalog-wide default** — `present_with :adapter do |name| … end` at the catalog class level. The block receives the component name and returns the target.
3. **Built-in `Conventions`** — gem fallback, used when neither scope above provides a target.

Built-in fallbacks:

| Adapter           | Fallback                                                                 |
|-------------------|--------------------------------------------------------------------------|
| `:partial`        | `"generative_ui/#{name.underscore}"` (e.g. `"generative_ui/card"`)       |
| `:view_component` | `"GenerativeUI::#{name.camelize}Component"` → `constantize` to the class |
| `:json`           | No target — JSON renderer serializes the component tree directly         |

Use `present_with` to redirect individual components or to set a catalog-wide convention that differs from the gem default:

```ruby
class ApplicationGenerativeCatalog < GenerativeUI::Catalog
  present_with :partial do |name|
    "components/#{name.underscore}"
  end

  component "Text" do
    desc "Render plain text."
    attributes { string :text }
    present_with :partial, "shared/widgets/text"
  end
end
```

Apps using ViewComponent declare bindings for the `:view_component` adapter instead — same DSL, different target type:

```ruby
component "Card" do
  attributes { ... }
  present_with :view_component, CardComponent
end
```

With the ViewComponent renderer, declared attributes and materialized refs arrive as keyword arguments:

```ruby
class GenerativeUI::CardComponent < ViewComponent::Base
  def initialize(title:, children:)
    @title = title
    @children = children
  end
end
```

## Validation model

Provider-facing schemas guide generation; runtime validation decides what the application accepts.

For a complete tool call, accepted components must form exactly one rooted tree:

- one component has `id: "root"`;
- ids are unique;
- every structural reference resolves;
- every component is reachable from `root`;
- cycles and shared children are rejected;
- `only:` constraints match the referenced component types.

`id` syntax is otherwise unconstrained in v1.

## Renderers

The gem ships with:

- `GenerativeUI::Renderers::Partial`
- `GenerativeUI::Renderers::ViewComponent`
- `GenerativeUI::Renderers::Json`

Register a custom renderer when your app uses another rendering system. The factory receives `view_context` and returns an object responding to `call(component_set)`:

```ruby
GenerativeUI.configure do |config|
  config.register_renderer(:phlex) do |view_context|
    PhlexRenderer.new(view_context:)
  end

  config.default_renderer = :phlex
end
```

Then choose it per call if needed:

```erb
<%= render_generative_ui tool_call.arguments, catalog: :support, renderer: :phlex %>
```

## License

MIT.
