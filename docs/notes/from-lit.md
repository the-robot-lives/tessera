# From Lit — converting an existing Lit component to a tessera stub

> Added: 2026-11-11 · `mix tessera.from_lit` · `Noizu.Tessera.FromLit.{Extractor, Generator}`

## When to use

You have a working Lit 3 element (`.js`/`.ts`) and want it under a tessera
contract: the Elixir spec DSL becomes the source of truth, `mix compile`
generates the wire contract module, and Hologram hosts get the
attr/prop/event/slot bridge for free. The converter does the mechanical
part — reading the element's declared surface and scaffolding the spec — so
you start from a typed stub instead of a blank file.

It is a **stub generator, not a transpiler**. The element's lifecycle
callbacks and methods are NOT converted. `render()` IS converted —
mechanically, into a `template ~TSR` block plus `action` stubs — for the
subset documented in the `Noizu.Tessera.FromLit.Render` moduledoc table;
anything outside the subset is dropped with a `todos` entry (and a warning)
rather than guessed. Directives keep the Tier-1 literal forms: `classMap`
and `styleMap` take an inline object literal only, `guard` takes a literal
dep array and a value-expression body (no html bodies — those lower only via
the ternary/&& branch forms).

## How to use

```bash
# in the host Mix project (or any directory with --out)
mix tessera.from_lit assets/js/persona-widget.ts
mix tessera.from_lit src/my-element.ts --out packages/my_element
mix tessera.from_lit src/my-element.ts --module MyApp.Components.MyElement --tag my-element

mix compile          # generates <snake_tag>.contract.generated.mjs
mix tessera.install  # once per host app, wires @noizu/tessera-core
```

Writes the same file set as `mix tessera.gen.component`: the spec module
(`lib/...`), the colocated `<snake_tag>.mjs` Lit element stub (extracted
`static styles` carried over, `register` export kept — CONTRACT.md §5), and
a WTR test skeleton. Existing files are never overwritten unless `--force`.

The task prints the extracted shape (properties, events, slots, styles) and
every warning; the warnings are also embedded in the generated moduledoc so
they survive the terminal scroll-back.

## What the extractor recognizes

| Lit pattern | Shape field |
|---|---|
| `@customElement("tag")`, `customElements.define("tag", C)` | `tag` |
| `class C extends LitElement` (also `ReactiveElement`) | `class_name` |
| `@property({...})` / `@state()` fields — multiline options, TS annotations, `declare`/`accessor`/visibility modifiers, literal defaults (incl. multiline arrays/objects) | `properties[]` |
| `static properties = {...}` / `static get properties()` — option objects, `name: Type` shorthand, `state: true` | `properties[]` (kind `static`) |
| `dispatchEvent(new CustomEvent("name", {detail, bubbles, composed}))`, `new Event("name")` | `events[]` (detail types inferred from literals; non-literals → `any`) |
| `<slot>` / `<slot name="x">` | `slots[]` (unnamed → `default`) |
| `static styles = css\`...\`` — single, array, getter form | `styles[]` (raw CSS) |

Type mapping: `String`→`:string`, `Number`→`:float`, `Boolean`→`:boolean`,
`Array`→`:list`, `Object`→`:map`; TS annotations map the same way; without
either, the default literal's type is used (Lit's own fallback is `String`).

## What the generator does with it

* attribute-observed scalars → `attr` (snake_case atom, kebab on the wire);
* `attribute: false` scalars → `prop`; `list`/`map` → `prop, json: true`
  (tsr-props), even if Lit observed an attribute for them (warned);
* `@state` fields → **commented-out** `state` declarations — internal state
  is not wire surface; enable them with the element DSL when you port the
  template;
* events → `event` with snake_cased detail keys; names the contract grammar
  rejects are adapted loudly (`focusChanged` → `focus-changed`, `close` →
  `<tag>-close`) and the adaptation is warned in the terminal AND the
  moduledoc — rename in spec **and** element if you want the original;
* slots → `slot`; plus `cy "<tag>-root"`;
* names failing the snake_case grammar or the snake↔camel round-trip
  (CONTRACT.md §1) are skipped with a warning, never silently mangled.

## Known limitations (warned, not guessed)

Computed defaults (`= crypto.randomUUID()`), custom `converter`/`hasChanged`,
spread options, non-literal event names, events constructed away from their
`dispatchEvent` call, `${...}`-interpolated styles (captured raw, commented
out in the stub), and backticks nested inside template interpolations.
Parsing is a comment-aware scanner, not a JS parser — exotic syntax may be
missed; the warnings list is the honest inventory of what was not carried.

## Workflow

1. Convert: `mix tessera.from_lit <source>` — read the warnings.
2. Verify the spec against the original element (the stub's moduledoc lists
   every adaptation); fix names/types/defaults by hand.
3. Port `render()`/methods into the `.mjs`, or rewrite with the element DSL.
4. `mix compile`, expand the WTR skeleton, run the host's tests.

Tests: `test/noizu/tessera/from_lit/{extractor,generator}_test.exs`
(fixtures: `test/fixtures/lit/`). The generator suite compiles the emitted
spec for real (`Code.compile_string`) and asserts the resulting
`__tessera_spec__/0` contract — the stub is proven compilable, not just
plausible text.