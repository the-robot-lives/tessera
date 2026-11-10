// persona_card.mjs — stub colocated with the test fixture spec module. The
// adapter binds it as an @external_resource and imports it by absolute path;
// only its existence matters to the Elixir tests. The real element lives in
// priv/js (@noizu/tessera-core).
import { defineOnce, TesseraElement } from "@noizu/tessera-core";
import contract from "./persona_card.contract.generated.mjs";

class PersonaCard extends TesseraElement(HTMLElement, contract) {}

export function register() {
  return defineOnce("persona-card", PersonaCard);
}

// LOAD-BEARING: stateless SSR never calls init/3 — the element gets defined
// only when the page bundle evaluates this statement (CONTRACT.md §3).
register();
