# Tessera wire contract (v1)

The single interface between the three layers: the Elixir spec, the Hologram adapter and the JS core. Both implementation tracks build to this document. If you change it, bump `contract.version` and update both sides in the same PR.

Phase 0 evidence: hologram-start-app branch `spike/tessera-bridge` @ `c20f27f9`.

## 1. Naming rules

| Elixir (spec) | DOM / JS | Rule |
|---|---|---|
| `attr :display_name` | attribute `display-name` | snake → kebab |
| `prop :tag_list` | property `tagList` | snake → camel |
| `event "persona-select"` | CustomEvent type `persona-select` | kebab, verbatim, `[a-z][a-z0-9]*(-[a-z0-9]+)+` |
| binding prop `on_persona_select` | — | `"on_" <> snake(event)` |
| default action `:persona_select` | — | `snake(event)` |
| detail key `persona_id` | detail key `personaId` | the JS core emits camel; the bridge converts recursively to snake before dispatch |

Tag names follow the custom-element rule: lowercase and contain a hyphen. Validation happens at compile time.

## 2. Generated JS contract module

For each component the spec generates `<snake_tag>.contract.generated.mjs` next to the component's `.mjs`, with a default export:

```js
export default {
  version: 1,
  tag: "persona-card",
  attrs:  [{ name: "display-name", key: "displayName", type: "string", required: true, default: null }],
  props:  [{ name: "tagList", type: "list", json: true, default: [] }],
  events: [{ name: "persona-select", detail: { personaId: "string", clickCount: "integer" } }],
  slots:  ["default"],
  cy: "persona-card-root",
};
```

Types: `string | integer | float | boolean | list | map | any`.

## 3. Rendered DOM (adapter output)

```html
<persona-card
  display-name="Ada"                                         <!-- scalar attrs; booleans by presence/absence -->
  tsr-props='{"tagList":["a","b"]}'                          <!-- json: true props, camelCase keys; omitted if none -->
  data-tsr-on="persona-select:chose@page;persona-hover:hover@picker1"
  data-cy="persona-card-root"></persona-card>
```

`data-tsr-on` grammar: `entry (";" entry)*`, where `entry = event ":" action "@" target` and `target ∈ page | layout | <cid>`. A binding prop value of `:chose` means target `page`. A value of `{:chose, target: "layout"}` (or a cid string) sets the target explicitly. If an event has no binding, it gets no entry.

## 4. JS core runtime (`@noizu/tessera-core`)

- `defineOnce(tag, ctor)`: if `customElements.get(tag)` exists, warn once and return the existing ctor. Otherwise define it.
- `emit(el, name, detail)`: dispatches `new CustomEvent(name, {detail, bubbles: true, composed: true})`.
- `TesseraElement(Base, contract)`: a mixin over `HTMLElement` or `LitElement`. It observes the attrs in the contract plus `tsr-props`. It parses the `tsr-props` JSON and assigns each key as a property; bad JSON produces a warning, never a throw. It calls `requestUpdate()` when present. On `connectedCallback` it registers the contract's events with the bridge and runs `behaviors` for the tag.
- **Bridge.** A singleton at `globalThis[Symbol.for("tessera.bridge")]`, holding one capture-phase `document` listener per registered event name. When an event fires:
  1. Resolve the host element (`event.target` after retargeting).
  2. Parse its `data-tsr-on` and find the entry for `event.type`.
  3. Call `globalThis.Hologram.dispatchAction(action, target, snakeKeysDeep(event.detail ?? {}))`.

  If no entry matches, or `globalThis.Hologram` is absent, it does nothing, which is the plain-HTML/React case.
- `behaviors.add(tag, fn)`: `fn(el)` runs on each `connectedCallback`. It may return a cleanup function, which runs on disconnect.

## 5. Elixir ↔ JS import rules (Hologram 0.10.1, learned in the spike)

- `js_import` paths must be **absolute**: build them from the component module's `__DIR__`, never a relative path. Relative paths resolve against the *caller's* file.
- The JS export name must equal the binding name unless `as:` is given. Component modules export `register` (a no-arg function returning the ctor).
- Hologram only bundles a `js_import` if the page's call graph references it. The adapter therefore calls `register` through `Hologram.JS.call/2` inside a generated `init/3`.
- `import Hologram.JS, only: [...]` **replaces** any earlier `only:` import, so always restate `js_import: 1, js_import: 2` alongside `call: 2`.
- `~JS` sigil code cannot see imported bindings; use `call/2`.
- Hologram `<Link>` drops unknown attributes. Don't rely on attrs placed on Link.
