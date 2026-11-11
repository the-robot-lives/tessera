// <spike-styles-panel> styles-DSL conformance (SpikeKit.StylesPanel):
// lit-parity §4.1 S-01…S-06 + EXTENSION-CONTRACT §9 X-14 (theming).
// Rendered-style assertions read getComputedStyle — never the stylesheet text.
import { expect, aTimeout } from "@open-wc/testing";
import { register } from "../../lib/spike_kit/spike-styles-panel.element.generated.mjs";
import { styles as sharedStyles } from "../../lib/spike_kit/shared_styles.mjs";

describe("<spike-styles-panel> styles DSL", () => {
  before(() => {
    register();
  });

  function make(attrs = {}, parent = document.body) {
    const el = document.createElement("spike-styles-panel");
    for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, value);
    parent.appendChild(el);
    return el;
  }

  it("S-06: static styles is a composed array [baseStyles, shared, ...author]", () => {
    const ctor = customElements.get("spike-styles-panel");
    expect(Array.isArray(ctor.styles)).to.equal(true);
    // base + shared module + two author css blocks
    expect(ctor.styles).to.have.lengthOf(4);
    expect(ctor.styles[1]).to.equal(sharedStyles);
  });

  it("S-01: base + author :host rules apply to the host", async () => {
    const el = make();
    await aTimeout(0);
    const cs = getComputedStyle(el);
    expect(cs.display).to.equal("block"); // baseStyles default
    expect(cs.paddingTop).to.equal("8px"); // author var() fallback
    expect(cs.borderTopWidth).to.equal("1px");
    el.remove();
  });

  it("S-02: :host([attr]) conditional style toggles with the attribute", async () => {
    const el = make();
    await aTimeout(0);
    expect(getComputedStyle(el).backgroundColor).to.not.equal("rgb(17, 17, 17)");
    el.setAttribute("tone", "dark");
    await aTimeout(0);
    expect(getComputedStyle(el).backgroundColor).to.equal("rgb(17, 17, 17)");
    el.removeAttribute("tone");
    await aTimeout(0);
    expect(getComputedStyle(el).backgroundColor).to.not.equal("rgb(17, 17, 17)");
    el.remove();
  });

  it("S-02: :host(.class) conditional style toggles with the class", async () => {
    const el = make();
    await aTimeout(0);
    expect(getComputedStyle(el).outlineStyle).to.not.equal("solid");
    el.classList.add("highlighted");
    await aTimeout(0);
    const cs = getComputedStyle(el);
    expect(cs.outlineStyle).to.equal("solid");
    expect(cs.outlineWidth).to.equal("2px");
    el.remove();
  });

  it("S-03: ::slotted() styles slotted children", async () => {
    const el = make();
    const p = document.createElement("p");
    p.textContent = "slotted";
    el.appendChild(p);
    await aTimeout(0);
    const cs = getComputedStyle(p);
    expect(cs.color).to.equal("rgb(204, 0, 204)"); // #c0c fallback
    expect(cs.marginTop).to.equal("0px");
    el.remove();
  });

  it("S-04: var(--tsr-*) fallbacks render unthemed; a parent override themes the element", async () => {
    const wrap = document.createElement("div");
    document.body.appendChild(wrap);
    const el = make({}, wrap);
    await aTimeout(0);

    const accent = el.shadowRoot.querySelector("[data-cy=spike-styles-panel-accent]");
    expect(getComputedStyle(accent).color).to.equal("rgb(102, 204, 255)"); // #6cf
    expect(getComputedStyle(el).borderTopColor).to.equal("rgb(102, 204, 255)");

    wrap.style.setProperty("--tsr-spike-styles-panel-accent", "#ff0000");
    await aTimeout(0);
    expect(getComputedStyle(accent).color).to.equal("rgb(255, 0, 0)");
    expect(getComputedStyle(el).borderTopColor).to.equal("rgb(255, 0, 0)");

    wrap.remove();
  });

  it("S-05: the shared style module's rules apply", async () => {
    const el = make();
    await aTimeout(0);
    const marker = el.shadowRoot.querySelector("[data-cy=spike-styles-panel-shared]");
    const cs = getComputedStyle(marker);
    expect(cs.letterSpacing).to.equal("0.5px");
    expect(cs.textTransform).to.equal("uppercase");
    el.remove();
  });

  it("S-06: every composed block applies and later entries win the cascade", async () => {
    const el = make();
    await aTimeout(0);
    const row = el.shadowRoot.querySelector("[data-cy=spike-styles-panel-row]");
    const accent = el.shadowRoot.querySelector("[data-cy=spike-styles-panel-accent]");
    const rowCs = getComputedStyle(row);
    expect(rowCs.display).to.equal("flex"); // block 1
    expect(rowCs.gap).to.equal("4px"); // block 2 (var fallback)
    // .accent color: block 1 #000, block 2 var(--tsr-…-accent, #6cf) — last wins
    expect(getComputedStyle(accent).color).to.equal("rgb(102, 204, 255)");
    el.remove();
  });

  it("X-14: every declared part exists in rendered DOM; the host exposes root", async () => {
    const el = make();
    await aTimeout(0);
    expect(el.getAttribute("part")).to.equal("root");
    const row = el.shadowRoot.querySelector('[part="row"]');
    const accent = el.shadowRoot.querySelector('[part="accent"]');
    expect(row).to.exist;
    expect(accent).to.exist;

    // ::part() reaches the declared parts from the outer tree
    const style = document.createElement("style");
    style.textContent = "spike-styles-panel::part(accent) { color: rgb(1, 2, 3); }";
    document.head.appendChild(style);
    await aTimeout(0);
    expect(getComputedStyle(accent).color).to.equal("rgb(1, 2, 3)");
    style.remove();
    el.remove();
  });

  it("X-14: declared custom properties resolve with fallbacks on a fresh element", async () => {
    const el = make();
    await aTimeout(0);
    const row = el.shadowRoot.querySelector("[data-cy=spike-styles-panel-row]");
    expect(getComputedStyle(row).gap).to.equal("4px"); // --tsr-…-gap fallback
    expect(getComputedStyle(el).paddingTop).to.equal("8px"); // --tsr-…-padding fallback
    el.remove();
  });
});