// <spike-props> conformance suite (SpikeKit.PropsPanel) — lit-parity brief 1c.
// Pins C-01…C-15 (component model / reactive properties), T-03 (?attr boolean
// binding) and the LC family (lifecycle hooks) against the GENERATED element.
// `changed` in willUpdate is a plain-object snapshot of Lit's changedProperties
// Map — keys are property names, values are the OLD values.
import { expect, aTimeout } from "@open-wc/testing";
import { behaviors } from "@noizu/tessera-core";
import { register } from "../../lib/spike_kit/spike-props.element.generated.mjs";

describe("<spike-props> (C/T/LC conformance)", () => {
  before(() => {
    register();
  });

  function make(attrs = {}) {
    const el = document.createElement("spike-props");
    for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, value);
    document.body.appendChild(el);
    return el;
  }

  // Null-safe: willUpdate fires before the first render, when the shadow
  // tree does not exist yet (domTicks snapshots "" at that point).
  const text = (el, cy) => {
    const node = el.shadowRoot && el.shadowRoot.querySelector(`[data-cy=${cy}]`);
    return node ? node.textContent.trim() : "";
  };

  // Document-level lifecycle event log. `domTicks` snapshots the rendered
  // ticks value AT EVENT TIME — willUpdate fires before render (old DOM),
  // updated fires after (new DOM).
  function lifecycleLog(el) {
    const log = [];
    const types = ["props-will", "props-first", "props-updated"];
    const listeners = types.map((type) => {
      const fn = (event) =>
        log.push({
          type,
          detail: event.detail,
          domTicks: text(el, "spike-props-ticks"),
        });
      document.addEventListener(type, fn);
      return [type, fn];
    });
    return {
      log,
      stop: () => listeners.forEach(([type, fn]) => document.removeEventListener(type, fn)),
    };
  }

  it("C-01: defines the custom element", () => {
    const ctor = register();
    expect(customElements.get("spike-props")).to.equal(ctor);
  });

  it("C-02/C-09: string property writes reflect to the attribute (reflect: true)", async () => {
    const el = make();
    await el.updateComplete;
    el.label = "Reflected";
    await el.updateComplete;
    expect(el.getAttribute("data-label")).to.equal("Reflected");
    el.remove();
  });

  it("C-03: attribute → property (default kebab mapping)", async () => {
    const el = make({ tone: "warm" });
    await el.updateComplete;
    expect(el.tone).to.equal("warm");
    el.remove();
  });

  it("C-04: Boolean attribute presence toggles the property", async () => {
    const el = make({ active: "" });
    await el.updateComplete;
    expect(el.active).to.equal(true);
    el.removeAttribute("active");
    await el.updateComplete;
    expect(el.active).to.equal(false);
    el.remove();
  });

  it("C-05: Number attribute coerces to a number", async () => {
    const el = make({ count: "7" });
    await el.updateComplete;
    expect(el.count).to.equal(7);
    el.remove();
  });

  it("C-06: Object attribute parses JSON", async () => {
    const el = make({ payload: '{"a":1}' });
    await el.updateComplete;
    expect(el.payload).to.eql({ a: 1 });
    el.remove();
  });

  it("C-07: internal state change re-renders", async () => {
    const el = make();
    await el.updateComplete;
    expect(text(el, "spike-props-ticks")).to.equal("0");
    el.shadowRoot.querySelector("[data-cy=spike-props-tick]").click();
    await el.updateComplete;
    expect(text(el, "spike-props-ticks")).to.equal("1");
    expect(el.ticks).to.equal(1);
    el.remove();
  });

  it("C-08: setting the same value does not re-render (default hasChanged)", async () => {
    const el = make();
    await el.updateComplete;
    const { log, stop } = lifecycleLog(el);
    try {
      el.tone = "calm"; // the default — no change
      await aTimeout(0);
      await el.updateComplete;
      expect(log.filter((e) => e.type === "props-updated")).to.have.lengthOf(0);
    } finally {
      stop();
      el.remove();
    }
  });

  it("C-10: custom attribute name maps both directions; default name unused", async () => {
    const el = make({ "data-label": "FromAttr" });
    await el.updateComplete;
    expect(el.label).to.equal("FromAttr");
    expect(el.getAttribute("label")).to.equal(null);

    el.label = "FromProp";
    await el.updateComplete;
    expect(el.getAttribute("data-label")).to.equal("FromProp");
    expect(el.getAttribute("label")).to.equal(null);
    expect(text(el, "spike-props-label")).to.equal("FromProp");
    el.remove();
  });

  it("C-11: connectedCallback fires on insert (behavior runs on connect)", async () => {
    const connected = [];
    const fn = (el) => {
      connected.push(el);
    };
    behaviors.add("spike-props", fn);
    try {
      const el = make();
      await el.updateComplete;
      expect(connected).to.include(el);
      // the generated connectedCallback ran its body (theming root part)
      expect(el.getAttribute("part")).to.equal("root");
      el.remove();
    } finally {
      behaviors.remove("spike-props", fn);
    }
  });

  it("C-12: disconnectedCallback fires on remove (behavior cleanup runs)", async () => {
    const disconnected = [];
    const fn = () => () => {
      disconnected.push(true);
    };
    behaviors.add("spike-props", fn);
    try {
      const el = make();
      await el.updateComplete;
      el.remove();
      expect(disconnected).to.have.lengthOf(1);
    } finally {
      behaviors.remove("spike-props", fn);
    }
  });

  it("C-13/LC-03: firstUpdated fires exactly once across many updates", async () => {
    const el = make();
    await el.updateComplete;
    const { log, stop } = lifecycleLog(el);
    try {
      // first update already happened before the log attached — drive three
      // more updates and assert none of them re-fires props-first.
      for (let i = 0; i < 3; i++) {
        el.shadowRoot.querySelector("[data-cy=spike-props-tick]").click();
        await el.updateComplete;
      }
      expect(log.filter((e) => e.type === "props-first")).to.have.lengthOf(0);
    } finally {
      stop();
      el.remove();
    }
  });

  it("C-13/LC-03: firstUpdated fires once on the FIRST update (fresh element)", async () => {
    const el = document.createElement("spike-props");
    const { log, stop } = lifecycleLog(el);
    try {
      document.body.appendChild(el);
      await el.updateComplete;
      el.shadowRoot.querySelector("[data-cy=spike-props-tick]").click();
      await el.updateComplete;
      const firsts = log.filter((e) => e.type === "props-first");
      expect(firsts).to.have.lengthOf(1);
      expect(firsts[0].detail).to.eql({ ticks: 0 });
    } finally {
      stop();
      el.remove();
    }
  });

  it("C-14: updateComplete resolves after the DOM reflects the change", async () => {
    const el = make();
    await el.updateComplete;
    el.label = "Awaited";
    await el.updateComplete;
    expect(text(el, "spike-props-label")).to.equal("Awaited");
    el.remove();
  });

  it("C-15: shouldUpdate returning false freezes the render (property still changes)", async () => {
    const el = make();
    await el.updateComplete;
    el.shadowRoot.querySelector("[data-cy=spike-props-freeze]").click();
    await el.updateComplete;

    const { log, stop } = lifecycleLog(el);
    try {
      el.shadowRoot.querySelector("[data-cy=spike-props-tick]").click();
      await aTimeout(0);
      await el.updateComplete;
      expect(el.ticks).to.equal(1); // property changed
      expect(text(el, "spike-props-ticks")).to.equal("0"); // render frozen
      expect(log).to.have.lengthOf(0); // no will/first/updated on a vetoed update
    } finally {
      stop();
      el.remove();
    }
  });

  it("T-03: ?hidden binding adds/removes the attribute with the boolean value", async () => {
    const el = make();
    await el.updateComplete;
    const secret = el.shadowRoot.querySelector("[data-cy=spike-props-secret]");
    expect(secret.hasAttribute("hidden")).to.equal(false);

    el.shadowRoot.querySelector("[data-cy=spike-props-hide]").click();
    await el.updateComplete;
    expect(secret.hasAttribute("hidden")).to.equal(true);

    el.shadowRoot.querySelector("[data-cy=spike-props-hide]").click();
    await el.updateComplete;
    expect(secret.hasAttribute("hidden")).to.equal(false);
    el.remove();
  });

  it("#21 Array: list prop renders via length; list attr parses JSON arrays", async () => {
    const el = make({ "data-tags": '["a","b"]' });
    await el.updateComplete;
    expect(el.tags).to.eql(["a", "b"]);

    el.items = [1, 2, 3];
    await el.updateComplete;
    expect(text(el, "spike-props-items")).to.equal("3");
    el.remove();
  });

  it("LC-01: willUpdate runs before render with the OLD changed values", async () => {
    const el = document.createElement("spike-props");
    const { log, stop } = lifecycleLog(el);
    try {
      document.body.appendChild(el);
      await el.updateComplete;
      el.shadowRoot.querySelector("[data-cy=spike-props-tick]").click();
      await el.updateComplete;

      const wills = log.filter((e) => e.type === "props-will");
      expect(wills).to.have.lengthOf(2);
      // first update: no old value; DOM already rendered when will fired? No —
      // will fires BEFORE render, but the first render happens in the same
      // update; domTicks at first will is "" (nothing rendered yet) or "0".
      expect(wills[0].detail.ticks).to.equal(undefined);
      // second update (tick 0 → 1): old value 0, DOM still shows 0 at will time
      expect(wills[1].detail.ticks).to.equal(0);
      expect(wills[1].domTicks).to.equal("0");

      const updateds = log.filter((e) => e.type === "props-updated");
      expect(updateds[updateds.length - 1].domTicks).to.equal("1");
    } finally {
      stop();
      el.remove();
    }
  });

  it("LC-02: updated fires after every rendered update, in lifecycle order", async () => {
    const el = document.createElement("spike-props");
    const { log, stop } = lifecycleLog(el);
    try {
      document.body.appendChild(el);
      await el.updateComplete;
      for (let i = 0; i < 2; i++) {
        el.shadowRoot.querySelector("[data-cy=spike-props-tick]").click();
        await el.updateComplete;
      }
      expect(log.map((e) => e.type)).to.eql([
        "props-will",
        "props-first",
        "props-updated",
        "props-will",
        "props-updated",
        "props-will",
        "props-updated",
      ]);
    } finally {
      stop();
      el.remove();
    }
  });

  it("LC-04: changed carries old values keyed by property name (will_seen state application)", async () => {
    const el = make();
    await el.updateComplete;
    // willUpdate applied will_seen on the first update (same render pass)
    expect(text(el, "spike-props-will")).to.equal("1");

    const { log, stop } = lifecycleLog(el);
    try {
      el.shadowRoot.querySelector("[data-cy=spike-props-tick]").click();
      await el.updateComplete;
      const will = log.find((e) => e.type === "props-will");
      expect(will.detail).to.eql({ ticks: 0 }); // OLD ticks, not the new 1
      expect(text(el, "spike-props-will")).to.equal("2");
    } finally {
      stop();
      el.remove();
    }
  });

  it("attribute: false state key is not observable as an attribute", async () => {
    const el = make();
    await el.updateComplete;
    el.shadowRoot.querySelector("[data-cy=spike-props-freeze]").click();
    await el.updateComplete;
    expect(el.frozen).to.equal(true);
    expect(el.hasAttribute("frozen")).to.equal(false);
    el.remove();
  });
});