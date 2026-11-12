// TESSER-019: LIVE render test of a component converted by
// `mix tessera.from_lit`. Source fixture: test/fixtures/from_lit/
// dashboard_panel.ts → spec test/support/conformance/conf_from_lit.ex →
// generated element js/test/fixtures/conformance/
// tsr-conf-from-lit-panel.element.generated.mjs. Asserts the DOM matches
// what the original Lit render produces: text, attributes, keyed list
// order, the ternary branch, and click → state change.
import { expect } from "@open-wc/testing";
import "./fixtures/conformance/wtr-no-auto-register.mjs";
import { tag, register } from "./fixtures/conformance/tsr-conf-from-lit-panel.element.generated.mjs";

register();

const rowIds = (el) => [...el.shadowRoot.querySelectorAll("li")].map((li) => li.dataset.id);
const rowLabels = (el) => [...el.shadowRoot.querySelectorAll("li")].map((li) => li.textContent);
const cy = (el, name) => el.shadowRoot.querySelector(`[data-cy="${name}"]`);

describe("from_lit conversion renders live (Tier 1)", () => {
  afterEach(() => {
    for (const el of document.querySelectorAll(tag)) el.remove();
  });

  async function mount() {
    const el = document.createElement(tag);
    document.body.appendChild(el);
    await el.updateComplete;
    return el;
  }

  it("renders the converter's defaults: text + ternary branch", async () => {
    const el = await mount();
    expect(cy(el, "from-lit-title").textContent).to.equal("Overview");
    // original Lit: this.open ? "open" : "closed" — open defaults true
    expect(cy(el, "from-lit-mode").textContent).to.equal("open");
    expect(cy(el, "from-lit-ticks").textContent).to.equal("0");
  });

  it("flips the ternary branch when the attr changes", async () => {
    const el = await mount();
    el.open = false;
    await el.updateComplete;
    expect(cy(el, "from-lit-mode").textContent).to.equal("closed");
    el.open = true;
    await el.updateComplete;
    expect(cy(el, "from-lit-mode").textContent).to.equal("open");
  });

  it("keeps the attribute/prop surface: kebab attr drives the title", async () => {
    const el = await mount();
    el.setAttribute("panel-title", "Ops Board");
    await el.updateComplete;
    expect(cy(el, "from-lit-title").textContent).to.equal("Ops Board");
  });

  it("renders the keyed list in order with data-id attributes", async () => {
    const el = await mount();
    expect(rowIds(el)).to.deep.equal(["r1", "r2", "r3"]);
    expect(rowLabels(el)).to.deep.equal(["Inbox", "Sent", "Drafts"]);
    // original Lit used lit/repeat keyed by row.id — reorder MOVES nodes.
    const before = [...el.shadowRoot.querySelectorAll("li")];
    el.rows = [
      { id: "r3", label: "Drafts" },
      { id: "r1", label: "Inbox" },
      { id: "r2", label: "Sent" },
    ];
    await el.updateComplete;
    expect(rowIds(el)).to.deep.equal(["r3", "r1", "r2"]);
    const after = [...el.shadowRoot.querySelectorAll("li")];
    for (const li of after) {
      expect(li, `node ${li.dataset.id}`).to.equal(
        before.find((n) => n.dataset.id === li.dataset.id)
      );
    }
  });

  it("click → action → state change re-renders the tick count", async () => {
    const el = await mount();
    const button = cy(el, "from-lit-tick");
    button.click();
    await el.updateComplete;
    expect(cy(el, "from-lit-ticks").textContent).to.equal("1");
    button.click();
    await el.updateComplete;
    expect(cy(el, "from-lit-ticks").textContent).to.equal("2");
    // the state is visible through the public statics too
    expect(el.tick_count).to.equal(2);
  });
});
