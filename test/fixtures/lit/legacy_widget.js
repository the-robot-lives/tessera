import { LitElement, html, css } from "lit";

// Lit 2-style declaration: static properties instead of decorators,
// tag registered via customElements.define at the bottom.
export class LegacyWidget extends LitElement {
  static properties = {
    heading: { type: String, attribute: "heading", reflect: true },
    count: { type: Number },
    payload: { type: Object, attribute: false },
    mode: { state: true },
    shortcut: String,
  };

  static get styles() {
    return [css`:host { color: red; }`, css`.x { margin: 0; }`];
  }

  fire() {
    this.dispatchEvent(new CustomEvent("legacy-fired", { detail: { ok: true }, bubbles: true }));
    this.dispatchEvent(new Event("ping"));
  }

  render() {
    return html`<slot></slot>`;
  }
}

customElements.define("legacy-widget", LegacyWidget);