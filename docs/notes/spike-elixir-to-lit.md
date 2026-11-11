# SPIKE — Elixir-to-Lit element DSL (`spike/elixir-to-lit`)

**Verdict: GO.** An author can define a fully functioning component — reactive
state, template, actions — entirely in Elixir through a Hologram-like DSL,
compiled at `mix compile` time into a real Lit custom element, shipped as both
ESM and UMD JavaScript that works in any host, with a *simpler* hookup for
Elixir/Hologram hosts than hand-written Lit elements.

Branch: `spike/elixir-to-lit` (pushed, not merged — spikes don't land).
Date: 2026-11-11.

---

## 1. What was built (evidence index)

| piece | where | proof |
|---|---|---|
| DSL (`state` / `template ~TSR` / `action`) | `lib/noizu/tessera/component.ex` + `lib/noizu/tessera/component/{expr,template,lit_codegen}.ex` | compile-time codegen, golden fixture |
| Two spike components, zero hand-written JS | `examples/spike_kit/lib/spike_kit/{counter,toggle_chip}.ex` (44 + 37 LOC) | WTR browser tests 10/10 |
| Generated Lit elements | `examples/spike_kit/lib/spike_kit/spike-*.element.generated.mjs` (gitignored artifacts; shape pinned by `test/fixtures/spike_widget.element.golden.mjs`) | golden test byte-for-byte |
| ESM + UMD + shared-runtime packaging | `examples/spike_kit/scripts/build-bundles.mjs` | size table §5 |
| Hologram host page | `demo/hologram_app/…/pages/spike_page.ex` → `http://localhost:5586/spike` | Cypress §7 |
| Plain-HTML UMD host | `demo/plain_html/spike.html` → `http://localhost:5587/spike.html` | Cypress §7 |
| React host (shared-runtime variant) | `demo/plain_html/react.html` → `http://localhost:5587/react.html` | Cypress §7 |
| ExUnit: subset accept/reject + golden codegen | `test/noizu/tessera/component/{expr,template,lit_codegen}_test.exs` | 165/165 root suite |
| WTR tests of generated elements | `examples/spike_kit/test/components/*.mjs` | 10/10 |

The two demo components mirror the brief: **counter** (attrs `label`/`step`,
state `count`, emits `count-change` with `%{count, delta}`) and
**toggle-chip** (required attr `chip_id`, state `selected`/`clicks`, emits
`chip-select` with `%{chip_id, selected}` — the persona-card selection shape).

---

## 2. The DSL

```elixir
defmodule SpikeKit.Counter do
  use Noizu.Tessera.Component, tag: "spike-counter", js: "spike_counter.mjs"

  attr(:label, :string, default: "Count")
  attr(:step, :integer, default: 1)
  state(:count, :integer, default: 0)
  event("count-change", detail: %{count: :integer, delta: :integer})
  cy("spike-counter-root")

  template ~TSR"""
  <div class="counter" data-cy="spike-counter-root">
    <span class="label">{@label}</span>
    <button type="button" class="btn dec" data-cy="spike-counter-dec" $click={:decrement}>-</button>
    <span class="count" data-cy="spike-counter-count">{@count}</span>
    <button type="button" class="btn inc" data-cy="spike-counter-inc" $click={:increment}>+</button>
  </div>
  """

  action :increment, fn state, _params ->
    emit("count-change", %{count: state.count + @step, delta: @step})
    %{state | count: state.count + @step}
  end
end
```

`mix compile` translates the template to a lit-html `render()` and each
action to a JS function (multi-expression bodies become an IIFE: emit, then
return the next state map), then writes:

* `<tag>.element.generated.mjs` — `LitElement` subclass mixed with
  `TesseraElement`: reactive properties from state + attrs + props
  (state keys stay snake_case; attrs/props camelCase), constructor defaults,
  `__tesseraState/SetState/RunAction` runtime, one `__action_<name>` per
  action, `register()` via `defineOnce`, top-level auto-register.
* the `:js` entry wrapper (`spike_counter.mjs`) when absent — never clobbers
  a hand-written one. The Hologram adapter's existing `js_import` wiring
  picks it up unchanged.

Wire conventions (unchanged from CONTRACT.md): events are composed
CustomEvents with **camelCase detail keys at the emit boundary**; the
`data-tsr-on` bridge snake-cases them back, so `on_chip_select={:chose}`
lands in the page action as `params.chip_id`.

---

## 3. Template parser finding (dual lexer)

`Noizu.Tessera.Component.Template` uses **Hologram 0.10.1's own template
parser as a library call** when Hologram is loaded —
`Hologram.Template.Parser.parse_markup/1` (public, `@doc`'d, but on a
`@moduledoc false` module in a pre-1.0 package: usable today, **no stability
guarantee**) — and a **minimal fallback lexer** otherwise (spec-only / npm
consumers that don't depend on Hologram). Both produce the same shared token
stream; the spike grammar (`{expr}`, `{%if}/{%else}/{/if}`, `{%for x <- coll}`,
`$event={:action}`) is deliberately the intersection of Hologram's grammar
and what the minimal lexer implements, so neither lexer is a second language.

* Root repo (Hologram in deps) → `:hologram` lexer; `TemplateTest` pins it.
* `examples/spike_kit` (no Hologram dep) → `:minimal` lexer; its ExUnit
  asserts `lexer: :minimal` and the WTR tests prove the generated elements
  behave identically.

Gotchas found: Hologram's parser emits inter-tag whitespace as text nodes
(cosmetic), and it *raises an opaque internals error* on unknown directives —
`Template` pre-scans for directives outside `{%if}/{%else}/{%for}` and
rejects them by name before handing off.

**Rejected alternative (per brief): embedding Hologram's own client runtime
in the element.** The element would ship Hologram's full JS runtime (its
stdlib bundle) alongside Lit — two runtimes, two template engines, ~an order
of magnitude more bytes than the element itself; both runtimes contend for
`globalThis.Hologram` bookkeeping if a page also hosts Hologram proper; and
it would rely on Hologram internals (`@moduledoc false` modules, pre-1.0
transpiler output shapes) that carry no stability promise. The DSL approach
gives Hologram-*shaped* authoring with zero runtime coupling.

---

## 4. Restricted expression subset

**In** (translator `Noizu.Tessera.Component.Expr`): literals; `state.<key>`
(validated against declared state keys), `params.<key>` / `params[:k]` /
`params["k"]`; `@attr` / `@prop` reads (validated); map update
`%{state | k: v}` and map literals (snake keys camelCased in emit details);
lists; arithmetic / comparison / `and` / `or` / `not`; `if/do/else`
(ternary); string interpolation `#{}` (the parser's injected
`Kernel.to_string/1` is unwrapped inside `${}`); pipe `|>`; single-clause
`fn x -> … end` as an `Enum` callback argument; `emit/2` (event validated);
allowlisted `Kernel` (`abs`, `min`, `max`, `round`, `trunc`, `to_string`,
`div`, `rem`…), `String` (`upcase`, `downcase`, `trim`, `capitalize`,
`length`), `Enum` (`map`, `count`, `at`, `filter`?, `reject`? — see
`@enum_allowlist` in `expr.ex`).

**Out** — every rejection names the construct in the CompileError (26/26
tests in `expr_test.exs`): `case`/`cond`/`with`; multi-clause `fn`; captures
`&f/1`; assignment/bindings; structs; tuples; `++`; modules outside the
allowlist (`Map.get`, …); allowlisted module but non-allowlisted function
(`String.pad_leading`); undeclared state key (`state.nope`), attr, event or
action; anonymous `fn` outside callback position; JS itself (use
`behaviors.add` — unchanged escape hatch).

Multi-expression action bodies become a JS IIFE — arrow IIFEs don't bind
`this`, so `emit(this, …)` works inside them.

---

## 5. Bundle sizes (esbuild, minified, es2020)

| artifact | raw | gzip | notes |
|---|---|---|---|
| `spike-counter.esm.js` | 22.0 KiB | **8.1 KiB** | ESM, lit + core inlined |
| `spike-counter.umd.js` | 22.9 KiB | **8.4 KiB** | UMD → `window.Tessera.Counter`, auto-defines on load |
| `spike-counter.runtime.esm.js` | 2.1 KiB | **0.9 KiB** | ESM variant, lit + core via import map |
| `spike-toggle-chip.esm.js` | 21.8 KiB | **8.1 KiB** | ESM, inlined |
| `spike-toggle-chip.umd.js` | 22.7 KiB | **8.4 KiB** | UMD → `window.Tessera.ToggleChip` |
| `spike-toggle-chip.runtime.esm.js` | 1.9 KiB | **0.9 KiB** | runtime variant |
| `tessera-runtime.esm.js` | 22.4 KiB | **8.4 KiB** | shared runtime (lit + core), amortized |

Variant pair (counter): inlined 8.1 KiB gz vs runtime-variant 0.9 KiB gz +
shared runtime 8.3 KiB gz. **Break-even at 2 components** (2×0.9+8.3 = 10.1
vs 2×8.1 = 16.2) — a component kit should ship the shared-runtime form plus
one inlined UMD escape hatch for script-tag hosts. Per-component payload
*above* the runtime is ~0.9 KiB gz.

UMD note: esbuild has no UMD format, so `build-bundles.mjs` builds an IIFE
and wraps it in a standard UMD shell; browser-global loads merge exports into
a shared `window.Tessera` namespace (multiple component scripts compose; the
shell is defensive under AMD/CJS).

---

## 6. DX comparison

| | persona-card (today: DSL contract + hand-written Lit) | spike-counter (this spike: element DSL only) |
|---|---|---|
| Elixir | 73 LOC | **44 LOC** |
| Hand-written JS | 119 LOC (`persona_card.mjs`) | **0** |
| Generated (not authored) | — | 82 LOC element module |
| Languages the author must know | 2 | **1** |
| Hookup on a Hologram page | identical (`<Component on_event={:action}/>` — same adapter, same bridge) | identical |

Toggle-chip: 37 Elixir LOC, no JS. The counter's hand-written equivalent
would be ~100+ lines of Lit + a parallel Elixir contract declaration.

---

## 7. Host proofs (Cypress — `demo/e2e/src/e2e/spike_lit.cy.ts`)

All three hosts pass the same behavioral assertions on the *same generated
elements* (mounted-proof + absence-of-console-error per CONVENTIONS §7):

1. **Hologram** (`http://localhost:5586/spike`) — `on_count_change={:counted}`
   and `on_chip_select={:chose}` land in page actions with snake_cased
   params (`%{chip_id: _, selected: _}`, `%{count: _, delta: _}`); page state
   re-renders; chip local state flips its own template branch.
2. **Plain HTML** (`http://localhost:5587/spike.html`) — two UMD script tags;
   `window.Tessera` exposes `Counter` + `ToggleChip`; vanilla
   `addEventListener` receives the camelCase detail maps; attrs coerce
   (`step="2"`).
3. **React** (`http://localhost:5587/react.html`) — React 18 CDN renders the
   elements; shared-runtime ESM variant through an import map (both bare
   specifiers → one `tessera-runtime.esm.js` instance); React state updates
   from `count-change` / `chip-select`.

Run: `cd demo/hologram_app && mix holo` (5586) + `cd demo/plain_html &&
node serve.mjs` (5587) + `cd demo/e2e && npm run run -- --spec
src/e2e/spike_lit.cy.ts`.

**Result at spike close: 7/7 passed** (`npx cypress run --spec src/e2e/spike_lit.cy.ts` — three hosts, 13s).

---

## 8. Risks / open edges

* **Hologram parser dependency is advisory, not load-bearing** — if Hologram
  0.11 moves `parse_markup`, the minimal lexer carries spec-only consumers;
  components compiled *in a Hologram host* would need the fallback lexer to
  accept the same grammar (it does today — both lexers are pinned by tests).
* **Two lexers = permanent dual maintenance.** The grammar intersection is
  small and pinned from both sides (root suite exercises Hologram's, spike_kit
  the minimal one); divergence would show up as a red suite, not a broken
  element.
* **Subset drift**: the allowlists in `expr.ex` are deliberately tiny; every
  addition needs a translate + accept + reject test. `Enum.filter/reject`
  exist in the allowlist table but are the least-exercised entries.
* **Formatting-sensitive goldens**: the golden fixture pins byte-for-byte
  output — intentional (determinism is the contract), but any cosmetic
  codegen change rewrites the fixture.
* **esbuild re-export pitfall** (hit twice): a shared-runtime entry must use
  explicit named re-exports AND `format: "esm"` — `export *` chains get
  tree-shaken and the API default format emits no exports; both failures look
  like `module 'lit' does not provide an export named 'html'` at runtime.
* **UMD namespace merge** is a shell convention (not a spec'd AMD behavior);
  documented in `build-bundles.mjs`.
* **`state` keys stay snake_case on the wire (element properties)** while
  attrs/props camelCase — consistent with the Hologram bridge but worth a
  line in CONTRACT.md when this lands for real.
* Not attempted (correctly, per brief): embedding Hologram's runtime (§3).

---

## 9. If GO — phase placement & PR sequence

The translator/codegen is additive behind the existing `use
Noizu.Tessera.Component` — no existing contract, adapter or JS changes
(root suite 165/165 including the untouched persona_kit paths). Suggested
sequence, each PR independently green:

1. **PR 1 — element DSL core**: `component.ex` accumulators + `Expr`
   (subset, allowlists, all rejections by name) + `Template` (dual lexer)
   + `LitCodegen` + golden/expr/template/codegen tests. No consumer changes.
2. **PR 2 — packaging**: `build-bundles.mjs` generalized under
   `mix tessera.build` (per-component ESM/UMD/runtime-variant + size report),
   documented in CONSUMING.md.
3. **PR 3 — demo + e2e**: `/spike` page, `spike.html`, `react.html`,
   `spike_lit.cy.ts` (all as landed in this spike, rebased).
4. **PR 4 — docs**: CONTRACT.md §"element components" (wire conventions,
   snake-state/camel-attr rule), EXTENDING.md pointer (behaviors escape
   hatch unchanged), `docs/notes/` retention of this spike.

Phases map to the tessera roadmap's "authoring ergonomics" phase; nothing
here blocks or reorders the schema/infra phases.

---

## 10. Reproduction

```sh
# root suite (subset + goldens + both-lexer template tests)
mix test                                   # 165 passed

# generated-element browser tests + packaging
cd examples/spike_kit && mix test          # 6 passed
npm test                                   # 10 passed (WTR)
npm run build:bundles                      # size table §5

# hosts
cd demo/hologram_app && mix deps.get && mix tessera.install && mix holo   # :5586
cd demo/plain_html && npm install && npm run build && node serve.mjs      # :5587

# e2e (all three hosts)
cd demo/e2e && npm install && npx cypress run --spec src/e2e/spike_lit.cy.ts
```

*Session-registration note:* tobor `Session_Create` returned 503 twice at
session start; per the active-development exception the spike proceeded
without a session ID.
