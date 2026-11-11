# Gap-Acceptance Ballot — Lit features tessera consciously does NOT implement

**Status: FINAL-FOR-BALLOT (2026-11-12)** — 2e/2f/4c are resolved (§4 provenance + §5 final dispositions); **brief 3f is a FOLLOW-UP to the Tier-1 parity declaration** and its rows stay marked PENDING 3F below. Recomputed against `docs/notes/lit-parity.md` §2 at `develop` `477d157` (post-2f; Tier-1 parity declared 2026-11-12). This doc is the durable record for **U7 (user ballot)**; nothing here is final until the ballot is recorded (session ledger + `applied:` here). **Owner per-category sign-off: OPEN** (§6).

## 0. How the set was recomputed (final 2026-11-12 — the audit's figure was "43"; the draft counted 41; the live set is 40)

The audit band was ≈43 universal ❌ rows (❌ in **both** Tier 1 and Tier 2). Recount history:

- **#23 / #31 reflect** and **#6 shouldUpdate** were listed in the audit's accepted band but are now **CLOSED in Tier 1 by brief 1c** (`reflect: true`, `should_update` DSL — C-02/C-09/C-15 WTR). Tier 2 remains ❌ (one-sided, not ballot material).
- Rows closed in ≥1 tier by landed briefs are no longer universal — see §4 (provenance table).
- **Why 40, not the draft's 41: #178 Signals is one-sided at the final recount** (Tier 1 ❌ / Tier 2 🔌 — the Tier-2 cell's host-side escape, "host may run @lit/signals outside; compute → setProps", was already in the matrix when the draft counted 41). It moves OUT of the ballot set into §3's one-sided band; its design-choice rationale stays recorded in §2 for provenance.
- **Forms (#144–#149) and the SSR family (#154–#165) are resolved out of pending**, not balloted: forms landed on both tiers (2f/3e — §4), SSR carries the 4c GO-conditional dispositions (§5).

**FINAL ballot set (2026-11-12, scripted recount of live §2 @ `477d157`): 40 universal ❌ rows — 34 ACCEPTED-WITH-HATCH · 6 ACCEPTED-DESIGN-CHOICE · 0 CLOSED within the ballot set** (closures are listed in §4 for provenance).

## 1. ACCEPTED-WITH-HATCH (34 rows)

Not implemented in the DSL; reachable through a sanctioned seam. Hatches: **`behaviors.add`** (EXTENSION-CONTRACT §6.5 — connect/disconnect lifecycle, element access, unsubscribe), **TesseraElement / TesseraHoloElement subclassing** (§6.6), **built-in reactivity + lifecycle hooks** (1c/3c), **host-side JS** (hand-written Lit/plain-DOM outside the generated element).

| # | Feature | Why accepted (1-line) | Sanctioned alternative |
|---|---------|----------------------|------------------------|
| 15 | `scheduleUpdate` | Scheduler customization — codegen owns update scheduling; authoring a scheduler is out of subset | Subclass TesseraElement (§6.6) and override; host-side control loop |
| 25 | `@property({hasChanged})` | Custom change-fn impossible in the restricted Elixir subset (1c deliberately excluded it) | `should_update` render gate (1c); subclass defines its own accessor pair with `hasChanged` |
| 26 | `@property({noAccessor})` | Niche option — tessera properties are already plain accessor-less reactive entries | Subclass + own `Object.defineProperty`; attribute observation unchanged |
| 27 | `@property({useDefault})` | Attribute-removal default-reset semantics niche; constructor defaults exist (1c) | Reset via action → state default; subclass override of `attributeChangedCallback` |
| 46 | Element expression `${directive()}` | No directive-part position in templates; only the sanctioned directive set (1d) reaches parts | The four 1d directives in child position; `behaviors.add` for imperative child-node insertion |
| 48 | `noChange` sentinel | Directive-internal only; no author-facing sentinel needed | `should_update` returning false freezes the render (1c) — the author-level equivalent |
| 51 | `literal`` (static exprs) | Dynamic tag names break static codegen + subset escaping model | Host-side template JS (hand-written `html```); `unsafeHTML`-class hatch (see #74) |
| 52 | `unsafeStatic()` | Same — dynamic tag names; deliberately escaped templates are a security feature (§10) | Host-side JS escape hatch; never via generated code |
| 64 | `cache` directive | Template caching is lit-html/Hologram-internal; authors cannot select cache policy at binding granularity | Structural: stable `{%for}` + keyed reconciliation is a Tier-1 gap by design; subclass re-mount control |
| 65 | `guard` directive | No memo gate at binding granularity; recompute is cheap in immutable state | `should_update` element-granularity gate (1c) |
| 66 | `live` directive | Live-DOM comparison implies mutable external DOM ownership — conflicts with renderer-owned parts | `behaviors.add` writes DOM imperatively; next render wins (documented semantics) |
| 67 | `keyed` directive | Reconciliation is renderer-owned (lit-html template caching T1; snabbdom T2) — author-keyed parts not modeled | `{%for}` over a stably-ordered collection; subclass controls mount order |
| 71 | `asyncAppend` | Async iterables in templates are out of the synchronous subset | Host async → `emit`/state update → conditional render (the sanctioned async pattern, #173) |
| 72 | `asyncReplace` | Same — no async in template subset | Same as #71 |
| 73 | `templateContent` | No `<template>` content cloning in either renderer | Static markup + conditional rendering; host-side DOM |
| 75 | `unsafeSVG` | Raw string injection deliberately excluded from the escaped template grammar | `svg``` passthrough in Tier 1 templates; host-side `innerHTML` at author risk (§10) |
| 76 | `unsafeMathML` | Same injection class as #75 | `mathml``` via host-side Lit (#40 hatch); raw markup passthrough |
| 93 | `unsafeCSS` | Deliberate: author CSS is static and escaped through the styles DSL (1b) | Shared style modules `{:shared, "path"}` (1b); theming via `--tsr-<tag>-*` (§7) |
| 118 | `@eventOptions` | No template-level listener options in the `$event` binding grammar | `behaviors.add` attaches listeners with full options on connect |
| 121 | Typed CustomEvents | Struct/event classes rejected by the expression subset; detail is a plain map | `emit/2` typed-by-contract (CEM documents detail schema, D-GAL); host-side `class X extends CustomEvent` |
| 130 | `hostUpdate` controller hook | No controller host; the update-pre phase is author-reachable via lifecycle DSL instead | `will_update` (1c) / `willUpdate` shim projection (3c) cover the pre-render slot |
| 131 | `hostUpdated` controller hook | Same — no controller host | `updated` (1c) / `updated(changed)` (3c) cover the post-render slot |
| 166 | Context protocol (@lit/context) | Two cross-boundary channels already contracted; a third would fragment the model | **Bus seam `setBus`/`BusClient`** (contract) + composed CustomEvents (§6.4 pipeline) |
| 167 | `createContext` | Same as #166 | Bus seam; host-side `@lit/context` on hand-written wrappers |
| 168 | `@provide` | Same | Bus seam provider side; subclass `connectedCallback` registers a ContextProvider |
| 169 | `@consume` | Same | Bus seam consumer side; props-down via `attr=` bindings is the default idiom |
| 170 | ContextProvider controller | Controller API needs a controller host; bus seam is the channel | `behaviors.add` + `new ContextProvider(host, …)` (imperative, element-granularity) |
| 171 | ContextConsumer controller | Same | `behaviors.add` + `new ContextConsumer(…)`; or props-down |
| 172 | ContextRoot | Tier-2 boundary already crossed via Hologram server state + bus; no Lit context tree exists | Bus seam (Hologram holds app state server-side — the original context use-case) |
| 175 | Task autoRun/manual | No Task object to configure | Host-side async action + `dispatchAction` sequencing (#173 pattern) |
| 176 | Task abort `{signal}` | Aborted-fetch plumbing is imperative JS territory | `behaviors.add` owns an AbortController across connects; disconnect aborts |
| 177 | Task chaining (output → args) | No reactive-task graph in the subset | Action chains in Elixir: action → async → set state → dependent action |
| 186 | `useController()` (React) | Needs both a React host and a Lit controller host | Wrap elements as plain custom elements (react.html pattern, #185) |
| 187 | Localization @lit/localize | No Lit template layer to localize at runtime | Elixir-side i18n at author time (module attributes / app gettext before template emission) |

## 2. ACCEPTED-DESIGN-CHOICE (6 rows in the ballot set + 2 outside it; #178 moved out one-sided — see §0)

Not gaps — deliberate architecture. Ballot here = confirm the choice stands.

| # | Feature | Class rationale | Alternative (the chosen mechanism) |
|---|---------|-----------------|------------------------------------|
| 178 | Signals @lit-labs/signals | **Built-in reactivity chosen**: Tier 1 compiles to Lit's reactive-properties core; Signals is an alternative state model, not an additive feature. *(Not in the final ballot set — one-sided at the 2026-11-12 recount: Tier 2 🔌 host-side escape. Kept here for provenance.)* | `state`/attr props + 1c lifecycle; Tier 2: Hologram state → `setProps` |
| 179 | `signal()` | Same family — no template integration by design | Reactive props (T1) / tsr-state + `tsr-state-change` (§6.2) |
| 180 | `computed()` | Derived values are Elixir functions in render, not reactive graph nodes | Pure function calls in templates / assigns |
| 181 | SignalWatcher mixin | Incompatible with the compiled class by design; mixin slot is taken by TesseraElement | Subclass hooks (§6.6) |
| 182 | `watch()` directive | Signals-internal template bridge | `will_update`/`updated(changed)` hooks |
| 183 | Signals `html` tag | Forking the template tag contradicts single-runtime output | lit-html `html``` (T1) / Hologram templates (T2) |
| 184 | signal-utils (SignalArray, @signal) | Ecosystem of the rejected model | Immutable-data updates: replace the value, not the collection |
| 195 | Experimental decorators | **Decorator-free output by design** (golden fixture) — static-properties only; not a universal ❌ (Tier-2 wrapper 🔌) | `static properties` emission (1c attribute/reflect/type opts) |
| 196 | TC39 decorators | Same — "either decorator mode" is false; the compiler never emits decorators | Same as #195; hand-written wrappers may use whatever they compile to |

## 3. One-sided ❌ rows — NOT balloted (a hatch is already live in the other tier)

Rows ❌ in exactly one tier are excluded from the ballot; each is already answered by the other tier or an in-tier hatch. Representative band (full cells in §2 of the matrix): #35 custom getter/setter, #40 mathml, #62 range, #63 repeat, #70 until, #74 unsafeHTML, #77/#78 custom/async directives (behaviors.add), #86 :host-context, #94/#95/#96 shadowRootOptions/delegatesFocus/light-DOM, #112 closed root, #117 cancelable, #119/#120 handleEvent/conditional listener, #124 dispatch-after-render, #139/#140 mixins (subclassing), #154–#165 SSR (see §5), #173/#174 Task (host async pattern), #185 React wrapper (manual custom-element use), #188–#193 ecosystem, #198/#199 .d.ts/TagNameMap, #201 warning suppression.

## 4. CLOSED-BY-PARITY (provenance — rows the audit banded as gaps; briefs landed)

| Rows | Closed by | Evidence |
|---|---|---|
| #6 shouldUpdate, #7 willUpdate, #10 firstUpdated, #11 updated, #22 attribute, #23/#31 reflect, #34 changedProperties, #43 ?attr | **1c** (Tier 1) | C-02/C-09/C-10/C-13/C-15, T-03, LC-01…04 WTR |
| #47 nothing, #56 classMap, #57 styleMap, #68 ifDefined | **1d** (Tier 1) | D-01/D-02/D-06/T-06 WTR |
| #79/#81/#82/#83/#84/#85/#87/#90/#92 (+ #91/#98) styles DSL | **1b / styles-dsl** (Tier 1) | S-01…S-06, X-14 WTR |
| #12 updateComplete, #18 hasUpdated, Tier-2 #7/#10/#11/#12/#34/#220 lifecycle | **3c** (Tier 2) | C-13/C-14, LC-02/LC-03/LC-04 Cypress |
| #99/#100/#101/#107/#108/#109/#142 slots | **3e** (Tier 2) | SD-01…SD-04 Cypress |
| #144–#149 forms — **Tier 2 side** | **3e** (Tier 2) | FM-01…FM-03 Cypress |
| #144–#149 forms — **Tier 1 side** | **2f** (Tier 1) | FM-01…FM-03 WTR (shared bodies) + X-12/§8.4 pin gate; ExUnit DSL/codegen; goldens byte-stable |
| #194 CEM | **D-GAL** (Phase-1 column) | `Codegen.cem/1`, `mix tessera.cem` / `mix tessera.gen.gallery` |
| #1/#2/#21/#29/#37/#49/#50/#53/#55/#197 P0 core | pre-existing spike goldens | matrix §2 |

## 5. RESOLVED pending rows — final dispositions (2026-11-12)

The rows §0 held out of the ballot are resolved as follows; none is balloted.

| Rows | Held on | Final disposition |
|---|---|---|
| **Forms #144–#149 (both tiers)** | ~~2f~~ — **LANDED** | Tier 2 green since 3e; Tier 1 landed with **2f**: `form_associated` spec DSL (additive-derived inheritance) → put-if-declared manifest/CEM key → `static formAssociated = true` in all three emission templates; constructor-gated `ElementInternals` exposed as `el.internals` (§6.7 negative pinned); FM-01…FM-03 + X-12 run as SHARED bodies, green on both harnesses (WTR + Cypress). Both tiers ✅ — see §4. |
| **#154–#163, #165 SSR family** (+ #164 ❓) | ~~4c~~ — **RESOLVED: GO-conditional** | Spike 4c verdict: **proven in a spike; production work owed — NOT "done"** (`docs/notes/ssr-dsd-spike.md`). Tier 2: #155/#156/#157/#158/#160 are **⚠ spike-proven, unshipped** (server `render_dom` DSD emission + browser attach + hydrate-by-adoption proven end-to-end in a real browser; the §4 delta list — `mountComponent` host adoption, snabbdom vnode-sel normalization, init/3 author-contract enforcement, SSR conformance cases — is the owed production work). #154/#162 confirmed **N/A by construction** on Tier 2 (`render_dom` IS the native equivalent of `@lit-labs/ssr`/`collectResult`); #163/#165 **accepted-with-reason** (defer-hydration trivially addable beside the shim delta; template-shadowroot polyfill wraps the same host-adoption mount). #159 streaming + #164 framework integrations stay open, explicitly non-blocking (#164 keeps the matrix's only ❓). Tier 1 SSR remains 🔌-unproven across the family — out of 4c's scope, no Tier-1 SSR claim is made. |
| **#144 Tier-2 declaration path; tag-takeover / canonical-macro surfaces (#139/#140 mixins, X-16/X-19/X-21 on Tier 2)** | **3f — PENDING 3F (FOLLOW-UP)** | 2e landed the Tier-1 half (takeover chains + `extendElement`; X-19/X-21 green on the WTR suite). **Brief 3f (in flight) is a FOLLOW-UP to the Tier-1 parity declaration** and owns the Tier-2 leg: the `form_associated` spec declaration replacing 3e's `__tsr_form_associated__` fixture hook, Tier-2 reuse of the canonical `use Vendor.Element` macro, X-16/X-19 exercised on Tier 2, the cross-runtime CompileError decision — plus the X-16 shared registry case (wired in the same `x_extension.mjs`). Where 3e/2e already carry a row it is ✅; what's pending is the mechanism/Tier-2 leg, not the capability. |

## 6. Ballot procedure (U7)

1. Finalize after 2f/3f land and 4c resolves (or is declined): recompute §0, move forms/SSR rows out of §5 into their final class, re-flip matrix §3 counts **then** (matrix is not touched by this draft — per brief 4a the §3 recount lands with finalization).
2. User confirms per category (not per row): §1 hatch-sufficient · §2 design choices stand · §3 exclusion rule holds · §5 dispositions.
3. Record answers in the session ledger and mirror them here under each section (`**A:**` lines appended, never rewritten).

**Finalization status (2026-11-12):** step 1 is DONE — §0 recomputed at `477d157` (**40 rows**), forms/SSR dispositions recorded (§5), and the matrix §3 recount landed with the Tier-1 parity declaration (`lit-parity.md` §3.1). Step 2 is **OPEN — owner per-category sign-off owed**: §1 hatch-sufficient · §2 design choices stand (6 ballot rows) · §3 exclusion rule holds · §5 dispositions. Nothing here is final until the ballot is recorded (session ledger + `**A:**`/`applied:` lines).
