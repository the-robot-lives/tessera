# Extending Tessera on the JS side

Three ways to change what a contract-driven element does, without touching the
package or regenerating contracts. Read `docs/CONTRACT.md` first — the tag
naming and `data-tsr-on` grammar are load-bearing here.

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
document. `defineOnce` keeps the FIRST registration and warns at most once per
tag that a later copy was skipped. To own the tag you must evaluate before the
package's element module does — import your subclass module first, or
re-register via `defineOnce` from an earlier-bundled entry. If you cannot
control load order, use behaviors (§1) or the element swap (§3) instead.

## 3. Swapping the element via `use ..., element:`

The Elixir side lets a host application replace the JS module that gets
`js_import`'d for a component:

```elixir
use PersonaKit.PersonaCard,
  element: MyAppWeb.MyCardJS
```

`MyAppWeb.MyCardJS` must export the same surface as the package element
module (`register/0`-style no-arg function returning the ctor, per
`CONTRACT.md` §5). This is the escape hatch when the tag must be YOUR class
from the start — the adapter never imports the package's element for that
component, so there is no race with `defineOnce`.

Combine with the same contract module (`contract.generated.mjs`) so attrs,
props and `data-tsr-on` keep matching the Elixir spec.

## Quick reference

| Need | Use |
|---|---|
| Attach DOM behavior/listeners to a shipped element | `behaviors.add` |
| Override the template or lifecycle | subclass + `defineOnce` before the package loads |
| Replace the element per host app, controlled from Elixir | `use ..., element:` |
| React to contract events from outside the element | plain `addEventListener` — events are composed and bubble (§1 of the contract) |
| Send component data to a backend | `BusClient` seam (`@noizu/tessera-core/bus`); without a transport every call resolves `{ok: false, reason: "no-transport"}` |
