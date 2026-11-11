// <spike-toggle-chip> generated-element tests (SpikeKit.ToggleChip): props
// in, local state flips with re-render (ternary branch), chip-select event
// with camelCase detail keys crossing the wire.
import { expect, aTimeout } from "@open-wc/testing";
import { register } from "../../lib/spike_kit/spike-toggle-chip.element.generated.mjs";

describe("<spike-toggle-chip>", () => {
  before(() => {
    register();
  });

  function make(attrs = {}) {
    const el = document.createElement("spike-toggle-chip");
    for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, value);
    document.body.appendChild(el);
    return el;
  }

  function dot(el) {
    return el.shadowRoot.querySelector(".dot").textContent.trim();
  }

  it("defines the custom element", () => {
    const ctor = register();
    expect(customElements.get("spike-toggle-chip")).to.equal(ctor);
  });

  it("renders attrs and default state", async () => {
    const el = make({ "chip-id": "persona-1", label: "Ada" });
    await aTimeout(0);
    expect(el.chipId).to.equal("persona-1");
    expect(el.selected).to.equal(false);
    expect(dot(el)).to.not.equal("*");
    expect(el.shadowRoot.querySelector("[data-cy=spike-chip-label]").textContent).to.equal("Ada");
    expect(el.shadowRoot.querySelector("[data-cy=spike-chip-clicks]").textContent).to.equal("0");
    el.remove();
  });

  it("toggle action flips state and switches the template branch", async () => {
    const el = make({ "chip-id": "persona-1", label: "Ada" });
    await aTimeout(0);
    el.shadowRoot.querySelector("[data-cy=spike-chip-root]").click();
    await aTimeout(0);
    expect(el.selected).to.equal(true);
    expect(dot(el)).to.equal("*");
    expect(el.clicks).to.equal(1);

    el.shadowRoot.querySelector("[data-cy=spike-chip-root]").click();
    await aTimeout(0);
    expect(el.selected).to.equal(false);
    expect(dot(el)).to.not.equal("*");
    expect(el.clicks).to.equal(2);
    el.remove();
  });

  it("emits composed chip-select with camelCase detail", async () => {
    const el = make({ "chip-id": "persona-7", label: "Grace" });
    await aTimeout(0);

    const received = [];
    const listener = (event) => received.push(event);
    document.addEventListener("chip-select", listener);
    try {
      el.shadowRoot.querySelector("[data-cy=spike-chip-root]").click();
      await aTimeout(0);
    } finally {
      document.removeEventListener("chip-select", listener);
    }

    expect(received).to.have.lengthOf(1);
    expect(received[0].detail).to.eql({ chipId: "persona-7", selected: true });
    el.remove();
  });
});
