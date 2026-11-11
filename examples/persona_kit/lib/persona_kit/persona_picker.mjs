// persona-picker — tessera example web component (PersonaKit.PersonaPicker).
//
// Composes <persona-card> children INSIDE its own shadow DOM and RE-EMITS
// their selection as the picker's own `persona-picked` event, emitted FROM
// THE OUTER ELEMENT — the documented nested-shadow pattern (CONTRACT.md §4,
// EXTENDING.md §4). Hosts bind on_persona_picked only; the child cards'
// persona-select events stay private to the picker.
import { LitElement, html, css } from "lit";
import { defineOnce, TesseraElement, emit } from "@noizu/tessera-core";
import contract from "./persona_picker.contract.generated.mjs";

class PersonaPicker extends TesseraElement(LitElement, contract) {
  static styles = css`
    :host {
      display: block;
      border: 1px dashed #94a3b8;
      border-radius: 12px;
      padding: 12px;
      margin: 8px 0;
      font-family: system-ui, sans-serif;
      background: #f8fafc;
    }
    h3 {
      margin: 0 0 8px;
      font-size: 1em;
      color: #334155;
    }
    .cards {
      display: flex;
      flex-wrap: wrap;
      gap: 4px;
    }
    .picked {
      margin: 8px 0 0;
      font-size: 0.9em;
      color: #475569;
    }
  `;

  // Re-emitted selection, surfaced in the picker's own shadow UI.
  #selected = null;

  #onCardSelect(event) {
    // Keep the child's persona-select private to the picker internals.
    event.stopPropagation();
    const personaId = event.detail?.personaId ?? null;
    this.#selected = personaId;
    this.requestUpdate();
    // RE-EMIT FROM THIS ELEMENT so the bridge resolves THIS host's
    // data-tsr-on binding (the picker is a registered contract element and
    // the direct event target — CONTRACT.md §4 attribution).
    emit(this, "persona-picked", { personaId });
  }

  connectedCallback() {
    super.connectedCallback();
    // Composed child events bubble to this host (same shadow tree).
    this.addEventListener("persona-select", this.#onCardSelect);
  }

  disconnectedCallback() {
    this.removeEventListener("persona-select", this.#onCardSelect);
    super.disconnectedCallback?.();
  }

  render() {
    const personas = Array.isArray(this.personas) ? this.personas : [];

    return html`
      <div data-cy="persona-picker-panel">
        <h3>${this.title}</h3>
        <div class="cards">
          ${personas.map(
            (persona) => html`
              <persona-card
                display-name=${persona.name}
                .tagList=${persona.tags ?? []}
              ></persona-card>
            `,
          )}
        </div>
        <p class="picked" data-cy="persona-picker-selected">picked: ${this.#selected ?? "none"}</p>
        <slot></slot>
      </div>
    `;
  }
}

export function register() {
  return defineOnce("persona-picker", PersonaPicker);
}

// LOAD-BEARING: see persona_card.mjs (CONTRACT.md §3).
register();
