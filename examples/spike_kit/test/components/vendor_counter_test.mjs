// <vendor-counter> — fresh-tag derivation end-to-end (conformance X-16,
// EXTENSION-CONTRACT.md §5/§9). SpikeKit.VendorCounter `use SpikeKit.Counter,
// tag: "vendor-counter"`: the derived tag registers, the MERGED spec drives the
// DOM, the overridden :increment down-calls the vendor base via real ES super,
// inherited members ride the class chain, and the base element keeps working.
import { expect, aTimeout } from "@open-wc/testing";
import { register } from "../../lib/spike_kit/vendor-counter.element.generated.mjs";
import { register as registerBase } from "../../lib/spike_kit/spike-counter.element.generated.mjs";

describe("<vendor-counter> (X-16 derivation)", () => {
  before(() => {
    registerBase();
    register();
  });

  function make(attrs = {}) {
    const el = document.createElement("vendor-counter");
    for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, value);
    document.body.appendChild(el);
    return el;
  }

  const text = (el, cy) =>
    el.shadowRoot.querySelector(`[data-cy=${cy}]`).textContent.trim();

  it("registers the derived tag as the mixed class", () => {
    const ctor = register();
    expect(customElements.get("vendor-counter")).to.equal(ctor);
  });

  it("leaves the base tag registered and behaving (base artifacts untouched)", async () => {
    expect(customElements.get("spike-counter")).to.be.a("function");
    const base = document.createElement("spike-counter");
    document.body.appendChild(base);
    await aTimeout(0);
    base.shadowRoot.querySelector("[data-cy=spike-counter-inc]").click();
    await aTimeout(0);
    expect(base.count).to.equal(1);
    base.remove();
  });

  it("renders the merged spec: inherited count + new extra/badge", async () => {
    const el = make({ badge: "Pro" });
    await aTimeout(0);
    expect(text(el, "vendor-counter-count")).to.equal("0");
    expect(text(el, "vendor-counter-extra")).to.equal("0");
    expect(el.shadowRoot.querySelector(".badge").textContent).to.equal("Pro");
    expect(el.count).to.equal(0);
    expect(el.extra).to.equal(0);
    expect(el.badge).to.equal("Pro");
    el.remove();
  });

  it("coerces the additive attr and inherited attrs to typed properties", async () => {
    const el = make({ badge: "X", step: "4" });
    await aTimeout(0);
    expect(el.badge).to.equal("X");
    expect(el.step).to.equal(4); // inherited attr still coerced
    el.remove();
  });

  it("overridden increment down-calls the vendor base via super, then layers extra", async () => {
    const el = make({ step: "2" });
    await aTimeout(0);
    const events = [];
    el.addEventListener("count-change", (e) => events.push(["count-change", e.detail]));
    el.addEventListener("vendor-ping", (e) => events.push(["vendor-ping", e.detail]));

    el.shadowRoot.querySelector("[data-cy=vendor-counter-inc]").click();
    await aTimeout(0);

    // base increment ran (count += step) AND derived layer ran (extra += 1)
    expect(el.count).to.equal(2);
    expect(el.extra).to.equal(1);
    expect(text(el, "vendor-counter-count")).to.equal("2");
    expect(text(el, "vendor-counter-extra")).to.equal("1");

    // both the inherited event (from the base down-call) and the new event fire
    const names = events.map(([n]) => n);
    expect(names).to.include("count-change");
    expect(names).to.include("vendor-ping");
    const ping = events.find(([n]) => n === "vendor-ping")[1];
    expect(ping.count).to.equal(2); // camelCase detail key
    el.remove();
  });

  it("the new additive action runs", async () => {
    const el = make();
    await aTimeout(0);
    el.shadowRoot.querySelector("[data-cy=vendor-counter-bump]").click();
    await aTimeout(0);
    expect(el.extra).to.equal(1);
    expect(el.count).to.equal(0); // untouched by bump_extra
    el.remove();
  });

  it("inherited decrement rides the ES class chain (not re-emitted)", async () => {
    const el = make({ step: "3" });
    await aTimeout(0);
    el.__tesseraRunAction("decrement", {});
    await aTimeout(0);
    expect(el.count).to.equal(-3);
    el.remove();
  });

  it("composes styles over the base (Lit does not auto-inherit styles)", async () => {
    const el = make();
    await aTimeout(0);
    // base styles + derived author block both adopted
    expect(el.shadowRoot.adoptedStyleSheets.length).to.be.at.least(2);
    el.remove();
  });
});