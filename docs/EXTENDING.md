# Extending Tessera on the JS side

Three ways to change what a contract-driven element does, without touching the
package or regenerating contracts. Read `docs/CONTRACT.md` first — the tag
naming and `data-tsr-on` grammar are load-bearing here. The normative
extension contract (Elixir inheritance + this JS surface) is
`docs/EXTENSION-CONTRACT.md`.

## 1. Behaviors (preferred)

A behavior is a function that runs on **every** `connectedCallback` of the
element registered for a tag. It may return a cleanup, which runs on the
matching `disconnectedCallback`. Behaviors attach to elements you do not own
and need no subclassing or re-registration:

```js
import { behaviors } from "@noizu/tessera-core/behaviors";

behaviors.add("persona-card", (el) => {
  const onClick = () => el.classList.add("is-selected");
  el.addEventListener("click", onClick);
  el.dataset.enriched = "true";

  return () => {
    // runs on disconnect (Hologram re-renders may mount/unmount the host)
    el.removeEventListener("click", onClick);
  };
});
```

Rules:

- The registry lives on the bridge singleton
  (`globalThis[Symbol.for("tessera.bridge")]`), so a behavior registered from
  any module copy — any page bundle — is seen by elements loaded from another.
- Add the same tag+fn twice and it stores once (`Set` semantics).
- `behaviors.remove(tag, fn)` removes one; a throwing behavior is caught and
  warned, it never breaks the element's connection.
- Keep behaviors idempotent per connect: they run again after every
  disconnect/connect cycle.

Use behaviors for DOM enrichment, extra listeners, integrations with other
widgets — anything that does not change the element's class identity.

## 2. Subclass + `defineOnce` (order matters)

For changes that need the class itself (override lifecycle, change the
template), subclass the mixed class and register it yourself:

```js
import { LitElement, html } from "lit";
import { TesseraElement } from "@noizu/tessera-core/element";
import { defineOnce } from "@noizu/tessera-core/define";
import contract from "./persona-card.contract.generated.mjs";

class MyPersonaCard extends TesseraElement(LitElement, contract) {
  render() { /* your template */ }
}

// FIRST definition of the tag wins — register before the library's own
// module evaluates, or your class will be skipped (with one console.warn).
defineOnce("persona-card", MyPersonaCard);
```

**Ordering rule:** custom elements allow exactly one definition per tag per
document. `defineOnce` keeps the FIRST registration and warns at most once
per tag **per document** that a later copy was skipped — the warned set lives
on the shared `globalThis` singleton, so duplicate module copies (Hologram
bundles every `js_import` into each page bundle) don't double-warn. To own the
tag you must evaluate before the package's element module does — import your
subclass module first, or re-register via `defineOnce` from an
earlier-bundled entry. If you cannot control load order, use behaviors (§1)
or derivation / `extendElement` (§3) instead.

## 3. Swapping the element via `use ..., element:` — NOT IMPLEMENTED (as of 0.2.0)

**This option does not exist.** `use Noizu.Tessera.Component` does not read an
`element:` option; it is silently ignored (tracked as F-04). Do not write code
against the sample below. To customize or replace a vendor element, use one of
the shipped mechanisms instead:

- §1 behaviors (`behaviors.add`, now with an API pin) or §2 subclass + `defineOnce`;
- **derivation** — `use Vendor.Element, tag: "my-el"` (a new tag) or
  `use Vendor.Element, tag: :inherit, priority: n` (same-tag takeover as a
  layered extension), with `base_action/3` down-calls;
- **`extendElement(tag, mixin)`** before the tag's first definition.

All three are specified in `docs/EXTENSION-CONTRACT.md` (§5 derivation, §5.9
takeover, §6 runtime API) and covered by the conformance suite.

The planned shape, for reference:

```elixir
use PersonaKit.PersonaCard,
  element: MyAppWeb.MyCardJS
```

`MyAppWeb.MyCardJS` must export the same surface as the package element
module (`register/0`-style no-arg function returning the ctor, per
`CONTRACT.md` §5). It is the escape hatch when the tag must be YOUR class
from the start — the adapter never imports the package's element for that
component, so there is no race with `defineOnce`.

Combine with the same contract module (`contract.generated.mjs`) so attrs,
props and `data-tsr-on` keep matching the Elixir spec.

## 4. Composing tessera components inside your shadow DOM (re-emit)

Bindings resolve from the document level
(`CONTRACT.md` §4). When element B sits inside element A's shadow root, the
retargeted shadow host A is the first candidate for B's composed events: if A
binds the same event name, A's action fires and B's never does. If A carries
no entry, the bridge falls back to scanning the composed path — open-shadow
internals are visible on it — so B's own mapping still fires when B's tag is
registered; the event is dropped only when no registered element on the path
maps it.

Rely on that fallback and you couple yourself to the child's tag being
registered and to your host staying unmapped. The deliberate pattern is to
re-emit the child events you want to expose, from yourself:

```js
import { emit } from "@noizu/tessera-core/events";
import { behaviors } from "@noizu/tessera-core/behaviors";

// persona-composer wraps <persona-card> in its own shadow root.
behaviors.add("persona-composer", (el) => {
  const card = el.shadowRoot?.querySelector("persona-card");
  if (!card) return;
  const onPick = (e) => {
    // Re-emit FROM THE OUTER ELEMENT so the bridge sees the composer as the
    // host and the composer's own data-tsr-on binding fires. Map the detail
    // to whatever your contract's event declares.
    emit(el, "persona-select", { personaId: e.detail?.personaId ?? null });
  };
  card.addEventListener("persona-select", onPick);
  return () => card.removeEventListener("persona-select", onPick);
});
```

The composer then declares `event "persona-select"` in its Elixir spec and
binds it normally (`on_persona_select=...`) — the child card's binding, if
any, stays private to the composer's internals.

## Quick reference

| Need | Use |
|---|---|
| Attach DOM behavior/listeners to a shipped element | `behaviors.add` |
| Override the template or lifecycle | subclass + `defineOnce` before the package loads |
| Replace the element per host app, controlled from Elixir | `use ..., element:` is NOT implemented — use derivation (`use Vendor.Element, tag: :inherit`) or `extendElement` (§3) |
| Expose events from a tessera child nested in your shadow DOM | re-emit with `emit()` from the outer element (§4) |
| React to contract events from outside the element | plain `addEventListener` — events are composed and bubble (§1 of the contract) |
| Send component data to a backend | `BusClient` seam (`@noizu/tessera-core/bus`); without a transport every call resolves `{ok: false, reason: "no-transport"}` |
