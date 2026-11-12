// Keyed {%for row <- @rows, key: row.id} → Lit `repeat` (lit-parity #63,
// BoE need #2). Fixture: test/support/conformance/conf_repeat.ex.
import { expect } from "@open-wc/testing";
import "./fixtures/conformance/wtr-no-auto-register.mjs";
import { tag, register } from "./fixtures/conformance/tsr-conf-repeat.element.generated.mjs";

register();

describe("keyed for → repeat (Tier 1)", () => {
  afterEach(() => {
    for (const el of document.querySelectorAll(tag)) el.remove();
  });

  it("a reorder MOVES the keyed nodes instead of re-rendering in place", async () => {
    const el = document.createElement(tag);
    document.body.appendChild(el);
    await el.updateComplete;

    const items = () => [...el.shadowRoot.querySelectorAll("li")];
    const before = Object.fromEntries(items().map((li) => [li.dataset.id, li]));
    expect(items().map((li) => li.textContent)).to.deep.equal(["Alpha", "Beta", "Gamma"]);

    await el.dispatchAction("reverse");
    await el.updateComplete;

    const after = items();
    expect(after.map((li) => li.textContent)).to.deep.equal(["Gamma", "Beta", "Alpha"]);
    // identity follows the KEY: the node keyed "a" is the same node, now last
    for (const li of after) expect(li, `node ${li.dataset.id}`).to.equal(before[li.dataset.id]);
  });
});
