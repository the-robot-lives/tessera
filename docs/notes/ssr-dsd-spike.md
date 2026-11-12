# Spike 4c — SSR / Declarative Shadow DOM (DSD) hydration for Tier 2

**Verdict: GO (conditional) — DSD emission + hydration onto the server-rendered
shadow root are empirically proven on the Tier-2 runtime at `develop@1d0501b`.
This is a spike, not production: no shim or compiler file changed. Two concrete
deltas remain for a production implementation (§4), both small, both proven
in-shape by the prototype.**

Context: lit-parity §2.12 rows #154–#165, the row marked "highest-risk" (#155
DSD). U8 gate: never a release blocker; accept-as-gap was the sanctioned
fallback — not needed: the question is answered.

> **Production status (2026-11-12, TESSER SSR-1/SSR-2): §4.1 and §4.2 LANDED.**
> The shim adopts a server `[data-tessera-holo-host]` and normalises the
> adopted vnode sels (`priv/tessera_holo/src/tessera_holo.mjs`
> `findServerHost` / `normalizeHydratedVnode`; `mountComponent(…, {hydrate:
> false})` opts out). `Noizu.Tessera.Hologram.Render.element/4` emits the DSD
> markup plus `tsr-props`. Proven in a browser by `demo/e2e/src/e2e/ssr_dsd.cy.ts`
> (single subtree, server-node identity after an action, class re-applied).
> The spec FAILS when either half is removed. §4.3 LANDED at render time,
> not compile time: Hologram injects a no-op default `init/3`, so the missing
> mirror cannot be seen from exports. `Render` turns the resulting KeyError
> into an ArgumentError that names the key and the one-line fix. §4.4 LANDED:
> conformance SSR-01/02 run on Tier 2 (adapter `ssr` fixture parses the server
> markup with `setHTMLUnsafe` before upgrade, then checks server-node
> identity after an action). Both fail with adoption removed. Still owed: the
> §4.5 complex-component checks. Only the HoloKit Counter is exercised today.

## 1. The two questions, answered

**Q1 — can Hologram's SERVER renderer emit a component's shadow-root HTML?**
YES, with public 0.10.1 API only. `Hologram.Template.Renderer.render_dom/3`
fed the component DOM tuple `{`{:component, Module, props_dom, []}`}` with a
`cid` prop takes the same clause a page render takes at `<Component cid=…/>`:
props are cast/defaults applied, `init/3` runs, the template renders to an
HTML string, and the component struct lands in a registry keyed by cid:

```elixir
props_dom = [
  {"label", [expression: {"pings"}]},
  {"step", [expression: {2}]},
  {"cid", [expression: {"tssr_dsd"}]}
]
{html, registry, _server} =
  Renderer.render_dom({:component, Counter, props_dom, []}, %Env{}, %Server{})
# html  = "<div class=\"tsr-counter\" data-cy=\"holo-counter-root\">…count…0…</div>"
# registry = %{"tssr_dsd" => %{module: Counter, struct: %Component{state: %{count: 0, step: 2, …}}}}
```

`$click` bindings are `$`-prefixed attrs the server renderer DROPS (client
binds them at patch), so the emitted HTML is exactly shadow-root-suitable
markup. The cid never appears in the markup; the client's own mount cid owns
event routing after hydration — no cid agreement needed across the boundary.

**Author-contract finding (upstream-shaped, not a blocker):** 0.10.1 splits
`init/2` (CLIENT init) from `init/3` (SERVER init). The `HoloKit` fixtures —
Counter included — define only `init/2`, so a naive server render of them
KeyErrors on state the client init would have created (`{@count}`). The DSD
adaptation is one mirroring line per component:

```elixir
def init(props, component, server), do: {init(props, component), server}
```

This is exactly Lit's SSR lifecycle-subset row (#156): server-side init must
compute what `render` needs; client-only side effects stay client-only.

**Q2 — can the Tier-2 client runtime hydrate onto that pre-rendered shadow
root instead of mounting from scratch?** PROVEN, with two mount-time deltas.
Declarative shadow roots work with the element as shipped TODAY:
`element.mjs #mount` already guards `if (!this.shadowRoot) attachShadow(...)`,
so a browser-attached DSD root is picked up without throwing. What the STOCK
mount then does, though, is mount-from-scratch — measured (variant A):
`mountComponent` creates its own empty `div[data-tessera-holo-host]` and appends
it, leaving the server subtree as a dead sibling — shadow child count 2,
visibly duplicated content.

Hydration (variant B) = adopt the server host instead of creating one:

```js
// mountComponent's first patch is already the adoption mechanism:
//   instance.patch(toVNode(instance.hostDiv), vnode)
// Swap WHICH div becomes hostDiv — the stock interpreter/renderer/event
// pipeline then morphs the REAL server DOM.
const existing = shadowRoot.querySelector("[data-tessera-holo-host]"); // server div
// (prototype hijacked document.createElement for the mount call; production
//  = a host-selection option in mountComponent / element #mount)
```

**The blocker the prototype surfaced (and the reason the spike was worth
running):** adoption alone still REPLACED the whole subtree — node identity
lost at the first patch. Root cause is snabbdom's `toVNode`: it bakes `id` +
every `class` token INTO the vnode `sel` (`"div.tsr-counter"`), while
Hologram's client `Renderer` builds plain-tag sels with `class` in
`data.attrs`. `isSameVnode` fails (`"div.tsr-counter" !== "div"`) and patch
swaps the old node out. Fix = normalize the adopted tree so sels match —
the spike stripped `class`/`id` attributes from the server subtree before
adoption (toVNode then produces plain sels; the attributes module re-applies
class from the incoming vnodes during the morph). A production version should
normalize the VNODE tree after `toVNode` (move `sel`'s `#id`/`.classes` into
`data.attrs`) instead of touching DOM. Consequence worth recording: this is
also why upstream Hologram's own page "hydration" (`toVNode(documentElement)`
+ patch) replaces classed subtrees rather than morphing them.

After normalization, every hydration property held in a real browser (Cypress,
Electron), driving the UNMODIFIED develop shim + bundles built from develop:

- single subtree after mount (no duplication); host div is the server div;
- root div + count span are the SAME DOM nodes after first patch, after two
  action morphs (`+`/`-` clicks: count 0→2→0 on server-created buttons), and
  after a prop update (`setProps({label})` morphs the label span text);
- `class` re-applied by the attributes module (`"tsr-counter"`);
- the emit bridge works on the hydrated instance: `dispatchAction("increment")`
  → `count-changed` CustomEvent `{count: 2, delta: 2}` crossing the shadow
  boundary (action queue async — asserted with a retried `cy.window().should`).

## 2. Evidence artifacts (spike scratch, worktree `ssr-spike`, uncommitted)

- `demo/hologram_app/.tmp/ssr_probe.exs` — defines the init/3 mirror
  (`HoloKit.Components.DsdCounter`, throwaway redefinition in-script), runs
  `render_dom`, emits the two pages below.
- `demo/holo_element/ssr-spike/index.html` — variant A: stock
  `defineElement` mount over a DSD-attached root (duplication measured).
- `demo/holo_element/ssr-spike/hydrate.html` — variant B: host adoption +
  sel normalization via `mountComponent` directly.
- `demo/e2e/src/e2e/ssr_dsd_spike.cy.ts` — 2 specs, **both passing** (the
  assertions listed above). Serve with `PORT=5591 node demo/holo_element/serve.mjs`.
- Bundles: `mix tessera.compile_component HoloKit.Components.Counter --out
  demo/holo_element/dist/tessera-holo-spike` (built from the worktree's
  `priv/tessera_holo/src` at 1d0501b — stock shim, untouched).

## 3. Row outcomes (lit-parity §2.12, Tier 2)

- **#155 DSD: spike-proven** — server-rendered `<template shadowrootmode>`,
  browser attach, runtime adopt-and-morph. Not yet shipped.
- **#156 SSR lifecycle subset: spike-proven** — `init/3` is the server subset;
  mirroring `init/2` is the author contract (compiler can enforce/warn).
- **#157/#158 hydration + hydrate(): spike-proven shape** — host adoption +
  vnode-sel normalization = the `hydrate()` equivalent; no Lit machinery.
- **#154/#160/#162: confirmed N/A** — Hologram's own Elixir renderer replaces
  `@lit-labs/ssr` entirely (render_dom IS the collectResult equivalent).
- **#159 streaming, #163 defer-hydration, #164 framework SSR integrations,
  #165 template-shadowroot polyfill: still open** — not exercised by this
  spike; none block the parity milestone (accept-with-note).

## 4. What production would require (the GO work list)

1. **Shim (additive, small):** `mountComponent` host selection — adopt an
   existing `[data-tessera-holo-host]` in the shadow root before creating one
   (or an explicit `hydrate: true` option); plus a post-`toVNode` vnode-sel
   normalization walk (move `#id`/`.classes` into `data.attrs`). ~dozens of
   lines in `priv/tessera_holo/src/tessera_holo.mjs` / `element.mjs`.
2. **Elixir SSR entry:** a `Noizu.Tessera.Hologram.Render` helper wrapping
   `render_dom` + the DSD `<template shadowrootmode="open"><div
   data-tessera-holo-host>…</div></template>` emission, with prop serialization
   parity (scalar props proven in-spike; `:list`/`:map` props need Encoder
   parity with the `tsr-props` JSON path).
3. **Author contract enforcement:** compile-time check/warn that a
   DSD-exported component defines `init/3` mirroring `init/2` (else the server
   render KeyErrors) — belongs in the 3f spec layer, not the shim.
4. **Conformance:** SSR family cases in 4b's harness (DSD attach + hydration
   identity + action-after-hydrate), against the real mount path.
5. **Known unexercised risk:** complex components (controlled form inputs,
   focus preservation, slot markers from 3e — server-side slot MARKER HTML vs
   `rewriteSlotVnodes` adoption interaction), multi-root component templates
   (host wrapper carries them — shape proven, per-component check needed),
   stateful-init divergence (server state ≠ client init is morphed on first
   patch — Lit-equivalent behavior, document it).

None of these are research anymore — each is a bounded engineering task with
the mechanism already demonstrated end-to-end in a browser.

## 5. Non-blocking caveats

- The prototype's `document.createElement` hijack and DOM class-stripping are
  spike scaffolding; production lands the equivalents inside the shim (§4.1)
  and MUST re-run the full Tier-2 e2e (16+ tests) — other briefs are actively
  changing the same files (3f/extension.ex lanes); coordinate the shim edit
  as its own PR after those land.
- Verdict scope = Tier 2. Tier 1 `@lit-labs/ssr` (row #154 Tier-1 column) was
  not probed here; that lane remains "plausible, unproven".
