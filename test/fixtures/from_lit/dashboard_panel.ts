import { LitElement, html } from "lit";
import { customElement, property, state } from "lit/decorators.js";
import { repeat } from "lit/directives/repeat.js";

/**
 * TESSER-019 source fixture: a small real Lit element converted with
 * `mix tessera.from_lit`. The emitted spec is hand-ported into the element
 * DSL (workflow step 3, docs/notes/from-lit.md) as
 * test/support/conformance/conf_from_lit.ex, generated into
 * js/test/fixtures/conformance/ via generate_fixtures.exs, and rendered
 * LIVE by js/test/from_lit_render.test.mjs.
 */
@customElement("dashboard-panel")
export class DashboardPanel extends LitElement {
  @property({ type: String }) panelTitle = "Overview";

  @property({ type: Boolean, reflect: true }) open = true;

  @property({ type: Array })
  rows: Array<Record<string, string>> = [
    { id: "r1", label: "Inbox" },
    { id: "r2", label: "Sent" },
    { id: "r3", label: "Drafts" },
  ];

  @state() tickCount = 0;

  render() {
    return html`
      <section class="panel">
        <h3>${this.panelTitle}</h3>
        <p class="mode">${this.open ? "open" : "closed"}</p>
        <ul>
          ${repeat(
            this.rows,
            (row) => row.id,
            (row) => html`<li data-id=${row.id}>${row.label}</li>`
          )}
        </ul>
        <button type="button" @click=${this.tick}>tick</button>
        <span class="ticks">${this.tickCount}</span>
      </section>
    `;
  }

  private tick() {
    this.tickCount += 1;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    "dashboard-panel": DashboardPanel;
  }
}
