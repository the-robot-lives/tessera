# Tier 2 spike — Hologram components as standalone custom elements

Status: **landed on `spike/hologram-runtime-element`** (spike branch — no PR, no merge).
Question answered: *can a complex interactive component written as an ordinary Hologram
component (`use Hologram.Component`, `init/2`, `action/3`, `~HOLO`, `put_state`) be compiled
by Hologram's own compiler and run inside a standard custom element's shadow root in ANY
host — plain HTML, React, Hologram page?*

**Verdict: YES — with three caveats** (below). No Hologram fork was needed; everything runs
against the house pin `0.10.1` from `deps/hologram`, patched only at the JS *surface* by a
tessera-owned shim that wraps — never edits — Hologram's runtime.

1. **The component must be written against one tessera-authored seam** (`HoloKit.Emit.mount/2`
   + `emit/3`, ~20 lines): a synthetic host-bridge cid `<cid>$h` + `put_action/2` aimed at it.
   Everything else about the component is stock Hologram.
2. **Per-component bundles inline the base when derived via `use`** (see
   [Base duplication](#base-duplication-each-derived-module-inlines-the-base)) — N derived
   tags cost N base copies today.
3. **Compile-time dependence on Hologram internals is real but narrow** (mirrored pipeline +
   two private-ish APIs); every touch point is listed below and is version-pinned.

Evidence: `demo/e2e/src/e2e/holo_runtime_element.cy.ts` — 16 specs, all green, across three
hosts (Hologram page :5586, plain HTML :5589, React 18 :5589), covering filtering, keyboard
nav, inline edit + validation (blank/duplicate), Esc-cancel, event payloads (camelCase
detail), focus retention, `data-tsr-on` bridge into host page actions with snake_cased
params, host client navigation while elements are mounted, and the extension items (A),
(A2), (B).

---

## 1. Isolated compile — how it works (`mix tessera.compile_component Mod`)

`lib/noizu/tessera/hologram/standalone.ex` mirrors Hologram's own `mix compile.hologram`
pipeline, minus the app:

```
rm build dir → compile extra_sources (third-party .ex) to scratch ebin
→ expand `use Base, tag:` modules → compile synthetic stub page + layout per component
→ load scratch OTP app (spec-modules trick — see below)
→ build_ir_plt(supervisor: stub) → build_call_graph → list_async_mfas
→ clone |> remove_manually_ported_mfas → validate_page_modules
→ list_runtime_mfas → remove_runtime_mfas!
→ per component: Compiler.build_page_js(...)   (Hologram's own function)
→ surgical JS edits (defs → registration call) → esbuild (esm / umd / standalone)
```

Internals it depends on (all 0.10.1, all listed for the fork/upstream conversation):

| API | Kind | Why |
|---|---|---|
| `Hologram.Compiler.build_ir_plt/1`, `build_call_graph/1`, `list_async_mfas/2`, `remove_manually_ported_mfas/1`, `validate_page_modules/2`, `list_runtime_mfas/3`, `remove_runtime_mfas!/2`, `build_page_js/6` | the compiler pipeline itself | reproducing `mix compile.hologram` for a non-app target |
| `Hologram.Compiler.Reflection.list_elixir_modules/0` | module enumeration | enumerates **loaded OTP apps only** — scratch app must be loaded first |
| `Hologram.Compiler.CallGraph` internals (`server_callback_analysis_by_templatable`, reachable-set extraction) | digraph analysis | the analysis map must contain EVERY templatable in a page's reachable set (page + **layout** + components) or `list_page_mfas` raises `BadMapError` |
| runtime JS (`assets/js/*.mjs`) anchor points: `pageReachableFunctionDefs`, `pageScriptLoaded`, `#defineManuallyPortedFunctions` | source-anchored string surgery | extracting the defs payload out of the emitted page JS and re-registering it under the tessera handshake |

Hard-won mechanics (each cost a debugging round):

* **`Kernel.ParallelCompiler.compile/2` NEVER writes BEAM files.** `beam_dest:`/`dest:` only
  annotate in-memory loads (Elixir 1.20.1 docs). Compiling third-party + stub sources with
  `compile/2` produced 237-byte "defs" bundles because the modules never hit disk and the
  scratch app loaded nothing. `compile_to_path/3` is required at both call sites.
* **Scratch app load**: tuple-loaded apps break `:code.lib_dir`, so the scratch app
  (`:tessera_holo_stubs`) is loaded via `Application.load({:application, ..., modules:
  beams})` with `Application.spec(app)[:modules]` as the enumeration path, then
  `Code.append_path` + per-module purge/`Code.ensure_loaded`. (`:code.load_module/1` is
  gone/private on OTP 29.)
* **The stub LAYOUT must be in the `server_callback_analysis` map** — `list_page_mfas`
  walks the page's reachable set, which includes the layout; a map keyed only by
  pages+components raises.
* **Module attributes are order-dependent**: `@scratch_app` used before its definition
  silently reads `nil` (this produced lying debug probes for a whole session).

## 2. Runtime surface — the shim (`priv/tessera_holo/src/`)

* `tessera_holo.mjs` — `initRuntime(hologram)` + `mountComponent(shadowRoot, Module, props)`
  WITHOUT forking Hologram: monkey-patches the shim's own runtime copy
  (`executeAction` for the `$h` emit bridge + the item-B hook chain, `render` for
  instance re-render, `sendCommand` for the documented BusClient seam — `put_command`
  out of scope for this spike, logged + dropped with `{ok: false, reason: "no-transport"}`).
* `register.mjs` — runtime-free component registrar: bundles push
  `{moduleName, defs, manifest}` onto `globalThis.__TesseraHoloComponents`; whichever
  runtime initializes first drains the queue; loads after init self-apply through
  `globalThis.__TesseraHoloApply__`. Load order between runtime and component bundles
  does not matter.
* `element.mjs` — `TesseraHoloElement` (`tsr-props` JSON attribute + kebab attributes cast
  via the compiled prop contract; open shadow root; `setProps`, `onAction`,
  `dispatchAction`, frozen `state` snapshot; documented subclass hooks
  `transformProps/1`, `onActionError/2`) and `defineElement/3` (tag→module map, later
  registration wins for elements connecting afterwards — the §5.9 takeover mechanism).

Bug class worth recording: **module-name aliases**. `Interpreter.moduleProxy(alias)` maps a
bare `HoloKit.Components.Counter` into the `Erlang_*` namespace — every lookup must use the
`Elixir.`-prefixed alias, and the descriptor registry accepts both spellings. Symptom when
wrong: "component … is not registered" although the bundle loaded.

Boot-time findings (each was a silent no-mount or blank shadow):

* The stock runtime **reads `globalThis.Hologram.isProfilingEnabled` around every delegated
  call** and assumes the page runtime created that object. On non-Hologram hosts the shim
  must stub it (`globalThis.Hologram ??= {isProfilingEnabled: false}`); on Hologram hosts
  the host's object wins and the shim merely save/restores the flag around delegated calls.
* **`JS.call` in `init/3` is a server-side pass-through** in 0.10.1 — client JS interop only
  executes inside action handlers, so a page cannot seed its glue from `init`. The
  Hologram-host glue is therefore a **module side effect** (`holo_runtime_glue.js` runs when
  the page bundle loads — initial SSR load and every client-side navigation; the module
  registry caches it, so the bootstrap runs once per document and element definitions
  survive navigation).
* **One constructor cannot define two tags.** `customElements.define` rejects a class
  already registered for another tag (`NotSupportedError: this constructor has already been
  used with this registry`) — `defineElement` therefore creates a fresh anonymous subclass
  per tag (which is also what makes host-JS subclassing under a new tag composable).
* **`renderDom`'s `context` argument is the boxed emitted-context map**, not an interpreter
  context: `#renderStatefulComponent` feeds it straight into `:maps.merge/2`, so passing
  `Interpreter.buildContext(...)` (a plain JS object) raises `BadMapError`. A standalone
  instance has no context providers and starts from `Type.map()`. Its `defaultTarget`
  argument is overridden with the component cid — template event bindings automatically
  target the instance.
* **`renderDom` returns a FLAT ARRAY of vnodes/text** for a list-root template (stock
  `renderPage` wraps it in html/body vnodes before patching). snabbdom cannot patch an
  array — the shim wraps it in `h("div", …)` (symptom if you don't: a literal `<undefined>`
  element inside the shadow root).
* **Boxed bitstrings carry `.text` (plus bytes/hex), NOT `.value`** — reading `.value` on a
  boxed bitstring yields `undefined`. Every decode goes through
  `Bitstring.toText(value)` (`RT.deps.Bitstring`), incl. action targets and map keys.

Testing notes (cost real debugging time, both Cypress-specific):

* In `cy.window().then((win) => …)` a bare `document` is the RUNNER's document — AUT
  queries must use `win.document`.
* **Never reuse a stored chainable across interactions inside a shadow root** (`const el =
  cy.get(sel)` then `el.shadow()` twice with a `.type()` in between): the held subject goes
  stale after the re-render and the next `.shadow()` retries for 10 s claiming the element
  "never hosts a shadow root" although the element is live, connected and mounted (proven
  via failure post-mortems dumping element state at the timeout). Always issue fresh
  `cy.get(sel).shadow()` chains.
* **`.type()` resolves when key events dispatch, not when the interpreter has applied the
  state** — the Hologram action queue is async, so a filter typed and immediately followed
  by keyboard navigation selects the wrong row. Gate on a rendered effect first (e.g.
  `items.should("have.length", 1)`). Related spec-shape trap: the demo component's
  duplicate-name validation is case-insensitive across ALL rows including the one being
  renamed — renames that case-insensitively equal the row's own name are (correctly)
  rejected, and a renamed row no longer matching the active filter disappears from view
  (both bit the first draft of these tests).

## 3. Coexistence with a host Hologram runtime

Two full runtime copies (host page bundle + tessera-runtime) coexist on one document:
compiled function defs register on the **shared** `globalThis.Elixir_*`/`Erlang_*` proxies.
Same hologram version ⇒ identical registration, overwrite harmless; version mismatch ⇒ last
writer wins — the manifest records the compiled hologram version for a handshake check
(recorded as a risk, not yet enforced). Verified live: host client navigation keeps working
with tessera elements mounted, and element emits reach host page actions through the
existing `data-tsr-on` bridge with snake_cased params (same contract as Tier 1).

## 4. Sizes vs Tier 1 (`origin/spike/elixir-to-lit`)

Tier 1 reference: counter ~8.1 KiB gz **inlined** (single-file); ~0.9 KiB per component +
~8.4 KiB shared when split. Tier 2 numbers (esbuild, es2021, minified, raw/gzip bytes):

| artifact | raw | gzip |
|---|---|---|
| tessera-runtime.esm.js (shared, exactly once) | 393,758 | 86,259 |
| tessera-runtime.umd.js | 394,346 | 86,497 |
| counter.esm.js | 13,650 | 2,278 |
| counter.umd.js | 14,630 | 2,683 |
| editable_list.esm.js | 58,259 | 7,387 |
| editable_list.umd.js | 59,239 | 7,841 |
| fancy_list.esm.js (derived) | 60,426 | 7,469 |
| fancy_list.umd.js (derived) | 61,406 | 7,921 |
| tidy_list.esm.js (derived) | 59,283 | 7,382 |
| tidy_list.umd.js (derived) | 60,263 | 7,834 |
| counter.standalone.esm.js (runtime+component) | 407,501 | 88,215 |
| editable_list.standalone.esm.js | 452,110 | 93,274 |

Per-component cost is competitive with Tier 1 (~7.4 KiB gz for the complex list vs ~0.9 KiB
— Hologram's client IR for the same component is simply bigger than Lit), but the **shared
runtime is ~10× Lit's** (86 KiB vs 8.4 KiB gz): Hologram ships its ERTS/interpreter. One
runtime is loaded exactly once per document regardless of how many components mount.

### Base duplication (each derived module inlines the base)

`use HoloKit.Components.EditableList, tag: ...` re-defines the base component *inside* the
deriving module (that is what makes `defoverridable` + `base_action/3` work), so the
compiler emits the base's IR again in every derived bundle: fancy_list/tidy_list ≈ 60 KB
raw each vs editable_list 58 KB. N derived tags ⇒ N base copies. Mitigations (future,
upstream-shaped): cross-bundle module dedup on the shared `Elixir_*` proxies (defs are
idempotent if identical), or an upstream "component bundle" target that emits a shared
base + thin derived defs.

## 5. Extension results

### (A) Compile-time extension — FEASIBLE

`ThirdParty.FancyList` (`demo/hologram_app/test/support/third_party/fancy_list.ex`):
`use HoloKit.Components.EditableList, tag: "fancy-list"`; overrides
`action(:save, _, _)` (trim, then delegate via the macro-injected `base_action/3`
dispatcher — **not `super`**, which Hologram 0.10.1's client transpiler does not support),
adds `action(:archive, ...)`, replaces the named template region `row_label/1`
(value-level region, not a DOM fragment). Runs alongside the base on the same page in all
three hosts; e2e proves upcased rows + trimmed saves + archive.

### (A2) Same-tag takeover — FEASIBLE (compile-time), with a JS-side seam (layering)

* **Compile-time**: a third-party module may register under the VENDOR's tag.
  `defineElement("tsr-holo-editable-list", "ThirdParty.TidyList")` after the vendor
  registration repoints the tag→module map. The custom-element CLASS cannot be redefined
  once registered (platform spec), so:
  * elements that connect **after** the takeover resolve the layered module;
  * already-connected instances keep their module — new behaviour layers onto them via the
    (B) `onAction` chain instead.
* **JS-side layer onto an already-defined tag**: possible only through those two seams
  (map repoint for future elements + `onAction` chain for live instances) — re-defining
  the class for a live tag is impossible by spec. Both seams are implemented and e2e-proven
  (`layered-list` downcases saves while the vendor instance on the same page does not).
* The takeover is an EXTENSION, never a substitute: the vendor behaviour stays reachable
  through `base_action/3` inside the layered module (TidyList downcases, then runs the
  vendor save/validation/emit underneath — asserted by `hr-saved-name` receiving the
  downcased name).

### (B) JS runtime extension WITHOUT Hologram internals — FEASIBLE

`el.onAction(name, (params, next) => ...)`, `el.dispatchAction(name, params)`, `el.state`
(read-only frozen plain object, camelCase primary + snake_case aliases), either-case names
and param keys, ALL actions open (no allowlist), `class X extends
customElements.get(tag)` overriding the documented `transformProps` / `onActionError`
hooks. Extender code imports nothing from Hologram and never touches
`globalThis.Hologram` — verified in the demos (`plain/index.html`, `react/index.html`):
composed hooks in registration order (`draft-changed` strips `!`, `draftChanged` collapses
`--`), param-rewriting interception (React forces every `selectItem` to id 1),
`dispatchAction` in either case, state aliases agreeing, subclass title suffix.

### T2-9 — does the scaffolding lift into a `use Vendor.Element` macro cleanly? — YES

The compile-time scaffolding used here **already is** a `use` macro:
`use HoloKit.Components.EditableList, tag: "fancy-list"` expands to the full base
component (props, init, `base_action/3` dispatcher over every action clause,
`defoverridable action: 3, row_label: 1, init: 2`). A canonical
`use Vendor.Element, tag: ...` is the same macro with the `tag:` opt mandatory and the
dispatcher injection made contractual — no new mechanism needed. The ONE gap for
multi-level extension: `base_action/3` currently dispatches to the base baked into the
deriving module, so A→B→C chains re-include the whole stack rather than linking through
the parent; the macro needs to record its parent module and emit
`base_action` → `parent.action` for true chaining (documented here; NOT implemented —
canonical macro is a later phase).

## 6. DX example

```elixir
# 1) write an ordinary Hologram component (one seam: mount the emit bridge)
defmodule HoloKit.Components.EditableList do
  use Hologram.Component
  prop :title, :string, default: "Items"
  prop :items, :list, default: []

  def init(props, component) do
    component
    |> HoloKit.Emit.mount(props)          # synthetic host bridge
    |> Hologram.Component.put_state(items: Map.get(props, :items, []), ...)
  end

  def action(:save, _params, component), do: ...
  def template, do: ~HOLO"""
    <div data-cy="holo-list-root">...</div>
  """
end
```

```bash
# 2) compile it (host app with :hologram + :noizu_tessera deps)
mix tessera.compile_component HoloKit.Components.EditableList
```

```html
<!-- 3) mount anywhere -->
<script src="tessera-runtime.umd.js"></script>
<script src="editable_list.umd.js"></script>
<script>
  TesseraHoloBundle.defineElement("tsr-holo-editable-list", "HoloKit.Components.EditableList");
</script>
<tsr-holo-editable-list tsr-props='{"items":[...]}'></tsr-holo-editable-list>
```

## 7. Risks / upstream-PR shape

* **Version churn**: the JS surgery anchors (`pageReachableFunctionDefs`,
  `pageScriptLoaded`, `#defineManuallyPortedFunctions`) are string anchors into Hologram's
  runtime source; any refactor breaks the build loudly (assertion on anchor presence), but
  it IS a fork-shaped patch until upstream lands a component-bundle target. The pipeline
  calls are all public functions of `Hologram.Compiler` today — an upstream
  `Compiler.build_component_js/5` would remove most of the mirroring.
* **Pre-1.0 internals**: `CallGraph`/`Reflection` internals could shift; the house pins
  0.10.1 and the manifest records the compiled hologram version for a mismatch check.
* **Shared global proxies**: cross-runtime overwrite is harmless only at the same version
  (see §3); a version handshake should be enforced before mixed-version hosts are allowed.
* **SSR/DSD**: not attempted — the element mounts client-side only; Hologram's SSR path
  renders pages, not arbitrary component shadow roots. Declarative shadow DOM would need
  the same defs serialized server-side (open question, upstream-shaped).
* **Bus routing (`put_command`)**: shimmed seam (`setBus`), logged + dropped by default;
  Tier 1 parity here is a later phase.
* **`JS.call` in `init/3`** is a server-side pass-through (0.10.1) — host glue must be a
  module side effect; worth an upstream docs note at minimum.

## 8. Recommendation — Tier 1 + Tier 2 behind one contract

Ship both: per-component `runtime: :lit | :hologram` in the tessera component contract.

* **Default stays Lit (Tier 1)**: 10× smaller shared runtime, ~8× smaller per-component
  bundles, no compiler internals dependence.
* **Tier 2 (`:hologram`)** where the component's domain logic is Elixir-side anyway
  (validation, complex state machines, server-shared code): the component is an ordinary
  Hologram component, dev-tested in a Hologram page, then exported as a host-agnostic
  element with the SAME wire contract (camelCase event detail, snake_cased params at the
  `data-tsr-on` bridge, `tsr-props` JSON) — hosts cannot tell the tiers apart.
* The `HoloKit.Emit` seam is the only tessera-authored convention inside the component; it
  degrades to a no-op-ish unknown-cid action on plain Hologram pages (documented in
  `emit.ex`).

---

## Appendix — repro

* compile: `cd demo/hologram_app && mix tessera.compile_component HoloKit.Components.EditableList HoloKit.Components.Counter ThirdParty.FancyList ThirdParty.TidyList --out priv/static/tessera-holo`
* hosts: `HOLOGRAM_START=1 mix run --no-halt` (:5586, `/holo_runtime`) · `node serve.mjs`
  (:5589, `/plain/` + `/react/`)
* e2e: `cd demo/e2e && npx cypress run --spec src/e2e/holo_runtime_element.cy.ts`
