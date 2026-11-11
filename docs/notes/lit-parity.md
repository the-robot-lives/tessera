# Lit Feature Inventory & Tessera Parity Matrix

> Generated: 2026-11-11 | Session: `8cab005e-11cf-42b8-8a29-9aff00f6bec0`
>
> Compares the full Lit 3 feature surface against tessera's three implementation tiers:
> - **Phase 1 (tessera today)**: Hand-written Lit elements beneath an Elixir contract layer.
> - **Tier 1 (spike/elixir-to-lit)**: Compile an Elixir subset directly to Lit element output.
> - **Tier 2 (spike/hologram-runtime-element)**: Host a Hologram component inside a custom element wrapper.

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
- ❓ = pending spike investigation (no notes file yet, or notes don't address this feature)

### 2.1 Component Model

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 1 | LitElement | `extends LitElement` | 🔌 Hand-written Lit elements beneath Elixir layer | ✅ expected: compiled output IS LitElement | 🟡 expected: Hologram component hosted inside custom element; LitElement is the wrapper shell | Tier 2: wrapper is a thin LitElement delegating to Hologram |
| 2 | ReactiveElement | `extends ReactiveElement` | 🔌 Inherited via LitElement | 🔌 Inherited via LitElement | 🔌 Inherited via wrapper LitElement | Tier 1/2 both have this from Lit underneath |
| 3 | @customElement | `@customElement('tag')` | 🔌 Hand-written on wrapper class | ✅ expected: generated from Elixir module name | ✅ expected: wrapper registers the element tag | |
| 4 | connectedCallback | super.connectedCallback() | 🔌 Via Lit element lifecycle | 🔌 Via compiled LitElement | 🟡 expected: Hologram init hooks map to this | |
| 5 | disconnectedCallback | super.disconnectedCallback() | 🔌 Via Lit element lifecycle | 🔌 Via compiled LitElement | 🟡 expected: Hologram teardown maps to this | |
| 6 | shouldUpdate | shouldUpdate(cp): boolean | 🔌 Can be overridden in hand-written elements | 🟡 expected: compilable from Elixir guard/condition | ❓ | |
| 7 | willUpdate | willUpdate(cp) | 🔌 Via Lit element lifecycle | ✅ expected: maps to Elixir lifecycle callback | ❓ | |
| 8 | update | update(cp) | 🔌 Via Lit element lifecycle | 🔌 Via compiled LitElement | ❓ | Rarely overridden directly |
| 9 | render | render(): TemplateResult | 🔌 Hand-written in Lit element | ✅ confirmed: `~TSR"""..."""` template DSL compiles to lit-html `render()` | 🟡 expected: Hologram's own rendering, not Lit's | Spike: dual-lexer parses `{expr}`, `{%if}/{%for}`, `$event`; generates `html``` in render() |
| 10 | firstUpdated | firstUpdated(cp) | 🔌 Can be overridden in hand-written elements | ✅ expected: maps to Elixir mount/init callback | ❓ | |
| 11 | updated | updated(cp) | 🔌 Via Lit element lifecycle | ✅ expected: maps to Elixir update callback | ❓ | |
| 12 | updateComplete | await this.updateComplete | 🔌 Via Lit element | 🔌 Via compiled LitElement | 🟡 expected: Hologram has its own update tracking | |
| 13 | getUpdateComplete | async getUpdateComplete() | 🔌 Can be overridden | 🟡 expected | ❓ | |
| 14 | requestUpdate | this.requestUpdate() | 🔌 Via Lit element | ✅ expected: triggered by Elixir state changes | 🟡 expected: Hologram triggers re-render, wrapper propagates | |
| 15 | scheduleUpdate | async scheduleUpdate() | 🔌 Via Lit element | ❓ | ❓ | Advanced scheduler customization |
| 16 | performUpdate | (internal) | 🔌 Lit internal | 🔌 Lit internal | 🔌 Lit internal | |
| 17 | addInitializer | addInitializer(fn) | 🔌 Via Lit element | ❓ | ❓ | |
| 18 | hasUpdated | this.hasUpdated | 🔌 Via Lit element | 🔌 Via compiled LitElement | ❓ | |
| 19 | isConnected | this.isConnected | 🔌 Via Lit element | 🔌 Via compiled LitElement | 🔌 Via wrapper LitElement | |

### 2.2 Reactive Properties

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 20 | @property | @property(opts) | 🟡 Elixir `tsr_prop` maps to @property via bridge | ✅ expected: compiled from Elixir attr declaration | 🔌 wrapper exposes @property that delegates to Hologram state | Tessera today: attrs defined in Elixir contract, bridge generates Lit @property |
| 21 | @property({type}) | type: String/Number/Boolean/Object/Array | 🟡 Elixir types map to Lit types in bridge | ✅ expected: Elixir type → Lit converter | 🔌 wrapper property types map to Hologram types | |
| 22 | @property({attribute}) | attribute: 'my-prop' or false | 🟡 Contract specifies attribute name | ✅ expected | 🔌 wrapper property → Hologram attr | |
| 23 | @property({reflect}) | reflect: true | ❌ Not in Phase 1 contract docs | ✅ expected | ❓ | |
| 24 | @property({converter}) | converter: {fromAttribute, toAttribute} | ❌ | ✅ expected: custom Elixir converter fn | ❓ | |
| 25 | @property({hasChanged}) | hasChanged: (n,o) => bool | ❌ | ✅ expected | ❓ | |
| 26 | @property({noAccessor}) | noAccessor: true | ❌ | ❓ | ❓ | Niche option |
| 27 | @property({useDefault}) | useDefault: true | ❌ | ❓ | ❓ | Lit 3.3+ feature |
| 28 | @state | @state() private _x | 🟡 Elixir internal state mapped via bridge | ✅ confirmed: `state(:count, :integer, default: 0)` generates Lit reactive properties | 🔌 wrapper @state maps to Hologram internal state | Spike: state DSL compiles to `static properties` entries; state keys stay snake_case on the element |
| 29 | static properties | static properties = {...} | ❌ (uses decorators) | ✅ confirmed: generated element uses static properties field | ❓ | Spike golden fixture confirms static properties output |
| 30 | Attribute-to-property conversion | automatic per type | 🟡 Bridge handles attr→prop sync | ✅ expected: Lit handles this natively | 🔌 Lit handles under the wrapper | |
| 31 | Property-to-attribute reflection | @property({reflect: true}) | ❌ | ✅ expected | ❓ | |
| 32 | Attribute name mapping | camelCase → lowercase | 🟡 Contract specifies attr name mapping | ✅ expected | 🔌 wrapper handles attr name mapping | |
| 33 | Boolean attribute semantics | present=true, absent=false | 🟡 Bridge respects Boolean type | ✅ expected | 🔌 wrapper Boolean properties | |
| 34 | changedProperties map | willUpdate(cp) | 🔌 Available via Lit element | ✅ expected | ❓ | |
| 35 | Custom getter/setter | @property() set/get | ❌ | 🟡 expected: Elixir accessor fns | ❓ | |
| 36 | elementProperties metadata | MyElement.elementProperties | 🔌 Available via Lit element | 🔌 Available via compiled LitElement | 🔌 Available via wrapper | |
| 37 | Mutation detection | this.items = [...items, new] | ❌ (JS concern) | ✅ expected: Elixir immutable data pattern | ❓ | |

### 2.3 Templates

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 38 | html tag | html`` | 🔌 Hand-written Lit templates | ✅ expected: compiled from Elixir template DSL | 🔌 Wrapper's render delegates to Hologram; Hologram uses its own template system | Tier 2: Hologram provides its own template language, not Lit's html`` |
| 39 | svg tag | svg`` | 🔌 Hand-written in Lit | 🟡 expected: Elixir SVG template compiles to svg`` | 🔌 via Hologram's rendering | |
| 40 | mathml tag | mathml`` | ❌ | ❓ | ❓ | Lit 3.2+, niche |
| 41 | Child expression | ${expr} | 🔌 Hand-written | ✅ expected | 🔌 via Hologram | |
| 42 | Attribute expression | attr=${val} | 🔌 Hand-written | ✅ expected | 🔌 via Hologram | |
| 43 | Boolean attribute expression | ?attr=${val} | 🔌 Hand-written | ✅ expected | ❓ | |
| 44 | Property expression | .prop=${val} | 🔌 Hand-written | ✅ expected | 🔌 wrapper uses .prop for Hologram state | |
| 45 | Event listener expression | @event=${handler} | 🔌 Hand-written | ✅ expected | 🟡 wrapper listens to Lit events, forwards to Hologram | |
| 46 | Element expression | ${directive()} | 🔌 Hand-written | ❓ | ❓ | |
| 47 | nothing sentinel | import {nothing} | 🔌 Hand-written | ✅ expected | ❓ | |
| 48 | noChange sentinel | import {noChange} | ❌ | ❓ | ❓ | Directive-internal use |
| 49 | Conditional rendering | ternary / when() | 🔌 Hand-written | ✅ confirmed: `{%if}/{%else}/{/if}` in template DSL compiles to ternary in generated JS | 🔌 via Hologram's own conditionals | Spike: if/else in ~TSR templates |
| 50 | List rendering | Array.map / map() | 🔌 Hand-written | ✅ confirmed: `{%for x <- coll}` in template DSL compiles to `map()` directive | 🔌 via Hologram | Spike: for-loop compiles to lit map() |
| 51 | Static expressions (literal) | literal`` / unsafeStatic() | ❌ | ❓ | ❓ | Niche: dynamic tag names |
| 52 | Static expressions (unsafeStatic) | unsafeStatic(str) | ❌ | ❓ | ❓ | |
| 53 | Nested templates | ${html`...`} | 🔌 Hand-written | ✅ expected | 🔌 via Hologram | |
| 54 | Template functions | const fn = (...) => html`...` | ❌ | ✅ expected: Elixir function components | 🔌 via Hologram | |
| 55 | Template result caching | automatic | 🔌 Lit handles this | 🔌 Lit handles this | 🔌 Lit handles this under wrapper | |

### 2.4 Built-in Directives

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 56 | classMap | classMap({...}) | 🔌 Hand-written | ✅ expected: Elixir class list compiles to classMap() | 🔌 wrapper can use classMap | |
| 57 | styleMap | styleMap({...}) | 🔌 Hand-written | ✅ expected | 🔌 wrapper can use styleMap | |
| 58 | when | when(cond, T, F) | 🔌 Hand-written | ✅ expected: compiles from Elixir if | 🔌 wrapper can use when | |
| 59 | choose | choose(val, cases, default) | 🔌 Hand-written | 🟡 expected: Elixir cond/case → choose() | 🔌 wrapper can use choose | |
| 60 | map | map(iter, fn) | 🔌 Hand-written | ✅ expected: Elixir for → map() | 🔌 wrapper can use map | |
| 61 | join | join(items, sep) | ❌ | ✅ expected | ❓ | |
| 62 | range | range(end) / range(s, e, step) | ❌ | ✅ expected | ❓ | |
| 63 | repeat | repeat(items, key, fn) | 🔌 Hand-written | ✅ expected: Elixir keyed for → repeat() | 🔌 wrapper can use repeat | |
| 64 | cache | cache(template) | ❌ | ✅ expected | ❓ | |
| 65 | guard | guard(deps, fn) | ❌ | ✅ expected | ❓ | |
| 66 | live | live(value) | ❌ | ✅ expected | ❓ | |
| 67 | keyed | keyed(key, template) | ❌ | ✅ expected | ❓ | |
| 68 | ifDefined | ifDefined(val) | 🔌 Hand-written | ✅ expected | 🔌 wrapper can use ifDefined | |
| 69 | ref / createRef | ref(this.ref) / createRef() | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | ❓ | ref requires imperative DOM; generated DSL doesn't emit it, but `behaviors.add` on connect provides full element access |
| 70 | until | until(promise, placeholder) | 🔌 Hand-written | 🟡 expected: async values | 🔌 wrapper can use until | |
| 71 | asyncAppend | asyncAppend(asyncIter, fn) | ❌ | ❓ | ❓ | |
| 72 | asyncReplace | asyncReplace(asyncIter) | ❌ | ❓ | ❓ | |
| 73 | templateContent | templateContent(tpl) | ❌ | ❓ | ❓ | |
| 74 | unsafeHTML | unsafeHTML(str) | 🔌 Hand-written | ✅ expected: raw HTML escape hatch | 🔌 wrapper can use unsafeHTML | |
| 75 | unsafeSVG | unsafeSVG(str) | ❌ | ✅ expected | ❓ | |
| 76 | unsafeMathML | (pattern) | ❌ | ❓ | ❓ | |
| 77 | Custom directives | class extends Directive | ❌ | 🔌 via behaviors.add escape hatch | ❓ | Custom directives need imperative DOM; reachable through the behaviors.add hatch |
| 78 | Async directives | class extends AsyncDirective | ❌ | 🔌 via behaviors.add escape hatch | ❓ | Async directives need lifecycle integration; reachable through behaviors.add |

### 2.5 Styles

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 79 | css tag | static styles = css`` | 🔌 Hand-written | ✅ expected: Elixir CSS block compiles to css`` | 🔌 Wrapper has static styles; Hologram styles are separate | Tier 2: Hologram's CSS lives in Hologram's own system |
| 80 | Static styles (Constructable Stylesheets) | static styles | 🔌 Hand-written Lit styles | 🔌 Compiled output uses static styles | 🟡 Wrapper uses static styles; Hologram content styled separately | |
| 81 | Style array composition | [a, b, css``] | 🔌 Hand-written | ✅ expected | 🔌 Wrapper composes styles | |
| 82 | Style inheritance | [...Parent.styles] | 🔌 Hand-written | ✅ expected | 🔌 Wrapper inherits | |
| 83 | :host selector | :host { ... } | 🔌 Hand-written | ✅ expected | 🔌 Wrapper uses :host | |
| 84 | :host([attr]) | :host([active]) | 🔌 Hand-written | ✅ expected | 🔌 Wrapper uses :host([attr]) | |
| 85 | :host(.class) | :host(.primary) | 🔌 Hand-written | ✅ expected | 🔌 Wrapper uses :host(.class) | |
| 86 | :host-context(.theme) | :host-context(.dark) | ❌ | ✅ expected | ❓ | |
| 87 | ::slotted() | ::slotted(p) { ... } | 🔌 Hand-written | ✅ expected | 🔌 Wrapper uses ::slotted | |
| 88 | :defined | my-el:defined | 🔌 Native browser CSS | 🔌 Native | 🔌 Native | |
| 89 | ::part() (exportparts) | ::part(button) | ❌ | ❓ | ❓ | |
| 90 | CSS custom properties | var(--name, fallback) | 🔌 Hand-written | ✅ expected: Elixir design tokens → CSS custom properties | 🔌 Wrapper uses CSS custom properties | |
| 91 | CSS custom property naming | --comp-name-prop | 🟡 Manual convention | ✅ expected | 🟡 Manual convention | |
| 92 | Shared style modules | export const styles = css`` | 🔌 Hand-written | ✅ expected: Elixir shared CSS modules | 🔌 Wrapper imports shared styles | |
| 93 | unsafeCSS | unsafeCSS(str) | ❌ | ✅ expected | ❓ | |
| 94 | shadowRootOptions | static shadowRootOptions | 🔌 Hand-written | ✅ expected: configured in component definition | 🔌 Wrapper sets shadowRootOptions | |
| 95 | delegatesFocus | delegatesFocus: true | 🔌 Hand-written | ✅ expected | 🔌 Wrapper sets delegatesFocus | |
| 96 | createRenderRoot (light DOM) | createRenderRoot() { return this; } | ❌ | ✅ expected | ❓ | Tier 2: Hologram components typically render inside shadow DOM |
| 97 | Design system token pattern | Two-level tokens | 🟡 Manual in CSS | ✅ expected: Elixir token declarations | 🟡 Manual | |
| 98 | Theme switching | CSS custom property overrides | 🔌 Hand-written | ✅ expected | 🔌 Wrapper | |

### 2.6 Shadow DOM

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 99 | Default slot | `<slot></slot>` | 🟡 Elixir `slot` declaration → Lit `<slot>` | ✅ expected: compiled from slot declaration | 🟡 Wrapper `<slot>`; Hologram renders its own content inside | |
| 100 | Named slots | `<slot name="header">` | 🟡 Elixir named slot → named `<slot>` | ✅ expected | 🟡 Wrapper named slots | |
| 101 | Slot fallback content | `<slot>default</slot>` | 🔌 Hand-written | ✅ expected | 🔌 Wrapper | |
| 102 | @query | @query('#id') el | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | ❓ | Imperative DOM reference; reachable through behaviors.add |
| 103 | @queryAll | @queryAll('.cls') els | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | ❓ | |
| 104 | @queryAsync | @queryAsync('#dyn') | ❌ | 🔌 via behaviors.add escape hatch | ❓ | |
| 105 | @queryAssignedElements | @queryAssignedElements({slot}) | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | ❓ | |
| 106 | @queryAssignedNodes | @queryAssignedNodes({slot}) | ❌ | 🔌 via behaviors.add escape hatch | ❓ | |
| 107 | slotchange event | @slotchange=${fn} | 🔌 Hand-written | ✅ expected | ❓ | |
| 108 | assignedElements() | slot.assignedElements() | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | ❓ | Imperative DOM access; reachable through behaviors.add |
| 109 | assignedNodes() | slot.assignedNodes() | ❌ | 🔌 via behaviors.add escape hatch | ❓ | |
| 110 | renderRoot | this.renderRoot | 🔌 Lit internal | 🔌 Lit internal | 🔌 Lit internal | |
| 111 | Open shadow root | mode: 'open' (default) | 🔌 Default | 🔌 Default | 🔌 Default | |
| 112 | Closed shadow root | mode: 'closed' | ❌ | ✅ expected: configurable | ❓ | |

### 2.7 Events

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 113 | @event listener | @click=${handler} | 🔌 Hand-written | ✅ expected: compiles from Elixir event handlers | 🟡 Wrapper listens, forwards to Hologram via bridge | |
| 114 | CustomEvent dispatch | dispatchEvent(new CustomEvent(...)) | 🔌 Hand-written in Lit | ✅ confirmed: `emit/2` in action DSL generates composed CustomEvent dispatch | 🟡 Hologram emits, wrapper dispatches CustomEvent | Spike: `emit("event-name", %{key: val})` compiled to CustomEvent with composed+bubbles; camelCase detail keys at emit boundary |
| 115 | bubbles option | {bubbles: true} | 🔌 Hand-written | ✅ expected | 🔌 Wrapper sets event options | |
| 116 | composed option | {composed: true} | 🔌 Hand-written | ✅ expected | 🔌 Wrapper sets event options | |
| 117 | cancelable option | {cancelable: true} | ❌ | ✅ expected | ❓ | |
| 118 | @eventOptions | @eventOptions({passive: true}) | ❌ | ✅ expected: declarative in component | ❓ | |
| 119 | handleEvent object | {handleEvent: fn, once: true} | ❌ | ❓ | ❓ | |
| 120 | Remove listener with nothing | @click=${active ? fn : nothing} | 🔌 Hand-written | ✅ expected: conditional handler → nothing | ❓ | |
| 121 | Typed CustomEvents | class MyEvent extends Event | ❌ | 🟡 expected: Elixir struct → typed CustomEvent | ❓ | |
| 122 | composedPath() | event.composedPath() | 🔌 Hand-written | 🔌 Native | 🔌 Native | |
| 123 | Bidirectional event pattern | event.detail.response | ❌ | ❓ | ❓ | |
| 124 | Dispatch after render | await updateComplete; dispatch | 🔌 Hand-written | ✅ expected | ❓ | |
| 125 | External listeners | window.addEventListener | 🔌 Hand-written | 🟡 expected: Elixir lifecycle hook | ❓ | |

### 2.8 Reactive Controllers

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 126 | ReactiveController interface | interface ReactiveController | 🔌 Hand-written controllers | 🔌 via behaviors.add escape hatch | ❓ | Controllers require imperative host API; behaviors.add provides connect/disconnect lifecycle matching controller hooks |
| 127 | addController | this.addController(ctrl) | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | ❓ | |
| 128 | hostConnected | hostConnected() | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | ❓ | behaviors.add fn runs on connectedCallback |
| 129 | hostDisconnected | hostDisconnected() | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | ❓ | behaviors.add cleanup fn runs on disconnectedCallback |
| 130 | hostUpdate | hostUpdate() | ❌ | 🔌 via behaviors.add escape hatch | ❓ | |
| 131 | hostUpdated | hostUpdated() | ❌ | 🔌 via behaviors.add escape hatch | ❓ | |
| 132 | Controller requesting update | this.host.requestUpdate() | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | ❓ | behaviors.add receives the element; can call requestUpdate() |
| 133 | Multiple controllers | multiple controller instances | 🔌 Hand-written | 🔌 via behaviors.add escape hatch | ❓ | behaviors registry supports multiple per-tag |
| 134 | Composing controllers | controller owns other controllers | ❌ | 🔌 via behaviors.add escape hatch | ❓ | |
| 135 | Controller + directive pattern | controller exposing ref() | ❌ | 🔌 via behaviors.add escape hatch | ❓ | |

### 2.9 Composition

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 136 | Nested components | `<child-el>` in template | 🟡 Elixir component composition → Lit nesting | ✅ expected: Elixir component tree → nested Lit elements | 🟡 Hologram components nested inside wrapper | |
| 137 | Properties down | .prop=${val} | 🟡 Bridge passes Elixir attrs as Lit properties | ✅ expected | 🔌 Wrapper passes props to child wrappers | |
| 138 | Events up | @event=${handler} | 🟡 Bridge forwards Lit events to Elixir handlers | ✅ expected | 🟡 Hologram events bubble through wrapper | |
| 139 | Mixin pattern | const M = (super) => class extends super | ❌ | 🔌 via subclassing TesseraElement | ❓ | Generated element is a LitElement subclass; consumer can apply mixins through TesseraElement mixin or plain JS subclassing |
| 140 | Mixin with public API | TS interface + Constructor type | ❌ | 🔌 via subclassing TesseraElement | ❓ | |
| 141 | Mediator pattern | Parent owns state, coordinates children | 🟡 Elixir parent component as mediator | ✅ expected: natural in Elixir | ✅ expected: natural in Hologram | |
| 142 | Slot-based composition | `<slot>` elements | 🟡 Elixir slot → Lit slot | ✅ expected | 🟡 Wrapper provides slot; Hologram content renders inside | |
| 143 | Mixin vs Controller decision | Prefer controllers | 🔌 Available in hand-written JS | 🔌 behaviors.add covers controller-like use; mixins via subclassing | ❓ | |

### 2.10 Forms

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 144 | formAssociated | static formAssociated = true | ❌ | ✅ expected: declared in component | ❓ | |
| 145 | ElementInternals | this.attachInternals() | ❌ | 🔌 via behaviors.add escape hatch | ❓ | Imperative API; reachable through behaviors.add on connect |
| 146 | setValidity | internals.setValidity(...) | ❌ | 🔌 via behaviors.add escape hatch | ❓ | |
| 147 | setFormValue | internals.setFormValue(val) | ❌ | 🔌 via behaviors.add escape hatch | ❓ | |
| 148 | formResetCallback | formResetCallback() | ❌ | 🔌 via behaviors.add escape hatch | ❓ | |
| 149 | formDisabledCallback | formDisabledCallback(bool) | ❌ | 🔌 via behaviors.add escape hatch | ❓ | |

### 2.11 Accessibility

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 150 | delegatesFocus | shadowRootOptions.delegatesFocus | 🔌 Hand-written | ✅ expected | 🔌 Wrapper | |
| 151 | ARIA attribute reflection | aria-label, role, etc. | 🔌 Hand-written in template | ✅ expected: Elixir aria attributes → template attrs | 🔌 Hologram renders ARIA attrs | |
| 152 | aria property reflection | (browser native) | 🔌 Native | 🔌 Native | 🔌 Native | |
| 153 | eslint-plugin-lit-a11y | NPM dev dependency | 🔌 Available in tooling | 🔌 Available in tooling | 🔌 Available in tooling | |

### 2.12 SSR

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 154 | @lit-labs/ssr | import {render} from '@lit-labs/ssr' | ❌ | ✅ expected: compiled Lit elements are SSR-able | ❓ | Hologram server-renders HTML and runs compiled-to-JS in browser; open question: can it emit inside Declarative Shadow DOM? Pending Tier 2 spike. |
| 155 | Declarative Shadow DOM | `<template shadowrootmode>` | 🔌 Lit SSR generates this | 🔌 Lit SSR generates for Tier 1 output | ❓ | Pending Tier 2 spike |
| 156 | SSR lifecycle subset | only constructor/willUpdate/render | 🔌 Lit handles | 🔌 Lit handles for compiled output | ❓ | Pending Tier 2 spike |
| 157 | @lit-labs/ssr-client hydration | import hydrate-support | ❌ | ✅ expected: hydrate on client | ❓ | Pending Tier 2 spike |
| 158 | hydrate() function | hydrate(template, container) | ❌ | ✅ expected | ❓ | Pending Tier 2 spike |
| 159 | Streaming SSR | RenderResultReadable | ❌ | ✅ expected | ❓ | Pending Tier 2 spike |
| 160 | collectResult / collectResultSync | collectResult(result) | ❌ | ✅ expected | ❓ | Pending Tier 2 spike |
| 161 | isServer detection | import {isServer} from 'lit' | ❌ | ✅ expected | ❓ | Pending Tier 2 spike |
| 162 | VM module isolation | ModuleLoader | ❌ | ✅ expected | ❓ | Pending Tier 2 spike |
| 163 | defer-hydration attribute | (Lit labs pattern) | ❌ | ✅ expected | ❓ | Pending Tier 2 spike |
| 164 | Framework integrations (SSR) | Astro, Eleventy, Next.js | ❌ | ✅ expected: Tier 1 Lit output works with standard integrations | ❓ | Pending Tier 2 spike |
| 165 | template-shadowroot polyfill | @webcomponents/template-shadowroot | ❌ | 🔌 Polyfill available | ❓ | Pending Tier 2 spike |

### 2.13 Labs / Ecosystem Packages

| # | Feature | Package | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 166 | Context protocol | @lit/context | ❌ | ✅ expected: Elixir context → @lit/context | ❓ | |
| 167 | createContext | createContext<T>(key) | ❌ | ✅ expected | ❓ | |
| 168 | @provide decorator | @provide({context}) | ❌ | ✅ expected | ❓ | |
| 169 | @consume decorator | @consume({context, subscribe}) | ❌ | ✅ expected | ❓ | |
| 170 | ContextProvider controller | new ContextProvider(...) | ❌ | ❌ expected: controller API | ❓ | |
| 171 | ContextConsumer controller | new ContextConsumer(...) | ❌ | ❌ expected | ❓ | |
| 172 | ContextRoot | new ContextRoot() | ❌ | ❓ | ❓ | |
| 173 | Task | @lit/task | ❌ | 🟡 expected: Elixir async → Task | ❓ | |
| 174 | Task class | new Task(host, opts) | ❌ | 🔌 via behaviors.add escape hatch | ❓ | Task is controller-based; reachable through behaviors.add |
| 175 | Auto-run vs manual | autoRun option | ❌ | ❓ | ❓ | |
| 176 | Task abort signal | {signal} | ❌ | ❓ | ❓ | |
| 177 | Task chaining | output → args | ❌ | ❓ | ❓ | |
| 178 | Signals | @lit-labs/signals | ❌ | ❌ expected: incompatible with compiled output | ❓ | Tier 1: Signals are a state management alternative; Tier 1 uses Lit's built-in reactivity. |
| 179 | signal() | signal(val) / get/set | ❌ | ❌ | ❓ | |
| 180 | computed() | computed(() => expr) | ❌ | ❌ | ❓ | |
| 181 | SignalWatcher mixin | SignalWatcher(LitElement) | ❌ | ❌ (not compatible with compiled class) | ❓ | |
| 182 | watch() directive | watch(signal) | ❌ | ❌ | ❓ | |
| 183 | Signals html tag | html from @lit-labs/signals | ❌ | ❌ | ❓ | |
| 184 | signal-utils | SignalArray, @signal | ❌ | ❌ | ❓ | |
| 185 | React wrapper | @lit/react createComponent | 🔌 Available for hand-written elements | ✅ expected: auto-generate createComponent | 🔌 Wrapper can be wrapped for React | |
| 186 | useController() hook | @lit/react/use-controller.js | ❌ | ❌ | ❓ | |
| 187 | Localization | @lit/localize | ❌ | ✅ expected: Elixir gettext → @lit/localize | ❓ | |
| 188 | Virtualizer | @lit-labs/virtualizer | ❌ | 🔌 Usable with compiled Lit elements | ❓ | |
| 189 | Motion | @lit-labs/motion | ❌ | 🔌 Usable with compiled Lit elements | ❓ | |
| 190 | Router | @lit-labs/router | ❌ | 🔌 Usable with compiled Lit elements | ❓ | |
| 191 | Observers | @lit-labs/observers | ❌ | 🔌 Usable with compiled Lit elements (controller-based, so limited) | ❓ | |
| 192 | Scoped registry mixin | @lit-labs/scoped-registry-mixin | ❌ | ✅ expected | ❓ | |
| 193 | Wrapper generators | @lit-labs/gen-wrapper-* | ❌ | ✅ expected: generate from CEM | 🔌 Generate from wrapper CEM | |
| 194 | Custom Elements Manifest | @custom-elements-manifest/analyzer | 🔌 Analyze hand-written elements | ✅ expected: auto-generate CEM from Elixir definitions | 🔌 Analyze wrapper classes | |

### 2.14 Tooling and DX

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 195 | Experimental decorators | @property() + tsconfig | 🔌 Hand-written | 🔌 Compiled output uses standard Lit decorators | 🔌 Wrapper uses decorators | |
| 196 | Standard TC39 decorators | @property() accessor | ❌ | 🟡 expected: output can use either decorator mode | 🔌 Wrapper can use either | |
| 197 | No-decorator API | static properties | ❌ | 🟡 expected: output can use static properties | 🔌 Wrapper can use static properties | |
| 198 | TypeScript types | Type declarations | 🔌 Lit types | ✅ expected: generate .d.ts from Elixir typespecs | 🔌 Lit types + wrapper types | |
| 199 | HTMLElementTagNameMap | declare global { ... } | 🔌 Hand-written | ✅ expected: auto-generated | 🔌 Wrapper auto-generates | |
| 200 | Dev-mode warnings | Automatic in dev build | 🔌 Lit dev build | 🔌 Lit dev build for compiled output | 🔌 Lit dev build for wrapper | |
| 201 | Warning suppression | LitElement.disableWarning(...) | ❌ | 🔌 Available | 🔌 Available | |
| 202 | lit-analyzer / lit-plugin | VS Code extension | 🔌 Works with .js output | 🔌 Works with compiled .js output | 🔌 Works with wrapper .js | |
| 203 | eslint-plugin-lit | ESLint plugin | 🔌 In JS toolchain | 🔌 In JS toolchain | 🔌 In JS toolchain | |
| 204 | Polyfills | @webcomponents/webcomponentsjs | 🔌 Available | 🔌 Available | 🔌 Available | |
| 205 | Browser support | ES2021 browsers | 🔌 Standard | 🔌 Standard | 🔌 Standard | |

### 2.15 Packaging and Distribution

| # | Feature | Lit API | tessera today (Phase 1) | Tier 1 (Elixir-to-Lit) | Tier 2 (Hologram runtime) | Notes |
|---|---------|---------|------------------------|----------------------|--------------------------|-------|
| 206 | ESM only | "type": "module" | 🔌 Standard | 🔌 Compiled output is ESM | 🔌 Wrapper is ESM | |
| 207 | Do not bundle rule | peerDependencies on lit | 🔌 Manual | ✅ expected: auto-config peer deps | 🔌 Wrapper respects this | |
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
| 217 | Browser-based testing | Web Test Runner | 🔌 Test Lit elements in browser | 🔌 Test compiled Lit elements in browser | ❓ | Tier 2: Hologram tests need Hologram's own test infrastructure |
| 218 | @open-wc/testing | fixture, html, expect | 🔌 Standard Lit testing | 🔌 Standard Lit testing for compiled output | ❓ | |
| 219 | fixture() | await fixture<MyEl>(html`...`) | 🔌 Standard | 🔌 Standard for compiled output | ❓ | |
| 220 | updateComplete in tests | await el.updateComplete | 🔌 Standard | 🔌 Standard | ❓ | |
| 221 | Shadow DOM queries | el.shadowRoot!.querySelector(...) | 🔌 Standard | 🔌 Standard | ❓ | |
| 222 | Semantic DOM snapshots | expect(el).shadowDom.to.equalSnapshot() | 🔌 Available | 🔌 Available | ❓ | |
| 223 | Accessibility assertions | expect(el).to.be.accessible() | 🔌 Available | 🔌 Available | ❓ | |
| 224 | WebdriverIO alternative | @wdio/globals | 🔌 Available | 🔌 Available | ❓ | |
| 225 | Vitest browser mode | vitest browser config | 🔌 Available | 🔌 Available | ❓ | |
| 226 | requestAnimationFrame pattern | await rAF() after change | 🔌 Standard | 🔌 Standard | ❓ | |
| 227 | Web Test Runner config | web-test-runner.config.mjs | 🔌 Standard | 🔌 Standard | ❓ | |

---

## 3. Gap Summary

### 3.1 P0 Features Missing Per Tier

#### Tier 1 (Elixir-to-Lit) — P0 coverage summary:

Tier 1 generates fully functional Lit elements with zero hand-written JS. All P0 template/directive/property features are confirmed (spike notes, components built and tested). Imperative DOM features (ref, @query, controllers, ElementInternals, mixins) are reachable through two escape hatches:

1. **`behaviors.add(tag, fn)`** — runs on `connectedCallback` with full element access, returns cleanup on disconnect. Covers: ref, @query, @queryAll, @queryAssignedElements/Nodes, ElementInternals, ReactiveController patterns, custom/async directives.
2. **Subclassing** — the generated element is a `TesseraElement(LitElement, contract)` subclass; consumer JS can apply mixins or add controllers through standard Lit class extension.

**Tier 1 P0 gap: 0 features strictly missing.** All are reachable — some through the DSL, some through the JS escape hatches. The DSL subset intentionally keeps the generated surface lean; anything outside it uses `behaviors.add`.

#### Tier 2 (Hologram Runtime Element) — ❓ on P0 features:

| Feature | Status | Notes |
|---------|--------|-------|
| render (Lit's html``) (#9) | 🟡 expected | Hologram uses its own template system, not Lit's html`` |
| shadow DOM queries (#102-106) | ❓ | Unknown if Hologram bridge provides equivalent |
| SSR/Declarative Shadow DOM (#154-157) | ❓ | Hologram server-renders HTML and runs compiled-to-JS in the browser; the open questions are whether Hologram's server renderer can emit a component inside Declarative Shadow DOM, and how client-side hydration would attach the Hologram runtime to the element afterwards. Pending the Tier 2 spike.
| @lit/context (#166-169) | ❓ | Unknown if Hologram can participate in Context protocol |
| Testing (#217-221) | ❓ | Hologram tests need Hologram infrastructure, not @open-wc/testing |

**Tier 2 P0 gap: dominated by ❓.** The Tier 2 spike (`spike/hologram-runtime-element`) has not been started — the branch exists but carries zero unique commits and no notes file. No features are confirmed or ruled out. The architectural questions are: whether Hologram's server renderer can emit inside Declarative Shadow DOM; how hydration would attach the Hologram runtime to a server-rendered element; and whether the Lit wrapper can adequately proxy Hologram's own template system for Lit-native directives and style encapsulation.

### 3.2 Fundamentally Hard Features

#### For Tier 1 (Elixir-to-Lit):

All P0 features are reachable — either through the compiled DSL or through the two JS escape hatches (`behaviors.add` for imperative DOM and `TesseraElement` subclassing for mixins/controllers). The DSL subset is deliberately lean and will remain so. Features outside the subset are not "missing" — they are intentionally deferred to the JS escape hatch:

1. **Imperative DOM (ref, @query, ElementInternals)** — not compilable from the Elixir expression subset; use `behaviors.add` on connect.
2. **ReactiveController API** — not expressible in the action DSL; use `behaviors.add` or subclass the generated element with a controller.
3. **Mixins** — JS class factory pattern; use `TesseraElement` subclassing in hand-written JS.
4. **Custom directives / async directives** — imperative Directive API; use `behaviors.add`.

#### For Tier 2 (Hologram Runtime Element):

1. **SSR** — Hologram server-renders HTML and runs its compiled-to-JS runtime in the browser. The open questions for Tier 2 are whether Hologram's server renderer can emit a component inside a Declarative Shadow DOM `<template shadowrootmode>` wrapper, and how client-side hydration would attach the Hologram runtime to the pre-rendered element. Pending the Tier 2 spike.

2. **Per-instance styles (styleMap, classMap)** — Hologram manages its own rendering inside the wrapper. Dynamic styles computed in Hologram need to be communicated through the bridge to the Lit wrapper's styleMap/classMap — adds latency and complexity.

3. **Lit's html`` template system** — Tier 2 uses Hologram's own template rendering. The Lit wrapper's `render()` is a thin delegate. This means Lit directives (when, choose, map, repeat, etc.) are NOT available inside Hologram-rendered content — Hologram must provide its own equivalents.

4. **updateComplete / reactive update cycle** — Lit's update batching is at the wrapper level. Hologram's update cycle is independent. Synchronizing the two (so `await this.updateComplete` works as expected) requires bridge work.

5. **Testing** — Lit component tests use `@open-wc/testing` with `fixture()`, `el.updateComplete`, and shadow DOM queries. Tier 2 components are Hologram inside a Lit wrapper; testing the Hologram content requires Hologram's own test infrastructure, not Lit's.

### 3.3 Suggested Parity Roadmap

**Phase 1 — Complete the Phase 1 bridge (now):**
- Port the remaining P0 features from hand-written Lit into the Elixir contract layer (reflect, converter, hasChanged, event options)
- Document which features are "🔌 via JS escape hatch" and commit to keeping the hatch open

**Phase 2 — Land the Tier 1 spike (confirmed GO):**
- The spike (`spike/elixir-to-lit`) has proven: full LitElement codegen from Elixir state/template/action DSL; 0 hand-written JS; ESM/UMD/shared-runtime packaging; Hologram/plain-HTML/React host proofs
- PR sequence: (1) element DSL core (Expr/Template/LitCodegen), (2) packaging under `mix tessera.build`, (3) demo + e2e, (4) docs update to CONTRACT.md + EXTENDING.md
- Document `behaviors.add` as the official escape hatch for imperative DOM, controllers, and custom directives
- Add the `state`-keys-snake_case convention to CONTRACT.md

**Phase 3 — Tier 2 spike:**
- Spike the Hologram-runtime-in-a-custom-element approach
- Investigate Declarative Shadow DOM emission from Hologram's server renderer
- Define how the Lit wrapper proxies Hologram template events and state changes
- Determine whether Hologram can hydrate into a server-rendered Declarative Shadow DOM element

**Phase 4 — Gap acceptance:**
- Explicitly document which Lit features each tier will NOT support
- For each gap, provide the recommended alternative or escape hatch
- Publish the conformance suite

---

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

---

*End of parity matrix. 227 features inventoried across 16 areas. Matrix covers Phase 1 (tessera today), Tier 1 (spike/elixir-to-lit), and Tier 2 (spike/hologram-runtime-element). Cells marked ❓ are pending spike note availability.*