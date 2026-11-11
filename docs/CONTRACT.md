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

### Key case conversion (normative)

The conversions in the table above are plain character transforms, not `Macro.underscore`:

- **snake → camel** (`display_name` → `displayName`, detail `persona_id` → `personaId`): split on `_`, capitalize the first character of every segment after the first.
- **camel → snake** (`displayName` → `display_name`): each uppercase character becomes `_` + its lowercase form. `userID` → `user_i_d` — consecutive capitals each get their own underscore.

Spec keys MUST round-trip: `snake → camel → snake` is an identity, or a key written by the Elixir spec would arrive back at the bridge as something else. That rules out:

- **digit-initial segments after `_`** — `col_2_width` → camel `col2Width` → snake `col2_width` ≠ `col_2_width`. Write `col2_width`.
- **double or trailing underscores** — `my__key`, `trailing_` round-trip into different strings.
- **a leading underscore** — `_hidden` is rejected outright by the identifier grammar (`^[a-z][a-z0-9_]*$` does not admit a leading `_`), not by the round-trip rule: `:_hidden` would actually round-trip byte-identically. Leading underscores are tessera-internal (see the reserved-key guard in CONTRACT.md §4).
- **consecutive capitals in JS-authored detail keys** — camel → snake splits per character, so `userID` → `user_i_d` and it never comes back. Write `userId`.

The Elixir side validates these rules at compile time; the JS core does not police them at runtime — a non-round-tripping key silently mismatches.

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

`data-tsr-on` grammar: `entry (";" entry)*`, where `entry = event ":" action "@" target` and `target ∈ page | layout | <cid>`. **The characters `:`, `@`, `;` and whitespace are reserved** — they delimit the entry grammar, so they can never appear inside an event, action or target name. Declared names are rejected at compile time with a pointed `CompileError`; binding values only exist at render time, so the adapter rejects them there with an `ArgumentError` naming the component, the event and the value. A binding prop value of `:chose` means target `page`. A value of `{:chose, target: "layout"}` or `{:chose, target: "<cid>"}` (the tuple form — the only way to address a layout or a component `cid`) sets the target explicitly; the target must be a string. A bare binary (or any other non-atom) binding is rejected at render time with an `ArgumentError`. If an event has no binding, it gets no entry.

## 4. JS core runtime (`@noizu/tessera-core`)

- `defineOnce(tag, ctor)`: if `customElements.get(tag)` exists, warn once and return the existing ctor. Otherwise define it.
- `emit(el, name, detail)`: dispatches `new CustomEvent(name, {detail, bubbles: true, composed: true})`.
- `TesseraElement(Base, contract)`: a mixin over `HTMLElement` or `LitElement`. It observes the attrs in the contract plus `tsr-props`. It parses the `tsr-props` JSON and assigns each key as a property; bad JSON produces a warning, never a throw. It calls `requestUpdate()` when present. On `connectedCallback` it registers the contract's events with the bridge and runs `behaviors` for the tag.
- **Bridge.** A singleton at `globalThis[Symbol.for("tessera.bridge")]`, holding one capture-phase `document` listener per registered event name. When an event fires:
  1. Resolve the host element (`event.target` after retargeting).
  2. Parse its `data-tsr-on` and find the entry for `event.type`.
  3. Call `globalThis.Hologram.dispatchAction(action, target, snakeKeysDeep(event.detail ?? {}))`.

  If no entry matches, or `globalThis.Hologram` is absent, it does nothing, which is the plain-HTML/React case.

- **Nested shadow attribution (normative).** The bridge resolves bindings from the document level. When tessera element B sits inside tessera element A's shadow root and B dispatches a composed event, the retargeted shadow host A is the first candidate: **if A binds that event name, A's action fires and B's never does.** If A carries no entry, the bridge falls back to scanning the composed path for the first registered contract element carrying a mapping — open-shadow internals are visible on that path — so B's own mapping still fires when B's tag is registered. The event is dropped only when no registered element on the path maps it. Prefer deliberate composition: a component that composes tessera children should re-emit child events from itself — `emit()` from the outer element — to expose them explicitly (see `docs/EXTENDING.md` §4) instead of relying on the path fallback.
- `behaviors.add(tag, fn)`: `fn(el)` runs on each `connectedCallback`. It may return a cleanup function, which runs on disconnect.

## 5. Elixir ↔ JS import rules (Hologram 0.10.1, learned in the spike)

- `js_import` paths must be **absolute**: build them from the component module's `__DIR__`, never a relative path. Relative paths resolve against the *caller's* file.
- The JS export name must equal the binding name unless `as:` is given. Component modules export `register` (a no-arg function returning the ctor).
- Hologram only bundles a `js_import` if the page's call graph references it. The adapter therefore calls `register` through `Hologram.JS.call/2` inside a generated `init/2` + `init/3` pair — BOTH arities, because Hologram 0.10.1 treats `init/2` (client mount) and `init/3` (server) as separate optional callbacks: the compiler never derives one from the other, a stateful client mount calls `init/2` directly, and stateless SSR never calls `init/3` at all (which is why the top-level `register()` call in the `.mjs` is load-bearing). Author overrides must target `__tessera_init__/2` and/or `__tessera_init__/3`, never the generated `init` pair.
- `import Hologram.JS, only: [...]` **replaces** any earlier `only:` import, so always restate `js_import: 1, js_import: 2` alongside `call: 2`.
- `~JS` sigil code cannot see imported bindings; use `call/2`.
- Hologram `<Link>` drops unknown attributes. Don't rely on attrs placed on Link.
