# Lit Feature Inventory & Tessera Parity Matrix

> Generated: 2026-11-11 | Session: `8cab005e-11cf-42b8-8a29-9aff00f6bec0`
>
> Post-0.2.0 changes on `develop` (2026-11-12). The rows below are NOT yet re-scored; counts are recomputed at the next release:
> - #96 `createRenderRoot` (light DOM): **Tier 1 implemented.** `use Noizu.Tessera.Component, render_root: :light` emits `createRenderRoot() { return this; }` and adopts styles additively into the root node. Slots are refused at compile time, and `:host` rules don't match in light DOM. Covered by `js/test/light_dom.test.mjs`. Tier 2 is unchanged.
> - #63 `repeat`: **Tier 1 implemented.** The keyed loop `{%for row <- @rows, key: row.id}` lowers to `repeat(items, keyFn, templateFn)` and imports `lit/directives/repeat.js`. Reorders move keyed nodes, covered by `js/test/repeat.test.mjs`, which fails when lowered to `.map`. Unkeyed `{%for}` stays `Array.map`.
> - #155–#158 SSR/DSD: **Tier 2 shipped** (`Noizu.Tessera.Hologram.Render`, shim hydration; conformance SSR-01/02). See `docs/notes/ssr-dsd-spike.md`.
>
> Correction (2026-11-11): matrix corrected against spike code (spike/elixir-to-lit @ 103c776) — Tier 1 column audited row-by-row against the compiled output; Tier 2 cells purged of stale Lit-wrapper framing; see §3 for the tier comparison.
>
> Compares the full Lit 3 feature surface against tessera's three implementation tiers:
> - **Phase 1 (tessera today)**: Hand-written Lit elements beneath an Elixir contract layer.
> - **Tier 1 (spike/elixir-to-lit)**: Compile an Elixir subset directly to Lit element output.
> - **Tier 2 (spike/hologram-runtime-element)**: Host a Hologram component inside a custom element wrapper.

> **PARITY DECLARED — 2026-11-12** (owner decision). Tier 1 declared at `develop` @ `477d157` (brief 2f merged); **extended to Tier 2's extension contract at `1ca9e81`** (brief 3f + the X-02/X-13 shared cases). Released as **0.2.0**.
>
> **What "Tier-1 parity reached" means here:**
> - **P0 author-facing gaps are closed or accepted.** Of the 80 P0 rows, Tier 1 is 51 ✅ / 23 🔌 (sanctioned escape hatch) / 6 ❌ — and every one of those 6 is consciously accepted in `docs/notes/gap-acceptance.md`: context protocol #166–#169 (bus-seam hatch, §1 there), decorator-free output #195 and no `.d.ts` generation #198 (documented non-goals of the compiler).
> - **The extension contract is green, stated precisely:** all of X-01…X-21 have shared, tier-agnostic case bodies in `test/conformance/cases/x_extension.mjs` (X-02/X-13 landed at `1ca9e81`, X-16 shared case with brief 3f). Tier 1 runs the full X family. Tier 2 runs X-16/X-19 (incl. the X-05…X-11 + X-20 base-suite replay on a taken-over tag) since brief 3f; cases the Hologram runtime can't host stay honest adapter-pending (e.g. X-21, per 3f). X-13 on Tier 2 asserts the §6.6 hook chain + reserved surface only: a live attribute change there reaches the render view, not action-visible state (the documented §2.2 "attrs flow one way in" divergence).
> - **Tier 2 rides the same canonical macro** (brief 3f): `use Vendor.Element` drives both tiers through one shared derivation layer; cross-runtime derivation is a pointed CompileError (T2-6); Tier-2 takeover chains are linear (no `super` in Hologram IR — §5.9).
> - **The conformance suite is the gate.** Re-run at `1ca9e81`: Tier-1 WTR conformance FULL lane **55 passed / 0 failed / 26 skipped** (exit 0); fast lane **164 / 0 / 13** (exit 0); Tier-2 `conformance_tier2.cy.ts` **31 passing / 0 failing / 49 pending of 80**.
> - **The remaining gaps are accepted** in `docs/notes/gap-acceptance.md`: **40 universal ❌ rows — 34 accepted-with-hatch · 6 accepted-design-choice** (recount 2026-11-12: #178 Signals is one-sided, Tier 2 🔌; the per-category owner ballot, §6 there, is OPEN).
>
> **What this declaration does NOT claim (still owed):**
> - **Full Tier-2 Lit parity** — Tier 2's extension contract landed (above), but its §2 matrix column is still 30 ✅ / 13 🟡 / 114 🔌 / 64 ❌ / 1 ❓ (+5 ⚠ spike-proven). Tier 2 is a full-Hologram-runtime engine by design, not a Lit re-implementation; its remaining gaps are accepted or hatch-covered in `gap-acceptance.md`.
> - **SSR production** — spike 4c's verdict is **GO-conditional**: DSD emission + hydration are *proven in a spike*; the production deltas (`docs/notes/ssr-dsd-spike.md` §4) are owed, unshipped.
> - **Two open owner questions** — two-layer rename chaining (§5.6) and whether a pinned derived `extension_api` stores the requirement string vs the resolved version.

---

## 1. Lit 3 Feature Inventory

### 1.1 Component Model

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 1 | `LitElement` | `class MyEl extends LitElement {}` | Base class for all Lit components; extends HTMLElement via ReactiveElement | P0 |
| 2 | `ReactiveElement` | `import {ReactiveElement} from 'lit';` | Base class below LitElement; reactive properties + update lifecycle, no template system | P0 |
| 3 | `@customElement` | `@customElement('my-el')` | Registers the class as a custom element with the browser | P0 |
| 4 | `connectedCallback` | `connectedCallback() { super.connectedCallback(); }` | Element inserted into DOM; creates renderRoot, starts first update, notifies controllers | P0 |
| 5 | `disconnectedCallback` | `disconnectedCallback() { super.disconnectedCallback(); }` | Element removed from DOM; pauses reactive update cycle | P0 |
| 6 | `shouldUpdate` | `shouldUpdate(changedProperties): boolean` | Return false to skip the update cycle for this change | P1 |
| 7 | `willUpdate` | `willUpdate(changedProperties)` | Compute derived values before render; runs in SSR | P0 |
| 8 | `update` | `update(changedProperties) { super.update(changedProperties); }` | Calls render() and applies template to DOM; rarely overridden | P1 |
| 9 | `render` | `render(): TemplateResult` | Returns template to render; must be pure, no side effects; runs in SSR | P0 |
| 10 | `firstUpdated` | `firstUpdated(changedProperties)` | Called once after first render; DOM is available | P0 |
| 11 | `updated` | `updated(changedProperties)` | Called after every render; DOM available; setting properties triggers another cycle | P0 |
| 12 | `updateComplete` | `await this.updateComplete` | Promise that resolves when the current update cycle finishes | P0 |
| 13 | `getUpdateComplete` | `async getUpdateComplete(): Promise<boolean>` | Override to await child component updates as well | P1 |
| 14 | `requestUpdate` | `this.requestUpdate()` / `this.requestUpdate('prop', oldVal)` | Manually schedule an update for changes Lit can't detect | P0 |
| 15 | `scheduleUpdate` | `async scheduleUpdate(): Promise<void>` | Override to customize update timing (e.g., rAF, macrotask) | P2 |
| 16 | `performUpdate` | (internal) | Called by the scheduler to execute the update; rarely touched directly | P2 |
| 17 | `addInitializer` | `target.constructor.addInitializer(instance => ...)` | Run code during element construction; used by custom decorators/controllers | P2 |
| 18 | `hasUpdated` | `this.hasUpdated` | Boolean; true after at least one update cycle completes | P1 |
| 19 | `isConnected` | `this.isConnected` | Boolean; true when element is in the live DOM | P1 |

### 1.2 Reactive Properties

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 20 | `@property` | `@property({type: String}) name = '';` | Declares a public reactive property, synced with an HTML attribute by default | P0 |
| 21 | `@property({type})` | `@property({type: Number})` / `String` / `Boolean` / `Object` / `Array` | Built-in type converter for attribute-to-property deserialization | P0 |
| 22 | `@property({attribute})` | `@property({attribute: 'my-prop'})` | Custom attribute name; `false` to disable attribute sync entirely | P0 |
| 23 | `@property({reflect})` | `@property({type: Boolean, reflect: true})` | Write property changes back to the HTML attribute (for CSS selectors, a11y) | P1 |
| 24 | `@property({converter})` | `@property({converter: {fromAttribute, toAttribute}})` | Custom attribute-to-property and property-to-attribute conversion | P1 |
| 25 | `@property({hasChanged})` | `@property({hasChanged: (n, o) => n !== o})` | Custom change detection; default is strict inequality (`!==`) | P1 |
| 26 | `@property({noAccessor})` | `@property({noAccessor: true})` | Prevent Lit from generating its own getter/setter | P2 |
| 27 | `@property({useDefault})` | `@property({type: String, useDefault: true})` | Reset to default when attribute is removed; suppress initial default reflection (3.3+) | P2 |
| 28 | `@state` | `@state() private _active = false;` | Internal reactive state; no attribute; triggers re-render on change | P0 |
| 29 | `static properties` | `static properties = { count: {type: Number} }` | Declarative property definitions without decorators (plain JS) | P1 |
| 30 | Attribute-to-property conversion | automatic per `type` | HTML attribute string parsed to JS type when attribute changes | P0 |
| 31 | Property-to-attribute reflection | `@property({reflect: true})` | JS value written back to attribute; uses `toAttribute` converter | P1 |
| 32 | Attribute name mapping | camelCase property → lowercase attribute by default | `myProp` maps to attribute `myprop` unless overridden | P0 |
| 33 | Boolean attribute semantics | `@property({type: Boolean}) disabled = false;` | Attribute present = true, absent = false; must default to false | P0 |
| 34 | `changedProperties` map | `willUpdate(changedProperties) { changedProperties.get('prop') }` | `Map<string, unknown>` of old values for all changed properties | P0 |
| 35 | Custom getter/setter with `@property` | `@property() set foo(v) { this._foo = v; } get foo() { return this._foo; }` | Add validation/transformation to property access while preserving reactivity | P1 |
| 36 | `elementProperties` metadata | `MyElement.elementProperties.get('count')` | Runtime access to declared property options | P2 |
| 37 | Mutation detection (immutable pattern) | `this.items = [...this.items, newItem];` | Replace references to trigger updates; mutations don't schedule | P0 |

### 1.3 Templates

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 38 | `html` tag | `` html`<p>${expr}</p>` `` | Tagged template literal returning `TemplateResult`; parsed once, dynamic parts updated on re-render | P0 |
| 39 | `svg` tag | `` svg`<circle cx="${x}" cy="${y}"/>` `` | Template tag for SVG content inside `<svg>` elements; uses SVG namespace | P1 |
| 40 | `mathml` tag | `` mathml`<mrow>${expr}</mrow>` `` | Template tag for MathML content (Lit 3.2+); uses MathML namespace | P2 |
| 41 | Child expression | `` html`<div>${value}</div>` `` | Inserts primitives, TemplateResults, DOM nodes, arrays, iterables, nothing, noChange | P0 |
| 42 | Attribute expression | `` html`<div class=${cls}></div>` `` | Sets HTML attribute; values converted to string; `nothing` removes attribute | P0 |
| 43 | Boolean attribute expression | `` html`<div ?hidden=${!show}></div>` `` | Prefix `?`; truthy adds attribute, falsy removes it | P0 |
| 44 | Property expression | `` html`<input .value=${val}>` `` | Prefix `.`; passes any JS value (objects, arrays, functions); case-sensitive | P0 |
| 45 | Event listener expression | `` html`<button @click=${handler}></button>` `` | Prefix `@`; auto-binds to component (LitElement); `nothing` removes listener | P0 |
| 46 | Element expression | `` html`<div ${ref(myRef)}></div>` `` | Placeholder for directives in opening tag position | P1 |
| 47 | `nothing` sentinel | `import {nothing} from 'lit';` | Renders no nodes in child position; removes attribute in attribute position | P0 |
| 48 | `noChange` sentinel | `import {noChange} from 'lit';` | Leaves current rendered value unchanged; used inside custom directives | P2 |
| 49 | Conditional rendering (ternary) | `` html`${this.show ? html`<p>Yes</p>` : nothing}` `` | Standard JS ternary inside template expressions | P0 |
| 50 | List rendering (Array.map) | `` html`${this.items.map(i => html`<li>${i}</li>`)}` `` | Standard JS array methods inside template expressions | P0 |
| 51 | Static expressions (`literal`) | `` import {literal} from 'lit/static-html.js'; html`<${literal`button`}>` `` | Dynamic tag/attribute names with template caching; expensive on change | P2 |
| 52 | Static expressions (`unsafeStatic`) | `` import {unsafeStatic} from 'lit/static-html.js'; html`<${unsafeStatic(tag)}>` `` | Like literal but for trusted dynamic strings; XSS risk with untrusted input | P2 |
| 53 | Nested templates | `` html`<div>${html`<span>${text}</span>`}</div>` `` | Templates compose naturally; child expression accepts TemplateResults | P0 |
| 54 | Template functions | `const badge = (user) => html`...`;` | Standalone functions returning TemplateResult; importable across components | P1 |
| 55 | Template result caching | automatic | Static string parts of tagged templates are parsed once and cached per template identity | P0 |

### 1.4 Built-in Directives

| # | Feature | Import | Description | Priority |
|---|---------|--------|-------------|----------|
| 56 | `classMap` | `lit/directives/class-map.js` | Dynamic CSS classes from object `{enabled: true, hidden: false}` | P0 |
| 57 | `styleMap` | `lit/directives/style-map.js` | Inline styles from object `{backgroundColor: 'red'}`; supports CSS custom properties | P0 |
| 58 | `when` | `lit/directives/when.js` | Binary template selection (cleaner ternary) `when(cond, ifTrue, ifFalse)` | P0 |
| 59 | `choose` | `lit/directives/choose.js` | Multi-case template selection (switch-like) | P1 |
| 60 | `map` | `lit/directives/map.js` | Transform iterables without DOM diffing; good for simple lists | P0 |
| 61 | `join` | `lit/directives/join.js` | Interleave separators between items | P1 |
| 62 | `range` | `lit/directives/range.js` | Generate numeric sequences `range(end)` or `range(start, end, step)` | P2 |
| 63 | `repeat` | `lit/directives/repeat.js` | Keyed list rendering with stable DOM identity; reorders existing nodes | P1 |
| 64 | `cache` | `lit/directives/cache.js` | Preserve DOM when switching between templates; caches per template identity | P1 |
| 65 | `guard` | `lit/directives/guard.js` | Skip re-evaluation unless dependencies change (reference equality) | P2 |
| 66 | `live` | `lit/directives/live.js` | Compare against live DOM value instead of last-rendered value (form inputs) | P1 |
| 67 | `keyed` | `lit/directives/keyed.js` | Force DOM replacement when key changes; clears all element state | P2 |
| 68 | `ifDefined` | `lit/directives/if-defined.js` | Set attribute only when value is defined; removes attribute on null/undefined | P0 |
| 69 | `ref` / `createRef` | `lit/directives/ref.js` | Imperative element references via `createRef<T>()` or callback `ref(el => ...)` | P0 |
| 70 | `until` | `lit/directives/until.js` | Placeholder until promises resolve; first resolved value displays | P1 |
| 71 | `asyncAppend` | `lit/directives/async-append.js` | Accumulate values from async iterables | P2 |
| 72 | `asyncReplace` | `lit/directives/async-replace.js` | Show only the latest value from async iterables | P2 |
| 73 | `templateContent` | `lit/directives/template-content.js` | Clone and render an HTML `<template>` element | P2 |
| 74 | `unsafeHTML` | `lit/directives/unsafe-html.js` | Render trusted strings as HTML (XSS risk with user input) | P1 |
| 75 | `unsafeSVG` | `lit/directives/unsafe-svg.js` | Render trusted strings as SVG | P2 |
| 76 | (unsafeMathML) | (pattern, no dedicated directive) | Render trusted strings as MathML via unsafeHTML | P2 |
| 77 | Custom directives | `class MyDirective extends Directive` / `AsyncDirective` | Create reusable template logic with `update(part, props)` and `render(...)` | P1 |
| 78 | Async directives | `class MyAsync extends AsyncDirective { update, render, disconnected, reconnected }` | Directives that maintain async state and respond to DOM connect/disconnect | P2 |

### 1.5 Styles

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 79 | `css` tag | `static styles = css`...`;` | Tagged template literal returning CSSResult; security: only css-tagged strings or numbers allowed | P0 |
| 80 | Static styles (Constructable Stylesheets) | `static styles = css`...`;` | Parsed once per class, shared across all instances via adoptedStyleSheets; no FOUC | P0 |
| 81 | Style array composition | `static styles = [resetStyles, baseStyles, css`...`];` | Compose from multiple CSSResult sources | P0 |
| 82 | Style inheritance | `static styles = [...ParentElement.styles, css`...`];` | Subclass must explicitly include parent styles | P0 |
| 83 | `:host` selector | `:host { display: block; }` | Style the host element itself | P0 |
| 84 | `:host([attr])` | `:host([active]) { border-color: blue; }` | Conditional styling based on host attributes | P0 |
| 85 | `:host(.class)` | `:host(.primary) { background: blue; }` | Conditional styling based on host classes | P0 |
| 86 | `:host-context(.theme)` | `:host-context(.dark-theme) { background: #333; }` | Style based on ancestor context | P1 |
| 87 | `::slotted()` | `::slotted(p) { color: green; }` / `::slotted([slot="header"])` | Style slotted (light DOM) children; direct children only | P1 |
| 88 | `:defined` | `my-element:defined { opacity: 1; }` / `my-element:not(:defined)` | Style before/after custom element registration | P2 |
| 89 | `::part()` (exportparts) | `::part(button) { color: red; }` | Expose named internal parts for external styling | P2 |
| 90 | CSS custom properties | `var(--my-color, fallback)` | Primary theming mechanism; cross shadow boundaries | P0 |
| 91 | CSS custom property naming convention | `--component-name-prop` | Prefix with component name to avoid collisions | P1 |
| 92 | Shared style modules | `export const shared = css`...`;` | Reusable CSSResult exports imported by multiple components | P0 |
| 93 | `unsafeCSS` | `import {unsafeCSS} from 'lit'; css`...`${unsafeCSS(trusted)}`...`;` | Escape hatch for trusted dynamic CSS strings; CSS injection risk | P2 |
| 94 | `shadowRootOptions` | `static shadowRootOptions = {mode: 'open', delegatesFocus: true};` | Options passed to `attachShadow()` | P1 |
| 95 | `delegatesFocus` | `static shadowRootOptions = {delegatesFocus: true};` | Focus is delegated to the first focusable element in the shadow tree | P1 |
| 96 | `createRenderRoot` (light DOM) | `createRenderRoot() { return this; }` | Override to render into light DOM instead of shadow DOM; loses encapsulation | P1 |
| 97 | Design system token pattern | Semantic tokens referencing primitive tokens via CSS custom properties | Two-level token system: primitives (`--color-blue-500`) and semantics (`--color-primary`) | P1 |
| 98 | Theme switching | Override semantic tokens at document level (`.dark-theme { --color-surface: ... }`) | Change theme by toggling CSS custom property values on an ancestor | P1 |

### 1.6 Shadow DOM

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 99 | Default slot | `<slot></slot>` | Unnamed slot; any light DOM children without `slot` attribute assigned here | P0 |
| 100 | Named slots | `<slot name="header"></slot>` | Named slot; matched via `slot="header"` attribute on light DOM children | P0 |
| 101 | Slot fallback content | `<slot name="header"><h2>Default</h2></slot>` | Content displayed when no slotted nodes are assigned | P0 |
| 102 | `@query` | `@query('#input') _input!: HTMLInputElement;` | `querySelector` on renderRoot; cached by default | P0 |
| 103 | `@queryAll` | `@queryAll('.item') _items!: NodeListOf<HTMLElement>;` | `querySelectorAll` on renderRoot | P1 |
| 104 | `@queryAsync` | `@queryAsync('#dynamic') _node!: Promise<HTMLElement>;` | Async querySelector; resolves after render if element not yet available | P2 |
| 105 | `@queryAssignedElements` | `@queryAssignedElements({slot: 'list', selector: '.item'}) _items!: HTMLElement[];` | Elements assigned to a specific slot; optional selector filter | P1 |
| 106 | `@queryAssignedNodes` | `@queryAssignedNodes({slot: 'header', flatten: true}) _nodes!: Node[];` | All nodes (including text) assigned to a slot; optional flatten | P1 |
| 107 | `slotchange` event | `<slot @slotchange=${this._onSlotChange}></slot>` | Fires when assigned nodes change | P1 |
| 108 | `assignedElements()` | `slot.assignedElements({flatten: true})` | Get elements assigned to a slot; flatten recurses into nested slots | P1 |
| 109 | `assignedNodes()` | `slot.assignedNodes({flatten: true})` | Get all nodes (including text) assigned to a slot | P2 |
| 110 | `renderRoot` | `this.renderRoot` | The root node where templates render (shadow root by default, or `this` for light DOM) | P0 |
| 111 | Open shadow root | `shadowRootOptions: {mode: 'open'}` (default) | Shadow root accessible via `element.shadowRoot` | P0 |
| 112 | Closed shadow root | `shadowRootOptions: {mode: 'closed'}` | Shadow root not accessible from outside; rarely used | P2 |

### 1.7 Events

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 113 | `@event` listener | `` html`<button @click=${this._handler}>` `` | Declarative event listener in template; auto-bound to component in LitElement | P0 |
| 114 | `CustomEvent` dispatch | `this.dispatchEvent(new CustomEvent('my-event', {detail, bubbles: true, composed: true}))` | Fire a custom event from the component | P0 |
| 115 | Event `bubbles` option | `{bubbles: true}` | Event flows up the DOM tree; default false | P0 |
| 116 | Event `composed` option | `{composed: true}` | Event crosses shadow DOM boundaries; default false | P0 |
| 117 | Event `cancelable` option | `{cancelable: true}` | `preventDefault()` can cancel; enables veto patterns | P1 |
| 118 | `@eventOptions` | `@eventOptions({passive: true})` on handler | Sets `addEventListener` options for the decorated handler | P1 |
| 119 | Listener `handleEvent` object | `` @click=${{handleEvent: () => ..., once: true}} `` | Object with `handleEvent` method; supports listener options without decorator | P2 |
| 120 | Remove listener with `nothing` | `` @click=${this.active ? handler : nothing} `` | Conditionally remove event listener | P1 |
| 121 | Typed CustomEvents | `class StatusChangedEvent extends Event { ... }` | Subclass Event for type-safe custom events | P1 |
| 122 | `composedPath()` | `event.composedPath()[0]` | Get the actual source element of a composed event | P2 |
| 123 | Bidirectional event pattern | Write to `event.detail.response` from listener; read back in dispatcher | Pattern for request-response via events | P2 |
| 124 | Dispatch after render | `this.prop = val; await this.updateComplete; this.dispatchEvent(...)` | Ensure DOM is updated before firing an event | P1 |
| 125 | External listeners (window/document) | `window.addEventListener('resize', this._boundHandler)` | Listen to external events; clean up in `disconnectedCallback` | P1 |

### 1.8 Reactive Controllers

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 126 | `ReactiveController` interface | `interface ReactiveController { hostConnected?(); hostDisconnected?(); hostUpdate?(); hostUpdated?(); }` | Contract for reusable lifecycle-aware behaviors | P0 |
| 127 | `addController` | `this.addController(controller)` in constructor | Register a controller with the host element | P0 |
| 128 | `hostConnected` | `hostConnected() { ... }` | Called when host is added to DOM; setup observers, timers, listeners | P0 |
| 129 | `hostDisconnected` | `hostDisconnected() { ... }` | Called when host is removed from DOM; teardown listeners, timers | P0 |
| 130 | `hostUpdate` | `hostUpdate() { ... }` | Called before host's `update()` and `render()` | P1 |
| 131 | `hostUpdated` | `hostUpdated() { ... }` | Called after host's `updated()` | P1 |
| 132 | Controller requesting update | `this.host.requestUpdate()` | Controller triggers host re-render by calling `requestUpdate()` on its host | P0 |
| 133 | Multiple controllers | `this._ctrl1 = new Ctrl1(this); this._ctrl2 = new Ctrl2(this);` | A single component can use multiple controllers; no diamond problem | P0 |
| 134 | Composing controllers | Controller class owning other controller instances | Controllers can own other controllers; composes behaviors | P1 |
| 135 | Controller + directive pattern | Controller exposes a `ref()` callback for per-element DOM observation | Controller uses `ref` directive to observe specific DOM within the host | P1 |

### 1.9 Composition

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 136 | Nested components | `<child-el .prop=${val} @event=${handler}></child-el>` | Components render other components in their template | P0 |
| 137 | Properties down | `.prop=${value}` syntax | Pass data down via properties (not attributes) for complex types | P0 |
| 138 | Events up | `@event=${handler}` syntax | Propagate changes up via CustomEvents | P0 |
| 139 | Mixin pattern | `export const MyMixin = <T extends Constructor<LitElement>>(superClass: T) => class extends superClass { ... }` | Subclass factory sharing properties, methods, and lifecycle hooks | P1 |
| 140 | Mixin with public API (TypeScript) | `declare class Interface { ... }` + mixin return typed as `Constructor<Interface> & T` | Proper type-safety for mixin-added properties | P2 |
| 141 | Mediator pattern | Parent owns shared state; children communicate only through parent events | Pattern for sibling communication without direct coupling | P1 |
| 142 | Slot-based composition | `<slot>` and `<slot name="x">` | Consumers provide light DOM content slotted into component structure | P0 |
| 143 | Mixin vs Controller tradeoff | Controllers preferred for most cases; mixins for adding to public API | Decision guide for choosing composition strategy | P1 |

### 1.10 Forms

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 144 | Form-associated custom elements | `static formAssociated = true;` + `ElementInternals` API | Custom element participates in HTML forms (validation, submission, reset) | P1 |
| 145 | `ElementInternals` | `this.attachInternals()` | Access form association APIs: validity, validationMessage, setFormValue, form | P1 |
| 146 | Form validation | `internals.setValidity(...)` | Set custom validation messages/states | P2 |
| 147 | Form data | `internals.setFormValue(value)` | Set the element's form submission value | P2 |
| 148 | `formResetCallback` | `formResetCallback() { ... }` | Called when the owning form is reset | P2 |
| 149 | `formDisabledCallback` | `formDisabledCallback(disabled) { ... }` | Called when the owning form's disabled state changes | P2 |

### 1.11 Accessibility

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 150 | `delegatesFocus` | `static shadowRootOptions = {delegatesFocus: true};` | Focus delegated to first focusable element in shadow tree | P1 |
| 151 | ARIA attribute reflection | Standard ARIA attributes on host or internal elements | `aria-label`, `role`, `aria-expanded`, etc. on elements in template | P0 |
| 152 | `aria` property reflection | (browser native) | Some ARIA attributes reflect to element properties (browser support varies) | P2 |
| 153 | `eslint-plugin-lit-a11y` | NPM dev dependency | Accessibility linting for Lit templates | P2 |

### 1.12 SSR

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 154 | `@lit-labs/ssr` | `import {render} from '@lit-labs/ssr';` | Server-side rendering of Lit components to static HTML (Node.js) | P1 |
| 155 | Declarative Shadow DOM | `<template shadowrootmode="open">` in SSR output | Server-rendered shadow DOM markup; browsers attach shadow root from this | P1 |
| 156 | SSR lifecycle subset | Only `constructor`, `willUpdate`, `render` run server-side | Components must compute critical state in `willUpdate`, not `updated` | P1 |
| 157 | `@lit-labs/ssr-client` hydration | `import '@lit-labs/ssr-client/lit-element-hydrate-support.js';` | Attaches Lit's reactive system to server-rendered DOM without re-rendering | P1 |
| 158 | `hydrate()` function | `import {hydrate} from '@lit-labs/ssr-client'; hydrate(template, container);` | Hydrate a standalone template into existing SSR'd container | P2 |
| 159 | Streaming SSR | `RenderResultReadable` wrapping render result | Stream HTML to client as components finish rendering | P2 |
| 160 | `collectResult` / `collectResultSync` | Collect SSR output to string | Async (await) or sync (throws on Promises) collection | P2 |
| 161 | `isServer` detection | `import {isServer} from 'lit'; if (!isServer) { ... }` | Guard browser-only APIs during SSR | P1 |
| 162 | VM module isolation | `ModuleLoader` from `@lit-labs/ssr/lib/module-loader.js` | Per-request isolation using Node.js VM modules (production SSR) | P2 |
| 163 | `defer-hydration` attribute | (Lit labs SSR pattern) | Mark elements that should not hydrate immediately | P2 |
| 164 | Framework integrations (SSR) | Astro (`@astrojs/lit`), Eleventy, Next.js (`@lit-labs/nextjs`), Nuxt | Pre-built SSR integrations for popular frameworks | P2 |
| 165 | `template-shadowroot` polyfill | `@webcomponents/template-shadowroot` | Polyfill Declarative Shadow DOM for older browsers | P2 |

### 1.13 Lit Labs / Ecosystem Packages

| # | Feature | Package | Status | Description | Priority |
|---|---------|---------|--------|-------------|----------|
| 166 | Context protocol | `@lit/context` | Stable | Provide/consume values across shadow boundaries via W3C Community Group protocol | P0 |
| 167 | `createContext` | `@lit/context` | Stable | Create a context key: `createContext<T>(key)` with string or Symbol | P0 |
| 168 | `@provide` decorator | `@provide({context: myCtx}) @property() value;` | Provider decorator; reactive when combined with @property | P0 |
| 169 | `@consume` decorator | `@consume({context: myCtx, subscribe: true}) @property() value;` | Consumer decorator; optional subscription for reactive updates | P0 |
| 170 | `ContextProvider` controller | `new ContextProvider(host, {context, initialValue})` | Imperative context provider; supports `setValue()` and force-notify | P1 |
| 171 | `ContextConsumer` controller | `new ContextConsumer(host, {context, subscribe, callback})` | Imperative context consumer with callback | P1 |
| 172 | `ContextRoot` | `new ContextRoot().attach(document.body)` | Late provider support; re-dispatches unsatisfied requests when new providers appear | P2 |
| 173 | Task | `@lit/task` | Stable | Async operation manager with INITIAL/PENDING/COMPLETE/ERROR status | P1 |
| 174 | `Task` class | `new Task(host, {task, args, autoRun})` | Runs async function; tracks status; renders via `.render({initial, pending, complete, error})` | P1 |
| 175 | Auto-run vs manual | `autoRun: true` (default) or `autoRun: false` + `.run()` | Auto-runs when args change; manual for user-triggered operations | P1 |
| 176 | Task abort signal | `{signal}` in task function | Previous runs auto-abort when args change; `signal.throwIfAborted()` | P1 |
| 177 | Task chaining | Output of one task feeds `args` of another | Compose dependent async operations | P2 |
| 178 | Signals | `@lit-labs/signals` | Labs | TC39 Signals Proposal integration; reactive data structures for shared observable state | P1 |
| 179 | `signal()` | `const count = signal(0); count.get(); count.set(1);` | Mutable state signal; get/set API | P1 |
| 180 | `computed()` | `const doubled = computed(() => count.get() * 2);` | Derived signal; auto-tracks dependencies | P1 |
| 181 | `SignalWatcher` mixin | `class MyEl extends SignalWatcher(LitElement) { ... }` | Auto-updates component when any signal read during render changes | P1 |
| 182 | `watch()` directive | `html`<p>${watch(count)}</p>`` | Per-binding signal update; only that binding re-renders | P2 |
| 183 | Signals `html` tag | `import {html} from '@lit-labs/signals';` | Auto-applies `watch()` to signal values; no `.get()` needed | P2 |
| 184 | `signal-utils` | `signal-utils` (companion) | Observable collections (`SignalArray`) and `@signal` class decorator | P2 |
| 185 | React wrapper | `@lit/react` | Stable | `createComponent({tagName, elementClass, react, events})` for React integration | P1 |
| 186 | `useController()` hook | `@lit/react/use-controller.js` | Adapt Lit reactive controllers for React function components | P2 |
| 187 | Localization | `@lit/localize` | Stable | Runtime or transform-mode localization; `msg()` for translatable strings | P2 |
| 188 | Virtualizer | `@lit-labs/virtualizer` | Labs | Virtual scrolling for large lists; renders only visible items | P2 |
| 189 | Motion | `@lit-labs/motion` | Labs | Animation primitives for enter/leave transitions | P2 |
| 190 | Router | `@lit-labs/router` | Labs | Client-side routing for Lit-based SPAs | P2 |
| 191 | Observers | `@lit-labs/observers` | Labs | Declarative `IntersectionObserver`, `ResizeObserver`, `MutationObserver`, `PerformanceObserver` controllers | P1 |
| 192 | Scoped registry mixin | `@lit-labs/scoped-registry-mixin` | Labs (near graduation) | Per-element custom element registry; avoids global `customElements.define` collisions | P2 |
| 193 | Wrapper generators | `@lit-labs/gen-wrapper-*` | Labs | Generate framework-specific wrappers (React, Angular, Vue, Svelte) from CEM | P2 |
| 194 | Custom Elements Manifest | `@custom-elements-manifest/analyzer` | Stable | Generate `custom-elements.json` manifest from source code; `--litelement` flag | P1 |

### 1.14 Tooling and DX

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 195 | Experimental decorators | `@property()` `@state()` + `tsconfig: experimentalDecorators: true` | Legacy TypeScript decorator mode; smaller output, recommended for production today | P0 |
| 196 | Standard TC39 decorators | `@property() accessor` + TypeScript 5.2+ | Stage 3 decorators with `accessor` keyword; future-proof | P1 |
| 197 | No-decorator API | `static properties = { ... }; customElements.define('tag', cls);` | Plain JS/TS support without decorators | P1 |
| 198 | TypeScript types | Full type declarations included | `TemplateResult`, `PropertyValues`, `CSSResult`, `PropertyDeclaration`, etc. | P0 |
| 199 | `HTMLElementTagNameMap` | `declare global { interface HTMLElementTagNameMap { 'my-el': MyEl; } }` | Type-safe `querySelector` and `createElement` | P1 |
| 200 | Dev-mode warnings | Automatic in development build | Runtime warnings for common mistakes (change-in-update, etc.) | P1 |
| 201 | Warning suppression | `LitElement.disableWarning?.('change-in-update');` | Disable specific dev-mode warnings | P2 |
| 202 | `lit-analyzer` / `lit-plugin` | VS Code extension / CLI | Template type-checking, completion, syntax highlighting inside `html` templates | P1 |
| 203 | `eslint-plugin-lit` | ESLint plugin | Lit-specific linting rules | P2 |
| 204 | Polyfills | `@webcomponents/webcomponentsjs` (optional) | Polyfills for Custom Elements, Shadow DOM, etc. on older browsers | P2 |
| 205 | Browser support | All modern browsers (Chrome, Firefox, Safari, Edge) | Lit 3 targets ES2021; requires ES2021-compatible browser or transpilation | P1 |

### 1.15 Packaging and Distribution

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 206 | ESM only | `"type": "module"` in package.json | Lit packages ship as ES modules; CommonJS not supported | P0 |
| 207 | Do not bundle rule | peerDependencies on `lit` | Publishing components: do not bundle Lit; causes duplicate instances | P1 |
| 208 | CDN usage | `import {LitElement, html} from 'https://cdn.jsdelivr.net/npm/lit@3/+esm'` | Lit works from CDN without build step | P1 |
| 209 | Dedup and multiple Lit versions | Singleton requirements (e.g., `signal-polyfill`) | Some packages require exactly one copy; use `npm dedupe` | P2 |
| 210 | `customElements.define` collision | Try/catch or scoped registries | Cannot define the same tag name twice; use scoped registry mixin or check first | P1 |
| 211 | File extensions in imports | `import './element.js'` (not `'./element'`) | Always include `.js` extension for ESM compatibility | P1 |
| 212 | Self-registration | `@customElement` calls `customElements.define` | Components register themselves when imported | P0 |
| 213 | Export the class | `export class MyElement extends LitElement` | Export for subclassing and scoped registries | P1 |
| 214 | Production build (Rollup) | Rollup + `@web/rollup-plugin-html` + terser + `minify-html-literals` | Recommended production build pipeline | P2 |
| 215 | Vite HMR | `vite-plugin-web-components-hmr` | Hot module replacement for Lit components | P2 |
| 216 | `vite-plugin-lit-css` | Import `.css` as Lit `css` tagged template | Vite plugin for CSS imports | P2 |

### 1.16 Testing

| # | Feature | Lit API / Syntax | Description | Priority |
|---|---------|-----------------|-------------|----------|
| 217 | Browser-based testing | Web Test Runner + Playwright/Puppeteer | Lit components must be tested in real browsers (Custom Elements, Shadow DOM, Constructable Stylesheets) | P0 |
| 218 | `@open-wc/testing` | `import {fixture, html, expect} from '@open-wc/testing';` | Test helpers: `fixture()` for mounting, `html` for templates, Chai expect | P0 |
| 219 | `fixture()` | `const el = await fixture<MyEl>(html`<my-el .prop=${val}></my-el>`);` | Mount a Lit element in test DOM; returns the element instance | P0 |
| 220 | `updateComplete` in tests | `el.prop = newVal; await el.updateComplete; expect(...)` | Wait for Lit's reactive update cycle before asserting | P0 |
| 221 | Shadow DOM queries | `el.shadowRoot!.querySelector('.inner')` | Query through shadow root in tests | P0 |
| 222 | Semantic DOM snapshots | `expect(el).shadowDom.to.equalSnapshot();` | Snapshot testing of rendered shadow DOM | P2 |
| 223 | Accessibility assertions | `await expect(el).to.be.accessible();` (with axe-core) | Automated a11y checks in component tests | P1 |
| 224 | WebdriverIO alternative | `@wdio/globals` with `$()` and `toHaveText()` | Alternative test runner for Lit components | P2 |
| 225 | Vitest browser mode | `vitest` with `browser.enabled: true, provider: 'playwright'` | Emerging option for browser-based component tests | P2 |
| 226 | `requestAnimationFrame` pattern | `await new Promise(r => requestAnimationFrame(r));` | More reliable than `updateComplete` for full descendant-tree completion | P1 |
| 227 | Web Test Runner config | `web-test-runner.config.mjs` with `nodeResolve: true` | Standard config for Lit component test suites | P1 |

---

**Total features inventoried: 227**

Feature counts by area:
- Component model: 19
- Reactive properties: 18
- Templates: 18
- Built-in directives: 23
- Styles: 20
- Shadow DOM: 14
- Events: 13
- Reactive controllers: 10
- Composition: 8
- Forms: 6
- Accessibility: 4
- SSR: 12
- Labs / Ecosystem: 29
- Tooling / DX: 11
- Packaging / Distribution: 11
- Testing: 11

---

## 2. Parity Matrix

Legend:
- ✅ = native / fully covered in this tier
- 🟡 = partial / some coverage or workaround
- 🔌 = via JS escape hatch (hand-written Lit underneath)
- ❌ = not supported
- ❓ = open — reason required in Notes (never bare)
- ⚠ = spike-proven (brief 4c), production unshipped — counted separately, never as ✅

**Tier 2 architecture (spike-confirmed):** the Tier 2 wrapper is a plain `TesseraHoloElement extends HTMLElement` + open shadow root + Hologram interpreter/snabbdom inside — **no LitElement anywhere**. Lit lifecycle/decorator rows are judged as "is the capability reachable from the wrapper/host".

Notes convention: every 🔌 says how and every ❌ says why in Notes; ❓ carries its reason in Notes.

### 2.1 Component Model

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 1 | LitElement | `extends LitElement` | 🔌 Hand-written Lit elements beneath Elixir layer | ✅ expected: compiled output IS LitElement | ❌ | Tier 2: wrapper is a thin LitElement delegating to Hologram · Tier 2: no LitElement — wrapper is a plain TesseraHoloElement extends HTMLElement + open shadow root + Hologram interpreter/snabbdom inside |
| 2 | ReactiveElement | `extends ReactiveElement` | 🔌 Inherited via LitElement | 🔌 Inherited via LitElement | ❌ | Tier 1/2 both have this from Lit underneath · Tier 1: inherited from the compiled LitElement · Tier 2: no ReactiveElement — plain HTMLElement wrapper |
| 3 | @customElement | `@customElement('tag')` | 🔌 Hand-written on wrapper class | ✅ expected: generated from Elixir module name | ✅ expected: wrapper registers the element tag | |
| 4 | connectedCallback | super.connectedCallback() | 🔌 Via Lit element lifecycle | 🔌 Via compiled LitElement | 🟡 expected: Hologram init hooks map to this | |
| 5 | disconnectedCallback | super.disconnectedCallback() | 🔌 Via Lit element lifecycle | 🔌 Via compiled LitElement | 🟡 expected: Hologram teardown maps to this | |
| 6 | shouldUpdate | shouldUpdate(cp): boolean | 🔌 Can be overridden in hand-written elements | ✅ confirmed: `should_update` DSL | ❌ | Tier 2: no render-gate hook — wrapper always re-renders · Tier 1: `should_update fn state, changed -> boolean end` lowers to shouldUpdate; false freezes the render (C-15 WTR) |
| 7 | willUpdate | willUpdate(cp) | 🔌 Via Lit element lifecycle | ✅ confirmed: `will_update` DSL | ✅ | Tier 2: shim projects `willUpdate(changed)` BEFORE renderDom+patch (3c) — changed = camelCase props+state diff with OLD values, plain object; first render sees the props view only (state struct is created by renderDom — honest divergence) · Tier 1: will_update lowers to willUpdate — changed old-value snapshot + next-state application (LC-01/LC-04 WTR) |
| 8 | update | update(cp) | 🔌 Via Lit element lifecycle | 🔌 Via compiled LitElement | ❌ | Rarely overridden directly — no update-phase hook, interpreter owns rendering |
| 9 | render | render(): TemplateResult | 🔌 Hand-written in Lit element | ✅ confirmed: `~TSR"""..."""` template DSL compiles to lit-html `render()` | 🟡 expected: Hologram's own rendering, not Lit's | Spike: dual-lexer parses `{expr}`, `{%if}/{%for}`, `$event`; generates `html``` in render() |
| 10 | firstUpdated | firstUpdated(cp) | 🔌 Can be overridden in hand-written elements | ✅ confirmed: `first_updated` DSL | ✅ | Tier 2: `firstUpdated(changed)` fires once per ELEMENT lifetime after the first committed render — latch survives disconnect/reconnect (3c; C-13/LC-03 Cypress) · Tier 1: first_updated lowers to firstUpdated — fires once after the first render (C-13/LC-03 WTR); behaviors.add remains the connect-time seam |
| 11 | updated | updated(cp) | 🔌 Via Lit element lifecycle | ✅ confirmed: `updated` DSL | ✅ | Tier 2: `updated(changed)` fires after every committed render — DOM already patched (3c; LC-02); a throwing hook is caught+warned, never aborts the shared Hologram.render loop (documented divergence: Lit propagates) · Tier 1: updated lowers to updated — fires after every rendered update, return value discarded (side-effects/emit; LC-02 WTR) |
| 12 | updateComplete | await this.updateComplete | 🔌 Via Lit element | 🔌 Via compiled LitElement | ✅ | Tier 2: `el.updateComplete` is the render-commit fence (3c) — queues behind an in-flight render, resolves true at commit / false on abort; at idle it resolves immediately because Tier-2 commits SYNCHRONOUSLY inside dispatchAction/setProps. Async-stage renders need `await dispatchAction(...)` first (honest debt, same class as X-10). C-14 pins the pattern |
| 13 | getUpdateComplete | async getUpdateComplete() | 🔌 Can be overridden | ❌ | 🟡 | Tier 2: no separate getUpdateComplete seam — but updateComplete itself IS an overridable prototype getter (3c), the seam for child-awaiting; dispatchAction/setProps still commit synchronously · Tier 1: not modeled; subclass-only |
| 14 | requestUpdate | this.requestUpdate() | 🔌 Via Lit element | ✅ expected: triggered by Elixir state changes | 🟡 expected: Hologram triggers re-render, wrapper propagates | |
| 15 | scheduleUpdate | async scheduleUpdate() | 🔌 Via Lit element | ❌ | ❌ | Advanced scheduler customization — no scheduler hook, interpreter owns update timing · Tier 1: fixed codegen surface (lit_codegen.ex:36-100) |
| 16 | performUpdate | (internal) | 🔌 Lit internal | 🔌 Lit internal | ❌ | no Lit update machinery in Tier 2 — interpreter owns update execution |
| 17 | addInitializer | addInitializer(fn) | 🔌 Via Lit element | ❌ | 🔌 | subclass + documented hooks (transformProps/onActionError) replaces it · Tier 1: no initializer concept in DSL |
| 18 | hasUpdated | this.hasUpdated | 🔌 Via Lit element | 🔌 Via compiled LitElement | ✅ | Tier 2: `el.hasUpdated` getter — latches true after the first committed render, per element lifetime (3c; LC-03) |
| 19 | isConnected | this.isConnected | 🔌 Via Lit element | 🔌 Via compiled LitElement | ✅ native: Element.isConnected on the plain HTMLElement wrapper | |

### 2.2 Reactive Properties

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 20 | @property | @property(opts) | 🟡 Elixir `tsr_prop` maps to @property via bridge | ✅ expected: compiled from Elixir attr declaration | 🔌 wrapper exposes @property that delegates to Hologram state | Tessera today: attrs defined in Elixir contract, bridge generates Lit @property |
| 21 | @property({type}) | type: String/Number/Boolean/Object/Array | 🟡 Elixir types map to Lit types in bridge | ✅ confirmed: all five types map | 🔌 wrapper property types map to Hologram types | Tier 1: integer/float→Number, string→String, boolean→Boolean, list→Array, map/any→Object (lit_codegen.ex lit_type/1); Array JSON attribute converter WTR-verified (C-06/#21) |
| 22 | @property({attribute}) | attribute: 'my-prop' or false | 🟡 Contract specifies attribute name | ✅ confirmed: `attribute: "name" \| false` | 🔌 wrapper property → Hologram attr | Tier 1: attribute option emitted in static properties — rename (C-10 WTR) or false (no attribute observation); contract/CEM still document the default kebab name (follow-up) |
| 23 | @property({reflect}) | reflect: true | ❌ Not in Phase 1 contract docs | ✅ confirmed: `reflect: true` | ❌ | attrs flow one-way IN only · Tier 1: reflect: true emitted; property→attribute reflection C-02/C-09 WTR |
| 24 | @property({converter}) | converter: {fromAttribute, toAttribute} | ❌ | ❌ | 🔌 | manifest-typed casting (integer/float/boolean/atom/string) + tsr-props JSON; no per-prop custom converter · Tier 1: coercion fixed in TesseraElement (element.mjs:57-73); custom converter fns impossible in subset |
| 25 | @property({hasChanged}) | hasChanged: (n,o) => bool | ❌ | ❌ | ❌ | setProps always re-renders · Tier 1: not emitted |
| 26 | @property({noAccessor}) | noAccessor: true | ❌ | ❌ | ❌ | Niche option — plain property semantics, no accessor customization · Tier 1: properties_object emits {type} only (lit_codegen.ex:166-173) |
| 27 | @property({useDefault}) | useDefault: true | ❌ | ❌ | ❌ | Lit 3.3+ feature — no attribute-removal default reset · Tier 1: constructor defaults exist (lit_codegen.ex:193-214) but no attribute-removal reset semantics |
| 28 | @state | @state() private _x | 🟡 Elixir internal state mapped via bridge | ✅ confirmed: `state(:count, :integer, default: 0)` generates Lit reactive properties | 🔌 wrapper @state maps to Hologram internal state | Spike: state DSL compiles to `static properties` entries; state keys stay snake_case on the element |
| 29 | static properties | static properties = {...} | ❌ (uses decorators) | ✅ confirmed: generated element uses static properties field | ✅ | Spike golden fixture confirms static properties output · Tier 2: Elixir `__props__/0` is the compile-time contract driving attribute casting |
| 30 | Attribute-to-property conversion | automatic per type | 🟡 Bridge handles attr→prop sync | ✅ expected: Lit handles this natively | 🔌 wrapper-level | Tier 2: tsr-props attr casting at wrapper level; no Lit conversion |
| 31 | Property-to-attribute reflection | @property({reflect: true}) | ❌ | ✅ confirmed: `reflect: true` | ❌ | attrs flow one-way IN only (same as #23) · Tier 1: reflect option (same as #23) |
| 32 | Attribute name mapping | camelCase → lowercase | 🟡 Contract specifies attr name mapping | ✅ expected | 🔌 wrapper handles attr name mapping | |
| 33 | Boolean attribute semantics | present=true, absent=false | 🟡 Bridge respects Boolean type | ✅ expected | 🔌 wrapper Boolean properties | |
| 34 | changedProperties map | willUpdate(cp) | 🔌 Available via Lit element | ✅ confirmed: `changed` snapshot in hooks | ✅ | Tier 2: hooks receive a plain-object snapshot of OLD values (camelCase props∪state merged view, state wins; first render props-only) — NOT a live Map (3c; LC-04 pins the shape) · Tier 1: lifecycle hooks receive `changed = Object.fromEntries(changedProperties)` — plain object, OLD values, property-name keys (camelCase attrs/props, snake state); NOT a live Map (LC-04 WTR) |
| 35 | Custom getter/setter | @property() set/get | ❌ | ❌ | 🔌 | setProps + state getter + transformProps · Tier 1: no accessor DSL; properties are plain Lit reactive props |
| 36 | elementProperties metadata | MyElement.elementProperties | 🔌 Available via Lit element | 🔌 Available via compiled LitElement | 🔌 Available via wrapper | |
| 37 | Mutation detection | this.items = [...items, new] | ❌ (JS concern) | ✅ expected: Elixir immutable data pattern | 🔌 | tsr-props attr re-derive fires re-render; JS mutation not tracked |

### 2.3 Templates

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 38 | html tag | html`` | 🔌 Hand-written Lit templates | ✅ expected: compiled from Elixir template DSL | 🔌 Wrapper's render delegates to Hologram; Hologram uses its own template system | Tier 2: Hologram provides its own template language, not Lit's html`` |
| 39 | svg tag | svg`` | 🔌 Hand-written in Lit | 🟡 expected: Elixir SVG template compiles to svg`` | 🔌 via Hologram's rendering | |
| 40 | mathml tag | mathml`` | ❌ | ❌ | 🔌 | Lit 3.2+, niche — unknown tags pass through renderer; mathml untested specifically · Tier 1: html`` only |
| 41 | Child expression | ${expr} | 🔌 Hand-written | ✅ expected | 🔌 via Hologram | |
| 42 | Attribute expression | attr=${val} | 🔌 Hand-written | ✅ expected | 🔌 via Hologram | |
| 43 | Boolean attribute expression | ?attr=${val} | 🔌 Hand-written | ✅ confirmed: `?attr={expr}` both lexers | 🔌 | renderer-owned, untested · Tier 1: `?attr={expr}` emits `?name=${expr}` (no quotes/__t); static ?attr → bare presence; mixed text/expr rejected; dual-lexer token parity pinned (T-03 WTR) |
| 44 | Property expression | .prop=${val} | 🔌 Hand-written | ✅ expected | 🔌 wrapper uses .prop for Hologram state | |
| 45 | Event listener expression | @event=${handler} | 🔌 Hand-written | ✅ expected | 🟡 wrapper listens to DOM events, forwards to Hologram | |
| 46 | Element expression | ${directive()} | 🔌 Hand-written | ❌ | ❌ | no directive-part position in Hologram templates · Tier 1: attr emission handles static/parts/$event only (template.ex:554-580); no directive pipeline |
| 47 | nothing sentinel | import {nothing} | 🔌 Hand-written | ✅ confirmed: bare `nothing` → imported sentinel | ✅ | nil renders nothing · Tier 1 (1d): `nothing` lowers to the `nothing` sentinel — child `${nothing}` (no __t), attribute `attr=${nothing}` removes the attribute; `import {…, nothing}` emitted only when used (T-06 WTR). nil→null stays distinct from nothing |
| 48 | noChange sentinel | import {noChange} | ❌ | ❌ | ❌ | Directive-internal use — no Hologram equivalent · Tier 1: if/else emits plain html`` (template.ex:535-543) |
| 49 | Conditional rendering | ternary / when() | 🔌 Hand-written | ✅ confirmed: `{%if}/{%else}/{/if}` in template DSL compiles to ternary in generated JS | 🔌 via Hologram's own conditionals | Spike: if/else in ~TSR templates |
| 50 | List rendering | Array.map / map() | 🔌 Hand-written | ✅ confirmed: `{%for x <- coll}` in template DSL compiles to `map()` directive | 🔌 via Hologram | Spike: `{%for}` compiles to Array.prototype.map (template.ex:546-552) — not the lit map() directive |
| 51 | Static expressions (literal) | literal`` / unsafeStatic() | ❌ | ❌ | ❌ | Niche: dynamic tag names — not supported in Hologram templates · Tier 1: tag names always static |
| 52 | Static expressions (unsafeStatic) | unsafeStatic(str) | ❌ | ❌ | ❌ | dynamic tag names not supported in Hologram templates · Tier 1: not modeled |
| 53 | Nested templates | ${html`...`} | 🔌 Hand-written | ✅ expected | 🔌 via Hologram | |
| 54 | Template functions | const fn = (...) => html`...` | ❌ | ❌ | 🔌 via Hologram | Tier 1: fn allowed only as Enum.map/filter callback (expr.ex:80-92); no function components |
| 55 | Template result caching | automatic | 🔌 Lit handles this | ✅ confirmed | ❌ | Tier 1: static html`` literals (golden fixture:57); lit-native template caching · no lit-html in Tier 2 — Hologram/snabbdom reconciliation owns caching |

### 2.4 Built-in Directives

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 56 | classMap | classMap({...}) | 🔌 Hand-written | ✅ confirmed: `class_map(%{…})` → `classMap({…})` | 🔌 wrapper can use classMap | Tier 1 (1d): `class_map(map_literal)` lowers to `classMap({…})` in child + attribute position (unquoted, no __t); `import {classMap} from "lit/directives/class-map.js"` emitted when used; non-map args rejected by name (D-01 WTR) |
| 57 | styleMap | styleMap({...}) | 🔌 Hand-written | ✅ confirmed: `style_map(%{…})` → `styleMap({…})` | 🔌 wrapper can use styleMap | Tier 1 (1d): `style_map(map_literal)` lowers to `styleMap({…})` — camelCase keys as written, string keys (incl. `--tsr-<tag>-*` custom properties) quoted; child + attribute position (unquoted, no __t); import emitted when used (D-02 WTR) |
| 58 | when | when(cond, T, F) | 🔌 Hand-written | 🔌 ternary | 🔌 wrapper can use when | Tier 1: ternary if/else (template.ex:535-543); when() not emitted |
| 59 | choose | choose(val, cases, default) | 🔌 Hand-written | ❌ | 🔌 wrapper can use choose | Tier 1: cond/case rejected by subset (expr.ex:26-36); only if/else ternaries |
| 60 | map | map(iter, fn) | 🔌 Hand-written | 🔌 Array.map | 🔌 wrapper can use map | Tier 1: Array.prototype.map (template.ex:551), not the lit map() directive |
| 61 | join | join(items, sep) | ❌ | 🔌 string join | 🔌 | Enum.join at expression level, subject to runtime stdlib coverage · Tier 1: Enum.join → Array.join string (expr.ex:80-92); not the join directive |
| 62 | range | range(end) / range(s, e, step) | ❌ | ❌ | 🔌 | Enum.map/enumerables · Tier 1: not in any expression allowlist |
| 63 | repeat | repeat(items, key, fn) | 🔌 Hand-written | ❌ | 🔌 wrapper can use repeat | Tier 1: Array.map only, no keys (template.ex:551) |
| 64 | cache | cache(template) | ❌ | ❌ | ❌ | whole-template re-render; interpreter owns reconciliation, no DOM cache · Tier 1: not modeled |
| 65 | guard | guard(deps, fn) | ❌ | ❌ | ❌ | no memo gate — interpreter re-renders · Tier 1: not modeled |
| 66 | live | live(value) | ❌ | ❌ | ❌ | no live-DOM comparison — vdom owns values · Tier 1: not modeled |
| 67 | keyed | keyed(key, template) | ❌ | ❌ | ❌ | Hologram vdom owns reconciliation · Tier 1: not modeled |
| 68 | ifDefined | ifDefined(val) | 🔌 Hand-written | ✅ confirmed: `if_defined(expr)` → `ifDefined(…)` | 🔌 wrapper can use ifDefined | Tier 1 (1d): `if_defined(expr)` lowers to `ifDefined(…)` in attribute position (unquoted, no __t) — removes the attribute on null/undefined; `import {ifDefined} from "lit/directives/if-defined.js"` emitted when used (D-06 WTR) |
| 69 | ref / createRef | ref(this.ref) / createRef() | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | 🔌 | ref requires imperative DOM; generated DSL doesn't emit it, but `behaviors.add` on connect provides full element access · Tier 2: open shadow root → el.shadowRoot.querySelector from host |
| 70 | until | until(promise, placeholder) | 🔌 Hand-written | ❌ | 🔌 wrapper can use until | Tier 1: subset is synchronous |
| 71 | asyncAppend | asyncAppend(asyncIter, fn) | ❌ | ❌ | ❌ | no async iterables in templates · Tier 1: no async in subset (expr.ex:26-36) |
| 72 | asyncReplace | asyncReplace(asyncIter) | ❌ | ❌ | ❌ | no async iterables in templates · Tier 1: no async in subset |
| 73 | templateContent | templateContent(tpl) | ❌ | ❌ | ❌ | no `<template>` content cloning in renderer · Tier 1: no directive pipeline |
| 74 | unsafeHTML | unsafeHTML(str) | 🔌 Hand-written | ❌ | 🔌 wrapper can use unsafeHTML | Tier 1: template text is escaped (template.ex:675-680); no unsafeHTML |
| 75 | unsafeSVG | unsafeSVG(str) | ❌ | ❌ | ❌ | no raw-SVG string injection · Tier 1: not modeled |
| 76 | unsafeMathML | (pattern) | ❌ | ❌ | ❌ | no MathML string injection · Tier 1: not modeled |
| 77 | Custom directives | class extends Directive | ❌ | 🔌 via behaviors.add escape hatch | ❌ | Custom directives need imperative DOM; reachable through the behaviors.add hatch · Tier 2: template-level ❌ — host-side onAction chain is the hatch |
| 78 | Async directives | class extends AsyncDirective | ❌ | 🔌 via behaviors.add escape hatch | ❌ | Async directives need lifecycle integration; reachable through behaviors.add · Tier 2: same hatch as #77 (host-side onAction chain) |

### 2.5 Styles

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 79 | css tag | static styles = css`` | 🔌 Hand-written | ✅ styles DSL emits author css`` blocks | 🔌 Wrapper has static styles; Hologram styles are separate | Tier 2: Hologram's CSS lives in Hologram's own system · Tier 1 (2026-11-11): `styles ~CSS`/string/list DSL; codegen emits one css`` block per author entry (escaped for the literal) |
| 80 | Static styles (Constructable Stylesheets) | static styles | 🔌 Hand-written Lit styles | ✅ confirmed: output uses static styles | 🟡 Wrapper uses static styles; Hologram content styled separately | Tier 1: output does use static styles (golden fixture:18-23) — prior 🔌 was an underclaim |
| 81 | Style array composition | [a, b, css``] | 🔌 Hand-written | ✅ [baseStyles, …author entries] | 🔌 Wrapper composes styles | Tier 1 (2026-11-11): css blocks + shared-module bindings compose in declaration order = cascade order (WTR S-06) |
| 82 | Style inheritance | [...Parent.styles] | 🔌 Hand-written | ✅ baseStyles inherited via array composition | 🔌 Wrapper inherits | Tier 1 (2026-11-11): every element composes [baseStyles, …author] — the tessera base's styles are the inherited parent entry; cross-component vendor derivation ([...Vendor.styles]) rides EXTENSION-CONTRACT §5 (pending) |
| 83 | :host selector | :host { ... } | 🔌 Hand-written | ✅ author :host rules | 🔌 Wrapper uses :host | Tier 1 (2026-11-11): author :host rules append after baseStyles (WTR S-01) |
| 84 | :host([attr]) | :host([active]) | 🔌 Hand-written | ✅ passthrough | 🔌 Wrapper uses :host([attr]) | Tier 1 (2026-11-11): :host([tone="dark"]) verified toggling with the attribute (WTR S-02) |
| 85 | :host(.class) | :host(.primary) | 🔌 Hand-written | ✅ passthrough | 🔌 Wrapper uses :host(.class) | Tier 1 (2026-11-11): :host(.highlighted) verified toggling with the class (WTR S-02) |
| 86 | :host-context(.theme) | :host-context(.dark) | ❌ | ❌ | 🔌 | host styles any part (open root); no scoped sheet shipped · Tier 1: not modeled (verbatim passthrough would reach Lit, untested) |
| 87 | ::slotted() | ::slotted(p) { ... } | 🔌 Hand-written | ✅ passthrough | 🔌 Wrapper uses ::slotted | Tier 1 (2026-11-11): ::slotted(p) verified on a slotted child (WTR S-03) |
| 88 | :defined | my-el:defined | 🔌 Native browser CSS | 🔌 Native | 🔌 Native | |
| 89 | ::part() (exportparts) | ::part(button) | ❌ | 🟡 parts exposed; exportparts not modeled | 🔌 | Tier 1 (2026-11-11): host exposes a `root` part + template `part="…"` attrs, declared in CEM `cssParts`; outer-tree ::part(accent) styling verified (WTR X-14); composite exportparts re-exposure still unmodeled |
| 90 | CSS custom properties | var(--name, fallback) | 🔌 Hand-written | ✅ var(--tsr-<tag>-*, fallback) | 🔌 Wrapper uses CSS custom properties | Tier 1 (2026-11-11): fallback REQUIRED at compile time for tag-scoped reads; declared in CEM cssProperties; ancestor overrides verified (WTR S-04/X-14) |
| 91 | CSS custom property naming | --comp-name-prop | 🟡 Manual convention | ✅ --tsr-<tag>-<prop> | 🟡 Manual convention | Tier 1 (2026-11-11): the scanner only recognizes --tsr-<tag>-<lower-kebab> reads (EXTENSION-CONTRACT §7); other var() reads pass through undeclared |
| 92 | Shared style modules | export const styles = css`` | 🔌 Hand-written | ✅ {:shared, "path.mjs"} | 🔌 Wrapper imports shared styles | Tier 1 (2026-11-11): imports the module's `styles` CSSResult into the array at the declared position; deduped per path (WTR S-05) |
| 93 | unsafeCSS | unsafeCSS(str) | ❌ | ❌ | ❌ | no dynamic CSS string injection · Tier 1: not modeled (deliberate — author CSS is static and escaped) |
| 94 | shadowRootOptions | static shadowRootOptions | 🔌 Hand-written | ❌ | 🔌 Wrapper sets shadowRootOptions | Tier 1: not emitted |
| 95 | delegatesFocus | delegatesFocus: true | 🔌 Hand-written | ❌ | 🔌 Wrapper sets delegatesFocus | Tier 1: not emitted |
| 96 | createRenderRoot (light DOM) | createRenderRoot() { return this; } | ❌ | ❌ | 🔌 | open shadow today; light-DOM root is a small wrapper change, not implemented · Tier 1: not modeled |
| 97 | Design system token pattern | Two-level tokens | 🟡 Manual in CSS | ❌ | 🟡 Manual | Tier 1: no token DSL (var() chains work in author CSS, unmodeled) |
| 98 | Theme switching | CSS custom property overrides | 🔌 Hand-written | ✅ ancestor --tsr-* overrides | 🔌 Wrapper | Tier 1 (2026-11-11): setting --tsr-<tag>-* on an ancestor re-themes host + shadow content (WTR S-04) |

### 2.6 Shadow DOM

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 99 | Default slot | `<slot></slot>` | 🟡 Elixir `slot` declaration → Lit `<slot>` | ✅ confirmed: literal `<slot>` markup passthrough | ✅ marker-rewritten `<slot>` (SD-01) | Tier 1: the slot declaration validates only (component.ex:360-363), never consumed by codegen; slots work via markup passthrough (template.ex:522-530) · Tier 2 (3e): Hologram void-parses `<slot>` AND both renderers substitute slot nodes, so markup passthrough is impossible — authors mark a slot with an element carrying `data-tsr-slot`; the shim rewrites those vnodes into real `<slot>` elements before each patch, and platform assignment works (Cypress SD-01) |
| 100 | Named slots | `<slot name="header">` | 🟡 Elixir named slot → named `<slot>` | ✅ expected | ✅ named — `data-tsr-slot="header"` (SD-02) | Tier 2 (3e): the marker's value lowers to the slot `name` attribute; a `slot="header"` child lands ONLY in the named slot (Cypress SD-02) |
| 101 | Slot fallback content | `<slot>default</slot>` | 🔌 Hand-written | ✅ expected | ✅ fallback = marker children (SD-03) | Tier 2 (3e): the marker is an ordinary element, so its children survive the void parse and become the slot's fallback content when rewritten — the one thing `<slot>` markup could never express here (Cypress SD-03) |
| 102 | @query | @query('#id') el | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | 🔌 | Imperative DOM reference; reachable through behaviors.add · Tier 2: no decorator, shadowRoot.querySelector works |
| 103 | @queryAll | @queryAll('.cls') els | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | 🔌 | no decorator; shadowRoot.querySelectorAll works |
| 104 | @queryAsync | @queryAsync('#dyn') | ❌ | 🔌 via behaviors.add escape hatch | 🔌 | async wrapper trivial |
| 105 | @queryAssignedElements | @queryAssignedElements({slot}) | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | 🔌 | slot wiring landed in 3e (#99-#101/#107-#109) — the decorator equivalent is a subclass one-liner (`slot.assignedElements({flatten})`) on the wired slot; no decorator itself |
| 106 | @queryAssignedNodes | @queryAssignedNodes({slot}) | ❌ | 🔌 via behaviors.add escape hatch | 🔌 | same — no decorator; `assignedNodes({flatten})` works on the wired slot (3e) |
| 107 | slotchange event | @slotchange=${fn} | 🔌 Hand-written | ✅ expected | ✅ shim-routed (SD-04) | Tier 2 (3e): NOT `@slotchange` authoring — Hologram's client runtime resolves `$event` handlers through a hardcoded whitelist that has no slotchange entry (an unlisted type throws inside handleUiEvent), so the shim attaches the listener itself: `data-tsr-slot-change="action"` on the slot marker dispatches the named action via the §6.3 pipeline on every genuine assignment change (Cypress SD-04; honest divergence from Lit's binding syntax) |
| 108 | assignedElements() | slot.assignedElements() | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | ✅ platform API on the wired slot (SD-01…03) | Imperative DOM access; reachable through behaviors.add · Tier 2 (3e): the rewrite yields a real HTMLSlotElement — assignedElements/flatten work unchanged (Cypress SD-01/02/03) |
| 109 | assignedNodes() | slot.assignedNodes() | ❌ | 🔌 via behaviors.add escape hatch | ✅ incl. fallback flatten (SD-03) | Tier 2 (3e): wired slot + flatten:true yields fallback content until something assigns (Cypress SD-03) |
| 110 | renderRoot | this.renderRoot | 🔌 Lit internal | 🔌 Lit internal | ❌ | no renderRoot in Tier 2 — interpreter renders into the open shadow root directly |
| 111 | Open shadow root | mode: 'open' (default) | 🔌 Default | 🔌 Default | 🔌 Default | |
| 112 | Closed shadow root | mode: 'closed' | ❌ | ❌ | 🔌 | closed root trivially configurable; open by default · Tier 1: no shadowRootOptions emission |

### 2.7 Events

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 113 | @event listener | @click=${handler} | 🔌 Hand-written | ✅ expected: compiles from Elixir event handlers | 🟡 Wrapper listens, forwards to Hologram via bridge | |
| 114 | CustomEvent dispatch | dispatchEvent(new CustomEvent(...)) | 🔌 Hand-written in Lit | ✅ confirmed: `emit/2` in action DSL generates composed CustomEvent dispatch | 🟡 Hologram emits, wrapper dispatches CustomEvent | Spike: `emit("event-name", %{key: val})` compiled to CustomEvent with composed+bubbles; camelCase detail keys at emit boundary |
| 115 | bubbles option | {bubbles: true} | 🔌 Hand-written | ✅ expected | 🔌 Wrapper sets event options | |
| 116 | composed option | {composed: true} | 🔌 Hand-written | ✅ expected | 🔌 Wrapper sets event options | |
| 117 | cancelable option | {cancelable: true} | ❌ | ❌ | 🔌 | emits bubbles+composed; cancelable flag not set · Tier 1: emit hardcodes bubbles/composed only (events.mjs:19-21) |
| 118 | @eventOptions | @eventOptions({passive: true}) | ❌ | ❌ | ❌ | no template-level listener options — host addEventListener opts apply · Tier 1: not modeled |
| 119 | handleEvent object | {handleEvent: fn, once: true} | ❌ | ❌ | 🔌 | host-side addEventListener accepts any listener form; template on-spec is function-only · Tier 1: $event binds declared action atoms only (template.ex:585-621) |
| 120 | Remove listener with nothing | @click=${active ? fn : nothing} | 🔌 Hand-written | ❌ | 🔌 | host-side removeEventListener works · Tier 1: binding must be a declared action atom; no conditional form |
| 121 | Typed CustomEvents | class MyEvent extends Event | ❌ | ❌ | ❌ | no shipped types · Tier 1: plain CustomEvent only (events.mjs:19-21); structs rejected in subset |
| 122 | composedPath() | event.composedPath() | 🔌 Hand-written | 🔌 Native | 🔌 Native | |
| 123 | Bidirectional event pattern | event.detail.response | ❌ | ❌ | ✅ | onAction intercept + emit + setProps is the contract shape (e2e pending) · Tier 1: emit detail is one-way |
| 124 | Dispatch after render | await updateComplete; dispatch | 🔌 Hand-written | ❌ | 🔌 | action→render sequencing owned by interpreter; host awaits dispatchAction return · Tier 1: emit runs synchronously inside the action; no updateComplete-then-dispatch modeling |
| 125 | External listeners | window.addEventListener | 🔌 Hand-written | 🔌 via behaviors.add | ✅ | composed bubbling CustomEvents — core design (e2e pending) · Tier 1: behaviors.add + disconnect cleanup (element.mjs:204-235) |

### 2.8 Reactive Controllers

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 126 | ReactiveController interface | interface ReactiveController | 🔌 Hand-written controllers | 🔌 via behaviors.add escape hatch | 🔌 | Controllers require imperative host API; behaviors.add provides connect/disconnect lifecycle matching controller hooks · Tier 2: subclass TesseraHoloElement + connected/disconnectedCallback |
| 127 | addController | this.addController(ctrl) | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | ❌ | no registry (subclass keeps own array) |
| 128 | hostConnected | hostConnected() | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | 🔌 | behaviors.add fn runs on connectedCallback · Tier 2: subclass connectedCallback |
| 129 | hostDisconnected | hostDisconnected() | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | 🔌 | behaviors.add cleanup fn runs on disconnectedCallback · Tier 2: subclass disconnectedCallback |
| 130 | hostUpdate | hostUpdate() | ❌ | ❌ | ❌ | no render lifecycle · Tier 1: behaviors have no update-time hook |
| 131 | hostUpdated | hostUpdated() | ❌ | ❌ | ❌ | no render lifecycle · Tier 1: behaviors have no update-time hook |
| 132 | Controller requesting update | this.host.requestUpdate() | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | 🔌 | behaviors.add receives the element; can call requestUpdate() · Tier 2: call setProps |
| 133 | Multiple controllers | multiple controller instances | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | 🔌 | behaviors registry supports multiple per-tag · Tier 2: multiple hooks compose at subclass level |
| 134 | Composing controllers | controller owns other controllers | ❌ | 🔌 via behaviors.add escape hatch | ❌ | no controller host — subclass composition only |
| 135 | Controller + directive pattern | controller exposing ref() | ❌ | 🔌 via behaviors.add escape hatch | ❌ | no controller host or template directives |

### 2.9 Composition

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 136 | Nested components | `<child-el>` in template | 🟡 Elixir component composition → Lit nesting | 🔌 static markup | 🟡 Hologram components nested inside wrapper | Tier 1: component tags (uppercase-first) rejected (template.ex:325-328); lowercase custom-element tags pass as static markup — no compile-time component tree |
| 137 | Properties down | .prop=${val} | 🟡 Bridge passes Elixir attrs as Lit properties | ✅ expected | 🔌 Wrapper passes props to child wrappers | |
| 138 | Events up | @event=${handler} | 🟡 Bridge forwards Lit events to Elixir handlers | ✅ expected | 🟡 Hologram events bubble through wrapper | |
| 139 | Mixin pattern | const M = (super) => class extends super | ❌ | 🔌 via subclassing TesseraElement | 🔌 | Generated element is a LitElement subclass; consumer can apply mixins through TesseraElement mixin or plain JS subclassing · Tier 2: wrapper is a plain class — JS mixins apply; new tag via defineElement |
| 140 | Mixin with public API | TS interface + Constructor type | ❌ | 🔌 via subclassing TesseraElement | 🔌 | same — plain class, JS mixins apply |
| 141 | Mediator pattern | Parent owns state, coordinates children | 🟡 Elixir parent component as mediator | ✅ expected: natural in Elixir | ✅ expected: natural in Hologram | |
| 142 | Slot-based composition | `<slot>` elements | 🟡 Elixir slot → Lit slot | ✅ expected | ✅ slots wired via marker rewrite (SD-01…04) | Tier 2 (3e): light-DOM children compose into Hologram-rendered structure through the wired slots — default/named/fallback/slotchange all pinned (see §2.6) |
| 143 | Mixin vs Controller decision | Prefer controllers | 🔌 Available in hand-written JS | 🔌 behaviors.add covers controller-like use; mixins via subclassing | 🔌 | subclass-with-hooks is Tier 2's composition story (extension B demo) |

### 2.10 Forms

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 144 | formAssociated | static formAssociated = true | ❌ | ✅ spec DSL `form_associated: true` (FM-01) | ✅ manifest-declared (FM-01) | Tier 1 (2f): spec field `form_associated` (boolean, additive-derived inheritance) → manifest `formAssociated` (present ONLY when declared — byte-stable absent otherwise) → `static formAssociated = true` in all three emission templates (fresh/derived/takeover mixin) → WTR conformance manifest carries it · Tier 2 (3e): defineElement sets the static when the manifest declares it (interim fixture hook `__tsr_form_associated__` → manifest `formAssociated`; brief 3f moves it to the spec) — decided at define time, additive-only through subclassing (FM-01 both tiers, shared body) |
| 145 | ElementInternals | this.attachInternals() | ❌ | ✅ gated constructor attach (FM-01) | ✅ gated constructor attach (FM-01) | Tier 1 (2f): the TesseraElement constructor runs attachInternals ONLY when `new.target.formAssociated === true` and exposes the handle as `el.internals`; undeclared elements read `null` — never attached (§6.7 MUST NOT, pinned by the FM-01 negative on the undeclared counter fixture, shared body); attachInternals-unavailable degrades to a warn + null · Tier 2 (3e): same gate in the Hologram base class |
| 146 | setValidity | internals.setValidity(...) | ❌ | ✅ via el.internals (FM-03) | ✅ via el.internals (FM-03) | Tier 1 (2f): validity/validationMessage surface on the owning form, clearing needs the anchor argument (FM-03 shared body on WTR) · Tier 2 (3e): same via the Cypress harness |
| 147 | setFormValue | internals.setFormValue(val) | ❌ | ✅ documented subclass pattern (FM-02) | ✅ documented subclass pattern (FM-02) | Tier 1 (2f): the SAME push-per-render pattern — the WTR harness mounts the compiled fixture through ConfFormRecording (extends the generated class; every render pushes state → setFormValue); FormData carries the name/value and internals.form === owner (submission data + form association are the pinned surfaces; internals.value is the author-managed API value — NOT a setFormValue mirror) · Tier 2 (3e): host-glue subclass mirrors the pattern · shared fm_form.mjs bodies run UNMODIFIED on both engines |
| 148 | formResetCallback | formResetCallback() | ❌ | ✅ base seam, subclass-overridable (FM-03) | ✅ base seam, subclass-overridable (FM-03) | Tier 1 (2f): no-op seam on the mixin base; ConfFormRecording overrides to record the reset and dispatch the fixture's reset_value action — re-render re-pushes the initial value (FM-03 shared body) · Tier 2 (3e): same seam on TesseraHoloElement |
| 149 | formDisabledCallback | formDisabledCallback(bool) | ❌ | ✅ base seam, subclass-overridable (FM-03) | ✅ base seam, subclass-overridable (FM-03) | Tier 1 (2f): same seam — both directions (setAttribute/removeAttribute disabled) reach the element via the platform callback into el.tesseraFormSignals (FM-03 shared body) · Tier 2 (3e): same |

### 2.11 Accessibility

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 150 | delegatesFocus | shadowRootOptions.delegatesFocus | 🔌 Hand-written | ❌ | 🔌 Wrapper | Tier 1: not emitted |
| 151 | ARIA attribute reflection | aria-label, role, etc. | 🔌 Hand-written in template | ✅ expected: Elixir aria attributes → template attrs | 🔌 Hologram renders ARIA attrs | |
| 152 | aria property reflection | (browser native) | 🔌 Native | 🔌 Native | 🔌 Native | |
| 153 | eslint-plugin-lit-a11y | NPM dev dependency | 🔌 Available in tooling | 🔌 Available in tooling | 🔌 Available in tooling | |

### 2.12 SSR

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 154 | @lit-labs/ssr | import {render} from '@lit-labs/ssr' | ❌ | 🔌 plausible, unproven | ❌ | no Lit — Hologram server-renders its own HTML; @lit-labs/ssr does not apply (confirmed by spike 4c: Renderer.render_dom/3 is the native equivalent) · Tier 1: architecturally plausible (decorator-free LitElement output, DOM-free import, SSR-safe defineOnce) but zero SSR proof in spike |
| 155 | Declarative Shadow DOM | `<template shadowrootmode>` | 🔌 Lit SSR generates this | 🔌 Lit SSR generates for Tier 1 output | ⚠ spike-proven, unshipped | SPIKE 4c GO: server render via render_dom + DSD template emission + browser attach + runtime adopt-and-morph PROVEN in a real browser; production deltas = host-adoption in mountComponent + snabbdom toVNode sel-normalization (class/id-in-sel replaces subtrees otherwise) + init/3 author mirror — see docs/notes/ssr-dsd-spike.md |
| 156 | SSR lifecycle subset | only constructor/willUpdate/render | 🔌 Lit handles | 🔌 unproven | ⚠ spike-proven | 4c: Hologram's server subset is init/3 + template render (init/2 is CLIENT-only in 0.10.1); DSD components mirror init/2 into init/3 — the Lit-equivalent author contract; compiler enforcement owed (3f spec layer) · Tier 1: unproven in spike |
| 157 | @lit-labs/ssr-client hydration | import hydrate-support | ❌ | 🔌 unproven | ⚠ spike-proven, unshipped | 4c: hydration = host adoption + vnode-sel normalization onto the stock toVNode first-patch; node identity survives mount + action morphs + prop updates · Tier 1: unproven in spike |
| 158 | hydrate() function | hydrate(template, container) | ❌ | 🔌 unproven | ⚠ spike-proven shape | 4c: mountComponent-onto-existing-DSD-root IS the hydrate() equivalent (no Lit machinery); explicit hydrate option is a §4.1 shim delta · Tier 1: unproven in spike |
| 159 | Streaming SSR | RenderResultReadable | ❌ | 🔌 unproven | 🔌 | server can stream HTML; elements upgrade on connect · Tier 1: unproven in spike |
| 160 | collectResult / collectResultSync | collectResult(result) | ❌ | 🔌 unproven | ⚠ native equivalent | 4c: render_dom returns the collected HTML+registry directly (no result-stream to collect) — N/A by construction · Tier 1: unproven in spike |
| 161 | isServer detection | import {isServer} from 'lit' | ❌ | 🔌 unproven | ✅ | Hologram has native server/client split (same component runs both sides) · Tier 1: unproven in spike |
| 162 | VM module isolation | ModuleLoader | ❌ | 🔌 unproven | ❌ | server side is Elixir, not Node VM modules · Tier 1: unproven in spike |
| 163 | defer-hydration attribute | (Lit labs pattern) | ❌ | 🔌 unproven | ❌ accepted-gap | mounts on connect, no deferral; not exercised by spike 4c — trivially addable alongside the §4.1 shim delta · Tier 1: unproven in spike |
| 164 | Framework integrations (SSR) | Astro, Eleventy, Next.js | ❌ | 🔌 unproven | ❓ | framework SSR integrations not exercised in the Tier 2 spike · Tier 1: unproven in spike |
| 165 | template-shadowroot polyfill | @webcomponents/template-shadowroot | ❌ | 🔌 Polyfill available | ❌ accepted-gap | not shipped; spike 4c ran on native-DSD Chromium (Electron) — old-Safari fallback would wrap the polyfill around the same host-adoption mount · Tier 1: unproven in spike |

### 2.13 Labs / Ecosystem Packages

| # | Feature | Package | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 166 | Context protocol | @lit/context | ❌ | ❌ | ❌ | no Lit context; bus seam (setBus/BusClient) is the cross-boundary channel · Tier 1: no provide/consume DSL |
| 167 | createContext | createContext<T>(key) | ❌ | ❌ | ❌ | no Lit context — bus seam is the cross-boundary channel · Tier 1: not modeled |
| 168 | @provide decorator | @provide({context}) | ❌ | ❌ | ❌ | no Lit context — bus seam is the cross-boundary channel · Tier 1: not modeled |
| 169 | @consume decorator | @consume({context, subscribe}) | ❌ | ❌ | ❌ | no Lit context — bus seam is the cross-boundary channel · Tier 1: not modeled |
| 170 | ContextProvider controller | new ContextProvider(...) | ❌ | ❌ expected: controller API | ❌ | no Lit context — bus seam (setBus/BusClient) is the cross-boundary channel |
| 171 | ContextConsumer controller | new ContextConsumer(...) | ❌ | ❌ expected | ❌ | no Lit context — bus seam (setBus/BusClient) is the cross-boundary channel |
| 172 | ContextRoot | new ContextRoot() | ❌ | ❌ | ❌ | no Lit context — bus seam is the cross-boundary channel · Tier 1: not modeled |
| 173 | Task | @lit/task | ❌ | 🟡 expected: Elixir async → Task | 🔌 | host-level async + setParams/onAction replicates the pattern |
| 174 | Task class | new Task(host, opts) | ❌ | 🔌 via behaviors.add escape hatch | ❌ | Task is controller-based; reachable through behaviors.add · Tier 2: needs Lit controller host |
| 175 | Auto-run vs manual | autoRun option | ❌ | ❌ | ❌ | no Task to configure · Tier 1: JS-side only |
| 176 | Task abort signal | {signal} | ❌ | ❌ | ❌ | no Task abort support · Tier 1: JS-side only |
| 177 | Task chaining | output → args | ❌ | ❌ | ❌ | no Task chaining · Tier 1: JS-side only |
| 178 | Signals | @lit-labs/signals | ❌ | ❌ expected: incompatible with compiled output | 🔌 | Tier 1: Signals are a state management alternative; Tier 1 uses Lit's built-in reactivity. · Tier 2: host may run @lit/signals outside; compute → setProps |
| 179 | signal() | signal(val) / get/set | ❌ | ❌ | ❌ | no template integration |
| 180 | computed() | computed(() => expr) | ❌ | ❌ | ❌ | no template integration |
| 181 | SignalWatcher mixin | SignalWatcher(LitElement) | ❌ | ❌ (not compatible with compiled class) | ❌ | no template integration |
| 182 | watch() directive | watch(signal) | ❌ | ❌ | ❌ | no template integration |
| 183 | Signals html tag | html from @lit-labs/signals | ❌ | ❌ | ❌ | no template integration |
| 184 | signal-utils | SignalArray, @signal | ❌ | ❌ | ❌ | no signal ecosystem |
| 185 | React wrapper | @lit/react createComponent | 🔌 Available for hand-written elements | 🔌 manual | 🔌 Wrapper can be wrapped for React | Tier 1: react.html drives plain custom elements via React 18; no createComponent generation |
| 186 | useController() hook | @lit/react/use-controller.js | ❌ | ❌ | ❌ | needs Lit controller host |
| 187 | Localization | @lit/localize | ❌ | ❌ | ❌ | no Lit template layer to localize · Tier 1: no gettext/i18n DSL |
| 188 | Virtualizer | @lit-labs/virtualizer | ❌ | 🔌 Usable with compiled Lit elements | 🔌 | wrap element with any host-side virtualizer; template-level ❌ |
| 189 | Motion | @lit-labs/motion | ❌ | 🔌 Usable with compiled Lit elements | ❌ | directive-based — no template directives |
| 190 | Router | @lit-labs/router | ❌ | 🔌 Usable with compiled Lit elements | ❌ | Hologram routes pages, not elements |
| 191 | Observers | @lit-labs/observers | ❌ | 🔌 Usable with compiled Lit elements (controller-based, so limited) | ❌ | controller-based — no controller host |
| 192 | Scoped registry mixin | @lit-labs/scoped-registry-mixin | ❌ | 🔌 subclassing | 🔌 | tag→module map is per-runtime-instance; customElements global registry caveat · Tier 1: usable via subclassing only, not generated |
| 193 | Wrapper generators | @lit-labs/gen-wrapper-* | ❌ | ❌ | 🔌 Generate from wrapper CEM | Tier 1: not implemented |
| 194 | Custom Elements Manifest | @custom-elements-manifest/analyzer | ✅ Generated from spec DSL (`Codegen.cem/1`; `mix tessera.cem` / `tessera.manifest`) + interactive gallery (`mix tessera.gen.gallery`) | ❌ | 🔌 Analyze wrapper classes | CEM (schemaVersion 1.0.0) is generated from the spec DSL — attrs/props (name, type, default), events + detail schema, slots, cssProperties, cssParts; `mix tessera.gen.gallery` scaffolds a live gallery from it. `contract.generated.mjs` remains the separate wire contract, not the CEM. |

### 2.14 Tooling and DX

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 195 | Experimental decorators | @property() + tsconfig | 🔌 Hand-written | ❌ decorator-free output | 🔌 Wrapper uses decorators | Tier 1: output is decorator-free static properties (golden fixture:11-16) — prior cell description contradicted the fixture |
| 196 | Standard TC39 decorators | @property() accessor | ❌ | ❌ | 🔌 Wrapper can use either | Tier 1: static properties only; 'either decorator mode' is false |
| 197 | No-decorator API | static properties | ❌ | ✅ confirmed: output IS static properties | 🔌 Wrapper can use static properties | Tier 1: golden fixture:12-16 — prior 🟡 was an underclaim |
| 198 | TypeScript types | Type declarations | 🔌 Lit types | ❌ | 🔌 plain-JS wrapper | Tier 1: only .mjs emitted; no .d.ts · Tier 2: plain-JS wrapper — no Lit/TS types shipped |
| 199 | HTMLElementTagNameMap | declare global { ... } | 🔌 Hand-written | ❌ | 🔌 Wrapper auto-generates | Tier 1: not generated |
| 200 | Dev-mode warnings | Automatic in dev build | 🔌 Lit dev build | 🔌 Lit dev build for compiled output | 🔌 plain-HTMLElement wrapper | Tier 2: plain-HTMLElement wrapper — no Lit dev build |
| 201 | Warning suppression | LitElement.disableWarning(...) | ❌ | 🔌 Available | 🔌 Available | |
| 202 | lit-analyzer / lit-plugin | VS Code extension | 🔌 Works with .js output | 🔌 Works with compiled .js output | 🔌 Works with wrapper .js | |
| 203 | eslint-plugin-lit | ESLint plugin | 🔌 In JS toolchain | 🔌 In JS toolchain | 🔌 In JS toolchain | |
| 204 | Polyfills | @webcomponents/webcomponentsjs | 🔌 Available | 🔌 Available | 🔌 Available | |
| 205 | Browser support | ES2021 browsers | 🔌 Standard | 🔌 Standard | 🔌 Standard | |

### 2.15 Packaging and Distribution

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 206 | ESM only | "type": "module" | 🔌 Standard | 🔌 Compiled output is ESM | 🔌 Wrapper is ESM | |
| 207 | Do not bundle rule | peerDependencies on lit | 🔌 Manual | 🔌 runtime variant only | 🔌 Wrapper respects this | Tier 1: default ESM/UMD variants inline lit (spike doc §5); only the runtime variant externalizes lit via import map |
| 208 | CDN usage | import from CDN URL | 🔌 Available | 🔌 Compiled output works from CDN | 🔌 Wrapper works from CDN | |
| 209 | Dedup and multiple Lit versions | npm dedupe | 🔌 Consumer concern | 🔌 Consumer concern | 🔌 Consumer concern | |
| 210 | customElements.define collision | Try/catch or scoped registry | 🔌 Manual | ✅ expected: auto-scoping | 🔌 Wrapper auto-registers | |
| 211 | File extensions in imports | import './x.js' | 🔌 Manual | ✅ expected: auto-generated | 🔌 Manual | |
| 212 | Self-registration | @customElement calls define | 🔌 Hand-written | ✅ expected: auto-generated | 🔌 Wrapper auto-registers | |
| 213 | Export the class | export class MyEl | 🔌 Hand-written | ✅ expected: auto-generated | 🔌 Wrapper exports class | |
| 214 | Production build (Rollup) | Rollup + plugins | 🔌 Manual | 🔌 Standard Rollup build | 🔌 Standard build | |
| 215 | Vite HMR | vite-plugin-web-components-hmr | 🔌 Available | 🔌 Available with Vite | 🔌 Available with Vite | |
| 216 | vite-plugin-lit-css | Import .css as css`` | 🔌 Available | 🔌 Available | 🔌 Available | |

### 2.16 Testing

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 217 | Browser-based testing | Web Test Runner | 🔌 Test Lit elements in browser | 🔌 Test compiled Lit elements in browser | ✅ | Cypress e2e over 3 hosts in flight (element-level, no Hologram test infra needed) — e2e pending |
| 218 | @open-wc/testing | fixture, html, expect | 🔌 Standard Lit testing | 🔌 Standard Lit testing for compiled output | ❌ | no Lit fixture harness — host-mounted Cypress e2e instead |
| 219 | fixture() | await fixture<MyEl>(html`...`) | 🔌 Standard | 🔌 Standard for compiled output | 🔌 | defineElement + createElement |
| 220 | updateComplete in tests | await el.updateComplete | 🔌 Standard | 🔌 Standard | ✅ | Tier 2: the pattern runs as-is on Tier 2 since brief 3c — mutate, `await el.updateComplete`, assert (C-14 Cypress; async-stage dispatches need `await dispatchAction` first) |
| 221 | Shadow DOM queries | el.shadowRoot!.querySelector(...) | 🔌 Standard | 🔌 Standard | ✅ | open root — el.shadowRoot.querySelector from test code |
| 222 | Semantic DOM snapshots | expect(el).shadowDom.to.equalSnapshot() | 🔌 Available | 🔌 Available | 🔌 | serialize open shadow root manually |
| 223 | Accessibility assertions | expect(el).to.be.accessible() | 🔌 Available | 🔌 Available | 🔌 | axe over hosts works; not yet in spec |
| 224 | WebdriverIO alternative | @wdio/globals | 🔌 Available | 🔌 Available | 🔌 | plain ESM/UMD bundles — any runner loads them |
| 225 | Vitest browser mode | vitest browser config | 🔌 Available | 🔌 Available | 🔌 | same — plain ESM/UMD bundles load in any runner |
| 226 | requestAnimationFrame pattern | await rAF() after change | 🔌 Standard | 🔌 Standard | 🔌 | standard DOM API — works unchanged |
| 227 | Web Test Runner config | web-test-runner.config.mjs | 🔌 Standard | 🔌 Standard | ❌ | N/A — Tier 2 tests run Cypress over hosts, not Web Test Runner |

---

## 3. Side-by-Side Comparison

Both tier columns of §2 are now fully investigated against their spikes: Tier 1 against the completed compiler spike (`spike/elixir-to-lit` @ `103c776`), Tier 2 against the in-progress runtime spike (`spike/hologram-runtime-element`, +2517 LOC WIP @ `9db5bb6`, verdicts merged in 6f79246). Every cell carries a verdict with evidence in Notes — except the single open row **#164** (Tier 2 framework SSR integrations, §2.12), kept ❓ with its reason.

Counting convention: raw ✅/🟡/🔌/❌/❓ counts per tier, shown as `✅/🟡/🔌/❌/❓` (⚠ spike-proven rows counted separately, never folded into ✅). Under the Tier 1 audit's folded convention (🟡 + 🔌 reported together), Tier 1 is **70 ✅ / 87 🔌 / 70 ❌** (2026-11-12 declaration recount @ `477d157`, scripted cell-by-cell over the live §2; the 2026-11-11 high-value-directives recount published 64 ✅ / 90 🔌 / 73 ❌, the property-options + lifecycle recount 60 ✅ / 92 🔌 / 75 ❌, the styles-DSL recount 50 ✅ / 94 🔌 / 83 ❌, the original audit 39 ✅ / 95 🔌 / 93 ❌).

### 3.1 Headline counts (per Lit priority)

| Priority | Phase 1 today | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) |
|---|---|---|---|
| P0 (80) | 0/13/62/5/0 | **51**/0/23/**6**/0 | 14/10/46/10/0 |
| P1 (83) | 1/3/39/**40**/0 | 15/2/30/**36**/0 | 10/3/41/26/0 · +3 ⚠ |
| P2 (64) | 0/0/17/47/0 | 4/1/31/28/0 | 6/0/27/28/1 · +2 ⚠ |
| **Total (227)** | 1/16/118/**92**/0 | **70**/3/84/**70**/0 | 30/13/114/**64**/1 · +5 ⚠ |

**2026-11-12 recount (Tier-1 parity declaration).** Scripted recount of every §2 cell at `477d157` (post-2f); supersedes the 2026-11-11 published counts. Delta vs those counts: Tier 1 ✅ 64→**70** (the 2f forms flips #144–#149 dominate; the remainder is §2 cell drift the per-delta notes below never rolled into the table), 🔌 87→84, ❌ 73→70; P0 ❌ stays **6** (#166–#169 context protocol, #195 decorators, #198 .d.ts — all accepted, see gap-acceptance.md). Tier 2 ✅ 10→**30** reflects the 3c/3d/3e flips (lifecycle/state-action/slots/forms) the old table predated; Tier 2 also now carries **5 ⚠** spike-proven SSR rows (4c) counted OUTSIDE ✅ by the recount convention. Phase 1 gains its first ✅ (#194 CEM, D-GAL).

**2026-11-11 delta (high-value directives, `feature/directives` → `epic.tier1-parity`).** Tier 1 flips 4 P0 cells: #56/#57 ❌→✅ (classMap/styleMap) and #47/#68 🔌→✅ (nothing/ifDefined). Evidence: `class_map/1`, `style_map/1`, `if_defined/1` and bare `nothing` lower to the Lit directives in child + attribute position (unquoted, no `__t`); `lit_codegen` emits `import {…, nothing}` and the `lit/directives/{class-map,style-map,if-defined}.js` imports only when used (word-boundary scan of the render body); non-map directive args rejected by name; dual-lexer parity pinned. ExUnit 346 (fast) + core/conformance WTR 105 fast (D-01/D-02/D-06/T-06 green on the compiled `tsr-conf-directives` fixture) + full conformance 36. Also fixed en route: `properties_object/1` emitted `{ , }` (a SyntaxError) for a template-only component with zero attrs/props/state — now `{}`; the `tsr-conf-slots` fixture dropped its dummy-attr workaround and is template-only (regression-pinned). Goldens unchanged (regen reviewed). **Owed follow-up:** the shared-runtime variant must serve `lit/directives/*.js` (explicit re-exports in `tessera-runtime.mjs` + `build-bundles.mjs` external widen + `demo/plain_html` import map) — deferred to the acceptance lane (file ownership); the inlined variant is proven here.

**2026-11-11 delta (directives shared-runtime follow-up, `feature/directives-shared` → `epic.tier1-parity`).** The owed follow-up landed — the shared-runtime variant now serves `lit/directives/*.js`: `tessera-runtime.mjs` explicitly re-exports `classMap`/`styleMap`/`ifDefined` (explicit named re-exports; `export *` is tree-shaken by esbuild), `build-bundles.mjs` runtime-variant externals widened to `lit` + `lit/*` + `@noizu/tessera-core` (a bare `lit` external does NOT match the subpath specifiers — directive code was silently inlined into every runtime bundle), and the `demo/plain_html/react.html` import map maps the three `lit/directives/*.js` specifiers at the shared runtime (one directive module instance). Proof vehicle: new `spike-directive-demo` component (class_map/style_map/if_defined/nothing, child + attribute position) bundled BOTH ways — the runtime variant's only imports are the externals (2.6 KiB vs 29.1 KiB inlined) and its element's prototype chain bottoms out at the SHARED runtime's `LitElement` (single-instance proof, no inlined second lit). New WTR lane `npm run test:runtime` (dedicated config: `nodeResolve: false` + import map injected via `testRunnerHtml`, mirroring the demo topology; the inlined bundle proven standalone in its own page) 6/6 green; default lane 54/54 incl. 5 new source-level D-01/D-02/D-06/T-06 tests; spike ExUnit green. #47/#56/#57/#68 evidence now covers both variants.

**2026-11-11 delta (property options + lifecycle + ?attr + Array, `feature/prop-options` → `epic.tier1-parity`).** Tier 1 flips 10 cells: P0 #7/#11/#22/#34/#43 ❌→✅ (5); P1 #6/#23/#31 ❌→✅ and #10/#21 🔌→✅ (5). Evidence: `attribute:`/`reflect:` DSL opts + `:list`→Array, `should_update`/`will_update`/`first_updated`/`updated` hooks with the `changed` old-value snapshot, `?attr={expr}` under BOTH lexers, prop constructor defaults, map/list JSON coercion in the mixin. ExUnit 145 (targeted) + spike_kit ExUnit 12 + spike_kit WTR 41 (C-01…C-15, T-03, LC-01…LC-04) + core WTR 81; element golden regenerated + reviewed. Also fixed en route: `<slot></slot>`/fallback under the Hologram lexer (Hologram treats slot as void — reserved-placeholder pre-pass), which un-broke the demo/hologram_app compile.

**2026-11-11 delta (styles DSL, `feature/styles-dsl` → `epic.tier1-parity`).** Tier 1 flips 12 §2.5 cells: P0 #79/#83 🔌→✅ and #81/#82/#84/#85/#90/#92 ❌→✅ (8); P1 #87/#91/#98 ❌→✅ (3); P2 #89 ❌→🟡 (parts exposed, exportparts still unmodeled). Evidence: `styles` DSL + composed `static styles` codegen, CEM `cssProperties`/`parts`, ExUnit 214 + spike_kit WTR 20 (S-01…S-06, X-14) + core WTR 80. The original audit's counts (32/0/29/19 P0, 39/2/93/93 total) are preserved in the delta note above for provenance.

**Corrected gap framing (supersedes the old "Tier 1 P0 gap: 0" claim; recount 2026-11-11).** The audit removes the earlier claim that no P0 feature is strictly missing. Tier 1 now has **6 unsupported P0 features** (was 19 before the styles DSL, 13 before property options + lifecycle, 8 before the high-value directives). The update-time seam now EXISTS — the lifecycle DSL (`should_update`/`will_update`/`first_updated`/`updated`) covers willUpdate/updated/changedProperties, and the four high-value directives (classMap/styleMap/nothing/ifDefined) now have per-binding child + attribute position (1d). The remaining band is the **rest of the directive pipeline** (repeat/cache/guard/live/keyed/unsafeHTML/unsafeSVG) plus controller hostUpdate/hostUpdated. Author CSS is no longer part of the gap — the `styles` DSL covers it. The escape hatches (`behaviors.add` + subclassing) remain real for imperative DOM and controller-shaped features at element granularity, but they do not reach per-binding template positions.

**Corrected Tier 2 status (supersedes the old "spike not started / zero commits" claim).** Tier 2 is no longer a paper architecture: `spike/hologram-runtime-element` carries a working wrapper — a plain `TesseraHoloElement extends HTMLElement` with an open shadow root and the Hologram interpreter/snabbdom inside, **no LitElement anywhere** — and its §2 verdicts are spike-confirmed. Where Tier 2 wins it wins on runtime reality: server round-trips, actions, live state, and a native `isServer` split (#161).

### 3.2 Where each tier wins (§2 section by section)

- **2.1 Component model.** Tier 1's compiled output literally `extends TesseraElement(LitElement, contract)` with `defineOnce`-guarded auto-registration — the Lit class surface (render, requestUpdate, updateComplete) is real Lit, inherited wholesale. Since 1c the DSL also exposes the update lifecycle as an authoring surface: `should_update`/`will_update`/`first_updated`/`updated` lower to the Lit hooks with a `changed` old-value snapshot (C-13/C-15, LC-01…LC-04 WTR); getUpdateComplete remains ❌ (subclass-only). Tier 2 has no LitElement at all, so Lit's class lifecycle is absent by construction; what it owns is Hologram's init/teardown mapping onto connected/disconnected callbacks.
- **2.2 Reactive properties.** Both cover the P0 core (attr declarations, `@state`, static properties, attr→prop conversion, boolean semantics, immutable-update detection). Tier 1's generated `static properties = {key: {type, …options}}` is decorator-free and contract-driven: since 1c it carries `attribute:` rename/disable and `reflect: true`, and all five types map (list→Array); custom `converter:`/`hasChanged:` fns remain outside the subset (codegen pass-through only, 4a escape-hatch ballot). Tier 2 does manifest-typed casting plus tsr-props JSON but also has no reflection — attrs flow one-way in. Phase 1's hand-written bridge is the only place custom converter/hasChanged remain reachable.
- **2.3 Templates.** Tier 1 compiles a fixed-grammar DSL to real lit-html: child/attr parts, `$event`→`@event`, `?attr={expr}` boolean bindings (both lexers, T-03), `{%if}` ternaries, `{%for}`→`Array.prototype.map`, nested templates, lit-native caching. Tier 2's renderer is Hologram's own (no lit-html), but its conditionals and lists are native to that system. Tier 1 rejects component tags at compile time; `<slot>…</slot>` with fallback content parses under both lexers (Hologram-void workaround via reserved placeholder). Tier 2 has no lit-html parts at all.
- **2.4 Directives.** Tier 1 (1d) has a directive pipeline for the four high-value directives: `class_map`/`style_map`/`if_defined`/`nothing` lower to classMap/styleMap/ifDefined/nothing in child + attribute position (unquoted, no `__t`) with conditional `lit/directives/*` imports (D-01/D-02/D-06/T-06 WTR). The rest — repeat/cache/guard/live/keyed/unsafeHTML/unsafeSVG — are still ❌; when/map/join are ternary or Array-method lookalikes, not the directives; custom/async directives survive only as behaviors.add element-granularity approximations. Tier 2's wrapper could use directives in its own markup, but none apply to Hologram-rendered content.
- **2.5 Styles.** Tier 1 (2026-11-11) has a real Elixir CSS DSL: `styles` accepts `~CSS` blocks, plain strings and `{:shared, "path.mjs"}` modules, composing `static styles = [baseStyles, …author entries]` in declaration order. `:host`/`:host([attr])`/`:host(.class)`/`::slotted()` pass through verbatim; `var(--tsr-<tag>-*, fallback)` reads require a fallback at compile time and are declared in the CEM (`cssProperties`), as are the host `root` part and template `part="…"` names (`cssParts`). Theming via ancestor `--tsr-*` overrides is WTR-verified (S-01…S-06, X-14). Still unmodeled: `:host-context` (untested passthrough), `unsafeCSS` (deliberate), shadowRootOptions/delegatesFocus, light-DOM render root, a two-level token DSL, and composite `exportparts`. Tier 2 keeps a wrapper static styles with Hologram content styled in its own system.
- **2.6 Shadow DOM.** Tier 1 slots work via markup passthrough (its `slot` declaration validates but is never consumed by codegen). Tier 2 (brief 3e) wires the whole slot family: Hologram void-parses `<slot>` and BOTH renderers substitute slot nodes, so markup passthrough is impossible — instead the shim rewrites `data-tsr-slot` marker vnodes into real `<slot>` elements before each patch, giving default/named assignment, fallback content (the marker's children survive the void parse), `assignedElements`/`assignedNodes`, and slotchange→action routing via `data-tsr-slot-change` (Hologram's `$event` whitelist has no slotchange — non-Lit authoring, honestly divergent). SD-01…SD-04 green on the Tier-2 Cypress harness. The @query family is behaviors.add-reachable in Tier 1 and shadowRoot-queryable in Tier 2's open root; closed shadow roots are unavailable in Tier 1 (no shadowRootOptions emission).
- **2.7 Events.** Tier 1's `emit/2` is a real composed+bubbles CustomEvent with camelCase detail keys — the P0 event path is solid — but fixed-shape: no cancelable, no listener options, no conditional binding, no dispatch-after-render, one-way detail. Tier 2 wins the richer patterns: composed bubbling by design, and the onAction-intercept request/response shape (#123) is one of its ✅s (e2e pending).
- **2.8 Reactive controllers.** Neither tier has the controller host API. Tier 1's behaviors.add matches hostConnected/hostDisconnected and multi-behavior composition, but hostUpdate/hostUpdated are ❌ — behaviors have no update-time hook. Tier 2 offers subclass connected/disconnected hooks with the same update-phase hole.
- **2.9 Composition.** Tier 1 compiles single components, not trees: component tags are rejected at compile time and lowercase tags pass as static markup, so nested composition is 🔌 static-markup only; props-down/events-up and slots still work. Tier 2 nests Hologram components inside the wrapper naturally. Mixins for both mean plain JS subclassing.
- **2.10 Forms.** Both tiers have full form association: manifest-declared `formAssociated` driven by the spec DSL `form_associated` (Tier 1: brief 2f, spec field → put-if-declared manifest key → `static formAssociated = true` emission in all three templates; Tier 2: brief 3e manifest hook, spec-driven `form_associated` read lands in 3f), constructor-gated `ElementInternals` exposed as `el.internals` with the §6.7 negative pinned, `setFormValue`/`setValidity` through the documented push-per-render subclass seam, and `formResetCallback`/`formDisabledCallback` as overridable base no-ops. FM-01…FM-03 run as SHARED case bodies on both harnesses (WTR + Cypress) — one spec, two engines. Tier 1 also pins §6.5 behaviors + §8.4 pinning end-to-end: X-12 (add/connect/cleanup, throw isolation, remove, unsubscribe — unsubscribe-returning `behaviors.add`) and the skip-on-major/minor-warn-only gate (Q1/U3) are green on the WTR suite; behaviors are checked at CONNECT, never at registration.
- **2.11 Accessibility.** Both pass ARIA attributes through templates; delegatesFocus is unmodeled in Tier 1 (not emitted — a corrected cell) and wrapper-set in Tier 2.
- **2.12 SSR.** Tier 2 owns the section's ✅: a native server/client split (`isServer`, #161) with real server round-trips — no Lit SSR machinery needed. Tier 1's SSR story is uniformly 🔌-unproven: architecturally plausible (decorator-free output, DOM-free import, SSR-safe `defineOnce`) but the spike contains zero SSR proof. **Spike 4c flipped Tier 2's #155/#156/#157/#158/#160 to spike-proven (GO verdict, deltas enumerated in `docs/notes/ssr-dsd-spike.md` §4 — none shipped yet); Declarative Shadow DOM remains unimplemented in production and unproven in Tier 1.**
- **2.13 Labs / ecosystem.** Tier 1's compiled elements sit under ecosystem tooling that operates on rendered elements (virtualizer, CDN consumption), but everything requiring author-side Lit APIs — context protocol, localize, CEM, wrapper generators, .d.ts — is ❌; React integration is manual custom-element usage, not `createComponent` generation. Tier 2's cross-boundary channel is the bus seam (setBus/BusClient) instead of @lit/context; its React/CEM stories are wrapper-level.
- **2.14 Tooling and DX.** The audit flipped the old story: Tier 1 output is decorator-free static properties — the no-decorator API is ✅ (underclaim corrected) while the experimental/TC39 decorator rows are ❌ (the old "output uses standard Lit decorators" contradicted the fixture). No .d.ts or HTMLElementTagNameMap is generated; lint/analyze/dev-warnings ride the emitted Lit class. Tier 2 keeps plain-HTMLElement tooling parity.
- **2.15 Packaging.** Tier 1 is the distribution story: proven ESM/UMD/runtime-variant bundles, `defineOnce` collision-safe registration, explicit `.mjs` imports, top-level self-registration, class export — with one corrected caveat: default variants inline lit, so the do-not-bundle rule holds only via the import-mapped runtime variant. Tier 2 ships plain ESM/UMD wrapper bundles.
- **2.16 Testing.** Tier 1 is tested the Lit way: a 10/10 Web Test Runner suite ran over generated elements with @open-wc/testing (arguably ✅ per the audit). Tier 2 inverts it: real-browser Cypress e2e over hosts is ✅-shaped while the @open-wc fixture/updateComplete harness is ❌ (sync returns). Both are genuinely browser-tested; the harnesses differ.

**Extension contract (both tiers feed it).** The stable consumer surface is EXTENSION-CONTRACT.md v0.1 (commit ed15a5a, user-confirmed). Because there is no `super` in Hologram IR, overridden actions get an injected `base_action/3` dispatcher plus `defoverridable`; same-tag extension layers via `use Base, tag: :inherit, priority: n` behind the X-19 base-suite gate; extension registrations are static MFA lists (no runtime bloat); same-version coexistence is safe, and a version mismatch resolves last-writer-wins. Cite the contract for semantics — this section does not restate them.

### 3.3 Parity roadmap

**Tier-1 parity declared 2026-11-12** (see the declaration at the top of this file). Per the approved parity plan (2026-11-11), updated at declaration:

1. **Tier 1 leads the implementation lane — DONE.** The only tier with a completed, byte-proven compiler spike and real packaging; its P0 is closed: the ❌ band shrank 19 → 13 → 8 → **6 accepted rows** (#166–#169 context protocol via the bus-seam hatch, #195 decorator-free-by-design, #198 no-.d.ts) across the styles DSL (1b), property options + lifecycle (1c), and the high-value directives (1d) briefs. The remaining directive band (repeat/cache/guard/live/keyed/unsafeHTML/unsafeSVG) and controller update hooks are accepted, not owed.
2. **The extension contract is the deliverable — Tier 1 complete, Tier 2 mid-flight.** Both tiers compile into it; consumers target it, not tier internals. Tier 1: 2a–2f landed (state/action pipeline, extension_api + CEM, canonical derivation macro, regions/rename/type-guard, takeover chain + `extendElement`, behaviors pin + forms); X-01…X-21 pinned except X-02/X-13 (registry-pending bodies, queued after 3f) and X-16 (Tier-1-proven via spike_kit; shared case rides 3f). Tier 2: 3c/3d/3e landed (lifecycle, state/action, slots/forms).
3. **The universal gaps are accepted — final set 40.** Recounted 2026-11-12 (`gap-acceptance.md` §0): **34 accepted-with-hatch · 6 accepted-design-choice**; #178 (Signals) is one-sided (Tier 1 ❌ / Tier 2 🔌) and sits outside the ballot; forms (#144–#149) and the SSR family are resolved with dispositions there, not balloted. The per-category owner ballot (§6 there) is **OPEN**.
4. **Tier 2 continues as the WIP stateful-component lane** behind the same contract. What remains is **brief 3f as the FOLLOW-UP to this milestone** (in flight, worktree `tier2-macro`): Tier-2 reuse of the canonical `use Vendor.Element` macro, X-16/X-19 exercised on Tier 2, the cross-runtime CompileError decision, plus the `form_associated` spec declaration path on Tier 2. SSR is **spike-proven, production-owed** (4c GO-conditional; deltas in `docs/notes/ssr-dsd-spike.md` §4) and was never a Tier-1 gate; #164-class framework-integration questions ride the Phase-2 host-swap work.

**What's next (post-declaration, in order):** ① brief **3f** — Tier-2 canonical-macro reuse + X-16/X-19 on Tier 2 + cross-runtime CompileError + the X-16 shared registry case; ② SSR production work — host adoption + vnode-sel normalization + init/3 author-contract enforcement + SSR conformance cases (4c §4 list); ③ X-02/X-13 conformance case bodies (after 3f, same file); ④ owner gap-acceptance ballot + the two open owner questions (§5.6 two-layer rename chaining; pinned `extension_api` requirement-string vs resolved version); ⑤ **hex publish** (`noizu_tessera` 0.1.0 is publish-ready, deferred until after parity — now unblocked by this declaration).

**Decision framing.** Choose **Tier 1** when the goal is Lit-grade interop and distribution — npm/UMD/import-map consumption, ecosystem tooling over rendered elements, zero-JS authorship from Elixir. Choose **Tier 2** when the goal is stateful Hologram-native components — server round-trips, actions, live state, native server/client split. Neither approximates the other's core: Tier 1 cannot model the Hologram runtime; Tier 2 cannot model Lit's update lifecycle, directives, or styles DSL. Both feed the same extension contract.

## 4. How to Measure Parity

A conformance test suite that both tiers can run. Each test is a Lit component behavior; the test passes if the tessera component (regardless of tier) behaves identically.

### 4.1 Proposed Conformance Suite

| Test ID | Feature | Test Description | Lit Reference |
|---------|---------|-----------------|---------------|
| C-01 | Element registration | Define a component; verify `customElements.get('test-el')` returns the class | @customElement |
| C-02 | Property → attribute | Set a string property; verify the HTML attribute matches | @property, attribute |
| C-03 | Attribute → property | Set an HTML attribute; verify the property reflects the parsed value | attribute→property conversion |
| C-04 | Boolean attribute | Toggle Boolean attribute presence; verify property is true/false | @property({type: Boolean}) |
| C-05 | Number attribute | Set numeric attribute; verify property is a number | @property({type: Number}) |
| C-06 | Object attribute | Set JSON attribute; verify property is parsed object | @property({type: Object}) |
| C-07 | @state reactivity | Change internal state; verify re-render | @state |
| C-08 | No re-render on same value | Set property to same value; verify no re-render (hasChanged) | hasChanged default |
| C-09 | Property reflection | Set property; verify HTML attribute updates (reflect: true) | reflect |
| C-10 | Custom attribute name | Declare property with custom attribute name; verify mapping | attribute: 'my-prop' |
| C-11 | connectedCallback | Insert element into DOM; verify callback fires | connectedCallback |
| C-12 | disconnectedCallback | Remove element from DOM; verify callback fires | disconnectedCallback |
| C-13 | firstUpdated | Verify callback fires once after first render | firstUpdated |
| C-14 | updateComplete | Change property; await updateComplete; verify DOM updated | updateComplete |
| C-15 | shouldUpdate skip | Return false from shouldUpdate; verify no re-render | shouldUpdate |
| LC-01 | willUpdate before render | Hook fires before render; `changed` carries OLD values (undefined on first update); DOM still shows the pre-update value at hook time | willUpdate(changedProperties) |
| LC-02 | updated after each render | Hook fires after every rendered update, in order willUpdate → render → firstUpdated (first only) → updated; vetoed updates fire nothing | updated(changedProperties) |
| LC-03 | firstUpdated once | Hook fires exactly once across the element's lifetime, after the first render | firstUpdated(changedProperties) |
| LC-04 | changedProperties old values | `changed.<prop>` is the previous value keyed by property name (camelCase attrs/props, snake state); a plain-object snapshot, not a live Map | changedProperties |
| T-01 | Child expression | Render `${value}`; verify text appears in DOM | html child expression |
| T-02 | Attribute expression | Render `class=${cls}`; verify attribute set | attribute expression |
| T-03 | Boolean attribute expression | Render `?hidden=${flag}`; verify attribute presence/absence | boolean attribute |
| T-04 | Property expression | Render `.value=${val}` on input; verify input value | property expression |
| T-05 | Event listener expression | Render `@click=${handler}`; click element; verify handler called | event expression |
| T-06 | nothing sentinel | Render `${nothing}`; verify no nodes | nothing |
| T-07 | Conditional rendering | Toggle condition; verify correct branch renders | when/when/ternary |
| T-08 | List rendering | Map over array; verify correct number of child nodes | map/map |
| T-09 | Nested templates | Render nested html``; verify composition | nested templates |
| D-01 | classMap | Apply dynamic class map; verify class attribute | classMap |
| D-02 | styleMap | Apply dynamic style map; verify style attribute | styleMap |
| D-03 | when directive | Pass true/false condition; verify correct template | when |
| D-04 | choose directive | Pass different cases; verify correct template | choose |
| D-05 | repeat with keys | Reorder items; verify DOM nodes reorder (not replace) | repeat |
| D-06 | ifDefined | Pass undefined; verify attribute not present | ifDefined |
| D-07 | ref directive | Create ref; after render verify ref.value is the element | ref |
| S-01 | :host style | Define :host style; verify applied to host | :host selector |
| S-02 | :host([attr]) | Toggle attribute; verify :host conditional style | :host([attr]) |
| S-03 | ::slotted() | Slot a child; verify ::slotted style applies | ::slotted() |
| S-04 | CSS custom property | Define var(--custom-prop); set on parent; verify applied | CSS custom properties |
| S-05 | Shared styles | Import shared CSSResult; verify applied | shared style modules |
| S-06 | Static styles array | Compose [a, b, css``]; verify all apply | style array composition |
| SD-01 | Default slot | Pass light DOM child; verify slotted | `<slot>` |
| SD-02 | Named slot | Pass element with slot="x"; verify in correct slot | `<slot name="x">` |
| SD-03 | Slot fallback | Don't pass slotted child; verify fallback renders | slot fallback |
| E-01 | CustomEvent dispatch | Dispatch CustomEvent with detail; verify listener receives detail | dispatchEvent |
| E-02 | bubbles: true | Dispatch bubbling event; verify parent receives it | bubbles |
| E-03 | composed: true | Dispatch composed event; verify crosses shadow boundary | composed |
| CT-01 | Context provide/consume | Provide context value; verify consumer reads it (within shadow tree) | @lit/context |
| CT-02 | Context subscription | Change provided value; verify consumer re-renders (subscribe: true) | @consume subscribe |

### 4.2 Running the Suite

Each test is a self-contained HTML page that:
1. Imports the component under test
2. Mounts it via `fixture()` (or equivalent)
3. Exercises the feature
4. Asserts the expected behavior

Tests use `@open-wc/testing` for Lit-native components. Tier 2 (Hologram) components need a bridge test harness that mounts the component inside a test DOM and waits for Hologram to initialize before asserting. The conformance suite should define the expected behavior, not the test runner — each tier provides its own runner adapter.

**Tier 1 coverage (2026-11-11, brief 1c).** C-01…C-15, T-03 and LC-01…LC-04 are asserted against the generated `<spike-props>` element in `examples/spike_kit/test/components/props_panel_test.mjs` (WTR, 41 tests incl. the counter/toggle_chip/styles_panel suites); C-11/C-12 observe connect/disconnect through the `behaviors.add` seam. The LC family is handed to brief 4b's harness as the lifecycle conformance rows.

---

*End of parity matrix. 227 features inventoried across 16 areas. Matrix covers Phase 1 (tessera today), Tier 1 (spike/elixir-to-lit @ 103c776), and Tier 2 (spike/hologram-runtime-element @ 9db5bb6). Single remaining ❓: #164 (Tier 2 framework SSR integrations — not exercised in the spike).*