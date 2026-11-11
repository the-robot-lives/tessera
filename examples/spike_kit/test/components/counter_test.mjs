// <spike-counter> generated-element tests (SpikeKit.Counter): reactive state
// from the DSL, translated actions driving re-render, composed count-change
// event with camelCase detail keys.
import { expect, aTimeout } from "@open-wc/testing";
import { register } from "../../lib/spike_kit/spike-counter.element.generated.mjs";

describe("<spike-counter>", () => {
  before(() => {
    register();
  });

  function make(attrs = {}) {
    const el = document.createElement("spike-counter");
    for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, value);
    document.body.appendChild(el);
    return el;
  }

  function countText(el) {
    return el.shadowRoot.querySelector("[data-cy=spike-counter-count]").textContent.trim();
  }

  it("defines the custom element", () => {
    const ctor = register();
    expect(customElements.get("spike-counter")).to.equal(ctor);
  });

  it("renders the declared default state (count 0)", async () => {
    const el = make();
    await aTimeout(0);
    expect(countText(el)).to.equal("0");
    expect(el.count).to.equal(0);
    el.remove();
  });

  it("coerces attrs to typed properties (label, step)", async () => {
    const el = make({ label: "Hits", step: "5" });
    await aTimeout(0);
    expect(el.label).to.equal("Hits");
    expect(el.step).to.equal(5);
    expect(el.shadowRoot.querySelector(".label").textContent).to.equal("Hits");
    el.remove();
  });

  it("increment action updates reactive state and re-renders", async () => {
    const el = make();
    await aTimeout(0);
    el.shadowRoot.querySelector("[data-cy=spike-counter-inc]").click();
    await aTimeout(0);
    expect(countText(el)).to.equal("1");
    expect(el.count).to.equal(1);
    el.remove();
  });

  it("decrement action respects the step attr", async () => {
    const el = make({ step: "3" });
    await aTimeout(0);
    el.shadowRoot.querySelector("[data-cy=spike-counter-dec]").click();
    await aTimeout(0);
    expect(countText(el)).to.equal("-3");
    el.remove();
  });

  it("emits composed count-change with camelCase detail", async () => {
    const el = make();
    await aTimeout(0);

    const received = [];
    const listener = (event) => received.push(event);
    document.addEventListener("count-change", listener);
    try {
      el.shadowRoot.querySelector("[data-cy=spike-counter-inc]").click();
      await aTimeout(0);
    } finally {
      document.removeEventListener("count-change", listener);
    }

    expect(received).to.have.lengthOf(1);
    expect(received[0].detail).to.eql({ count: 1, delta: 1 });
    expect(received[0].composed).to.equal(true);
    el.remove();
  });
});
