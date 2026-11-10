# Authoring tessera components (Elixir side)

How to declare a web component with the `Noizu.Tessera.Component` DSL so that
`mix compile` generates the wire contract, the colocated JS skeleton wiring, and
(in Hologram apps) the server render + bridge glue. The normative wire contract
is `docs/CONTRACT.md`; this guide is the developer workflow.

## Minimal component

```elixir
defmodule MyApp.Components.PersonaCard do
  use Noizu.Tessera.Component,
    tag: "persona-card",
    js: "persona_card.mjs"

  attr :display_name, :string, required: true
  attr :disabled, :boolean, default: false

  prop :tag_list, :list, json: true, default: []
  prop :filters, :map, json: true, default: %{}

  event "persona-select", detail: %{persona_id: :string, click_count: :integer}
  event "persona-hover", detail: %{hovered: :boolean}

  slot "header"
  cy "persona-card-root"
end
```

- `tag:` — kebab-case custom-element name matching `^[a-z][a-z0-9]*(-[a-z0-9]+)+$`
  (enforced at compile time; must contain at least one hyphen per the platform
  custom-element requirement).
- `js:` — the colocated `.mjs` file next to this module's source file. It is
  treated as an `@external_resource`; the generated JS contract module is
  written next to it at compile time (only when its content changed).
- `cy:` — optional stable `data-cy` test hook rendered on the host element.

## The DSL

| Macro | Purpose | Wire shape |
|---|---|---|
| `attr :name, :type` | DOM attribute (snake_case atom) | rendered kebab-cased (`display-name=`), value camelCase prop `displayName` |
| `prop :name, :type, json: true` | JSON payload shipped through `tsr-props` | DOM property, camelCased key (`tagList`) |
| `event "name-detail"` | CustomEvent the element emits | binding prop `on_persona_select`, default action `persona_select`, `data-tsr-on="persona-select:action@target"` |
| `slot "name"` | declared slot (documented in manifest) | passthrough `<slot />` |
| `cy "name"` | `data-cy` value | rendered verbatim |

All DSL options must be compile-time literals (variables and module attributes
raise a `CompileError` pointing at the call site).

### Naming — the one rule that matters

Contract keys must survive the snake↔camel round-trip **byte-for-byte**: declare
`snake_case` atoms whose camelCase form (split on `_`, capitalize every segment
after the first) converts back to the identical snake_case name. `persona_id`
round-trips; `col_2_width` does not (`col2Width` collapses back to `col2_width`)
and is rejected at compile time with a rename suggestion. Non-snake names
(`Display_Name`, `foo__bar`, `_hidden`) are rejected outright. Do not reach for
`Macro.underscore/camelize` around contract keys — tessera's byte-exact rules
in CONTRACT.md §1 differ from them (`userID` → `user_i_d`, `col2_width` stays
`col2_width`).

### Types

`:string` · `:integer` · `:float` · `:boolean` · `:list` · `:map` · `:any`.
Event `detail:` maps use the same type set as values.

### Defaults

Declared `default:` values are JSON literals and appear in the generated
contract + manifest. At render time a prop/attr the caller did not pass falls
back to its declared default — **so a template-referenced name must either be
passed by every caller or declare a `default:`**, otherwise the template's
`@var` lookup raises `KeyError` at render (Hologram only injects defaults that
are declared). This bites json props referenced via `tsr-props` in particular:
give every json prop a `default:` (`[]`, `%{}`) unless you guarantee callers
always pass it.

## What `mix compile` generates

1. `__tessera_spec__/0` and `__tessera_manifest__/0` on the component module
   (compile-time validated spec + JSON-encodable manifest map).
2. The JS contract module `<snake_tag>.contract.generated.mjs` next to the
   `.mjs` — byte-deterministic output of CONTRACT.md §2. It is gitignored;
   regenerate by compiling. It is also an `@external_resource` of the module,
   so editing it by hand is futile (and next compile overwrites edits only when
   the spec actually changed — content-compared, no rebuild loops).
3. In Hologram apps (`hologram` dep present): the server render template
   (kebab attrs, `tsr-props` JSON for json props, `data-tsr-on` for bound
   events, `data-cy`), generated `init/2` + `init/3` that trigger the client
   registration call, and the absolute-path `js_import` binding to the `.mjs`
   (`register` export). Hologram treats `init/2` (client mount) and `init/3`
   (server) as separate callbacks — the compiler never derives one from the
   other, which is why tessera generates both.

**Override `__tessera_init__/2` (client) and/or `__tessera_init__/3` (server)
— never `init/2` / `init/3` — to seed state.** The generated inits run
`call(:register, [])` before delegating to the `__tessera_init__` hooks, so
overriding the hooks keeps registration alive; a user-defined `init` written
before the generated one would shadow it and kill registration.

**The top-level `register()` call at the end of your `.mjs` is load-bearing.**
Stateless SSR (no `cid` passed) never runs `init/3`; the element gets defined
only when the page bundle evaluates the `.mjs` and reaches that statement.
Removing it means components render server-side but never upgrade on the
client. `mix compile` emits a warning when a component's `.mjs` is missing the
call. See docs/CONTRACT.md §3/§5 for the render + bridge mechanics.

## Known compiler behaviours (not bugs)

- On Elixir 1.20+, every component that overrides `init/3` gets
  `warning: the following clause is redundant: def init(props, component, server)`
  from the type checker. This is inherent to Hologram's documented
  override-`init`-after-`use` pattern (`use Hologram.Component` itself defines
  a catch-all `init/3`), reproduces with a plain Hologram component, and is
  expected in tessera apps. It does not affect the library's own build.
- Stateless rendering (no `cid` passed) never runs `init/3` server-side —
  stateful initialization only happens for `cid`-bearing instances (and the
  client mount path calls `init/2`, which is why both are generated).

## Scaffolding

```sh
mix tessera.gen.component persona-card --module MyApp.Components.PersonaCard
```

writes `lib/my_app/components/persona_card.ex` (spec skeleton),
`persona_card.mjs` (element template — replace the body, keep the `register`
export), and `test/components/persona_card_test.mjs` (define-once smoke test).
The scaffolded `.mjs` imports only exports that exist in `@noizu/tessera-core`
(`TesseraElement`, `defineOnce`); use `emit` and `behaviors` from the same
package inside your element for events and shared behavior.

## Packages

```elixir
use Noizu.Tessera.Package, components: [MyApp.Components.PersonaCard]
```

generates `components/0` (component modules) and `manifest/0` (aggregated
manifest maps) on the host module — feed `mix tessera.manifest` with it to
emit `tessera-manifest.json` + `custom-elements.json` for tooling.
