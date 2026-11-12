// fixture: one Lit render() exercising every construct the from_lit render()
// conversion supports (TESSER-016). Keep in sync with the conversion table in
// Noizu.Tessera.FromLit.Render's moduledoc.
import { LitElement, html, css, nothing, repeat, guard, live, unsafeHTML, classMap, styleMap, ifDefined } from "lit";
import { customElement, property, state } from "lit/decorators.js";

@customElement("kitchen-sink")
export class KitchenSink extends LitElement {
  @property({ type: String }) title = "Hello";
  @property({ type: Number }) count = 0;
  @property({ type: Array }) items = [];
  @property({ type: Object }) styleObj = {};
  @property({ type: String }) optVal?: string;
  @property() liveVal = 0;
  @property() rawHtml = "";
  @state() open = false;

  render() {
    return html`
      <h1>${this.title}</h1>
      <p class=${classMap({ active: this.open })} style=${styleMap(this.styleObj)}>${this.count + 1}</p>
      ${this.open ? html`<span>open</span>` : html`<span>closed</span>`}
      ${this.count > 0 && html`<b>big</b>`}
      <ul>
        ${this.items.map((item) => html`<li>${item.name}</li>`)}
      </ul>
      ${repeat(this.items, (item) => item.id, (item) => html`<row row-name=${item.name}>row</row>`)}
      <button @click=${this.save}>Save</button>
      <input .value=${this.optVal} ?disabled=${this.open} aria-label="item ${this.title}" />
      <x-live .checked=${live(this.liveVal)}></x-live>
      <x-opt .v=${ifDefined(this.optVal)}></x-opt>
      <x-unsafe .html=${unsafeHTML(this.rawHtml)}></x-unsafe>
      <x-guard .t=${guard(this.items, () => html`<g>guarded</g>`)}></x-guard>
      <x-no>${nothing()}</x-no>
      <span>${this.items.length} items</span>
      <span>${this.title.toUpperCase()}</span>
      ${`tag: ${this.title}`}
    `;
  }

  save() {
    this.dispatchEvent(new CustomEvent("sink-save", { detail: { title: this.title } }));
  }
}
