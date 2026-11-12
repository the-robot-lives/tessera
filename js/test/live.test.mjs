// live(expr) on a property binding (lit-parity #67, BoE need #3).
// Fixture: test/support/conformance/conf_live.ex (.value={live(@draft)}).
import { expect } from "@open-wc/testing";
import "./fixtures/conformance/wtr-no-auto-register.mjs";
import { tag, register } from "./fixtures/conformance/tsr-conf-live.element.generated.mjs";

register();

describe("live() + .prop binding (Tier 1)", () => {
  afterEach(() => {
    for (const el of document.querySelectorAll(tag)) el.remove();
  });

  it("re-render resets a user-edited input even when state did not change", async () => {
    const el = document.createElement(tag);
    document.body.appendChild(el);
    await el.updateComplete;

    const input = el.shadowRoot.querySelector('[data-cy="conf-live-input"]');
    expect(input.value).to.equal("");

    // the user types: the DOM value drifts, state.draft is still ""
    input.value = "typed by user";

    await el.dispatchAction("clear"); // draft "" → "" (same), clears 0 → 1
    await el.updateComplete;

    expect(el.shadowRoot.querySelector('[data-cy="conf-live-clears"]').textContent).to.equal("1");
    expect(input.value, "live() compares against the live DOM value").to.equal("");
  });
});
