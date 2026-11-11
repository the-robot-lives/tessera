# Gap-Acceptance Ballot — Lit features tessera consciously does NOT implement

**Status: DRAFT — finalize after the in-flight briefs land (2e takeover-chain, 2f Tier-1 forms, 3f Tier-2 canonical macro; 4c SSR spike gated by U8).**
Recomputed against `docs/notes/lit-parity.md` §2 at `develop` `1d0501b` (post-1b/1c/1d/2a/2b/2c/2d/3c/3d/3e + D-GAL flips). This doc is the durable record for **U7 (user ballot)**; nothing here is final until the ballot is recorded (session ledger + `applied:` here).

## 0. How the set was recomputed (the "43" is the audit's figure — the live count is 41)

The audit band was ≈43 universal ❌ rows (❌ in **both** Tier 1 and Tier 2). Since then:

- **#23 / #31 reflect** and **#6 shouldUpdate** were listed in the audit's accepted band but are now **CLOSED in Tier 1 by brief 1c** (`reflect: true`, `should_update` DSL — C-02/C-09/C-15 WTR). Tier 2 remains ❌ (one-sided, not ballot material).
- Rows closed in ≥1 tier by landed briefs are no longer universal — see §4 (provenance table).

**Actual post-flip ballot set: 41 universal ❌ rows**, classified: **34 ACCEPTED-WITH-HATCH · 7 ACCEPTED-DESIGN-CHOICE · 0 CLOSED within the ballot set** (closures are listed in §4 for provenance). **6 forms rows + 12 SSR rows sit in §5 as PENDING-FINAL** — do not ballot them yet.

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

## 2. ACCEPTED-DESIGN-CHOICE (7 rows in the ballot set + 2 outside it)

Not gaps — deliberate architecture. Ballot here = confirm the choice stands.

| # | Feature | Class rationale | Alternative (the chosen mechanism) |
|---|---------|-----------------|------------------------------------|
| 178 | Signals @lit-labs/signals | **Built-in reactivity chosen**: Tier 1 compiles to Lit's reactive-properties core; Signals is an alternative state model, not an additive feature | `state`/attr props + 1c lifecycle; Tier 2: Hologram state → `setProps` |
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
| #194 CEM | **D-GAL** (Phase-1 column) | `Codegen.cem/1`, `mix tessera.cem` / `mix tessera.gen.gallery` |
| #1/#2/#21/#29/#37/#49/#50/#53/#55/#197 P0 core | pre-existing spike goldens | matrix §2 |

## 5. PENDING-FINAL — do NOT ballot these until the briefs land

| Rows | Waiting on | Current state |
|---|---|---|
| **#144 formAssociated, #145 ElementInternals, #146 setValidity, #147 setFormValue, #148 formResetCallback, #149 formDisabledCallback** (Tier-1 side) | **brief 2f (in flight)** | Tier 2 ✅ since 3e (manifest-declared, gated attach, subclass seams — FM-01…03). Tier 1 ❌/🔌: no `form_associated` DSL, no `static formAssociated` emission, no internals accessor. 2f flips #144/#145/#148/#149 per its acceptance criteria (internals accessor also covers #146/#147). **Mark pending-final, not accepted.** |
| **#144 Tier-2 declaration path** | **brief 3f (in flight)** | 3e ships the manifest/fixture hook `__tsr_form_associated__`; 3f moves it to the spec DSL (`form_associated`) — row already ✅, mechanism finalization only. |
| **#154–#163, #165 SSR family** (+ #164 ❓) | **brief 4c (GATED by U8, not started)** | Tier 1 uniformly 🔌-unproven; Tier 2 ❌ except #161 isServer ✅. Per brief 4c: **prove → flip + add conformance cases; unproven in time-box → accept as documented gap (then move into §1/§2 of this doc)**. Never a release blocker. |
| Tag-takeover / canonical-macro surfaces (#139/#140 mixins, contract X-19/X-21/X-16) | **2e + 3f (in flight)** | Not matrix ❌ rows (🔌 subclassing today) — listed so the ballot doesn't over-claim extension parity before those land. |

## 6. Ballot procedure (U7)

1. Finalize after 2f/3f land and 4c resolves (or is declined): recompute §0, move forms/SSR rows out of §5 into their final class, re-flip matrix §3 counts **then** (matrix is not touched by this draft — per brief 4a the §3 recount lands with finalization).
2. User confirms per category (not per row): §1 hatch-sufficient · §2 design choices stand · §3 exclusion rule holds · §5 dispositions.
3. Record answers in the session ledger and mirror them here under each section (`**A:**` lines appended, never rewritten).
