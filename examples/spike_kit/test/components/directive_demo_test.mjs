// <spike-directive-demo> generated-element tests (SpikeKit.DirectiveDemo,
// brief 1d): class_map / style_map / if_defined / nothing lowering from the
// DSL to the lit directives, exercised through the SOURCE module (mirrors the
// conformance D-01/D-02/D-06/T-06 cases). The BUILT-bundle variants (inlined +
// shared-runtime) live in the test:runtime lane — runtime_variant_test.mjs /
// inlined_variant_test.mjs.
import { expect } from "@open-wc/testing";
import { register } from "../../lib/spike_kit/spike-directive-demo.element.generated.mjs";

describe("<spike-directive-demo>", () => {
  before(() => {
    register();
  });

  function make(attrs = {}) {
    const el = document.createElement("spike-directive-demo");
    for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, value);
    document.body.appendChild(el);
    return el;
  }

  const cy = (el, name) => el.shadowRoot.querySelector(`[data-cy=${name}]`);

  it("defines the custom element", () => {
    const ctor = register();
    expect(customElements.get("spike-directive-demo")).to.equal(ctor);
  });

  it("D-01: class_map toggles classes from state", async () => {
    const el = make();
    await el.updateComplete;
    const node = cy(el, "spike-dir-class");
    expect(node.classList.contains("active")).to.equal(false);
    cy(el, "spike-dir-toggle-active").click();
    await el.updateComplete;
    expect(node.classList.contains("active")).to.equal(true);
    cy(el, "spike-dir-toggle-highlight").click();
    await el.updateComplete;
    expect(node.classList.contains("highlight")).to.equal(true);
    cy(el, "spike-dir-toggle-active").click();
    await el.updateComplete;
    expect(node.classList.contains("active")).to.equal(false);
    expect(node.classList.contains("highlight")).to.equal(true);
    el.remove();
  });

  it("D-02: style_map sets inline styles and custom properties (attr-reactive)", async () => {
    const el = make();
    await el.updateComplete;
    const node = cy(el, "spike-dir-style");
    expect(node.style.backgroundColor).to.equal("red");
    expect(node.style.getPropertyValue("--spike-directive-demo-accent").trim()).to.equal("blue");
    el.setAttribute("bg", "green");
    await el.updateComplete;
    expect(node.style.backgroundColor).to.equal("green");
    el.remove();
  });

  it("D-06: if_defined removes the attribute when undefined", async () => {
    const el = make();
    await el.updateComplete;
    const node = cy(el, "spike-dir-defined");
    expect(node.hasAttribute("title")).to.equal(false);
    el.setAttribute("title-text", "hello");
    await el.updateComplete;
    expect(node.getAttribute("title")).to.equal("hello");
    el.removeAttribute("title-text");
    await el.updateComplete;
    expect(node.hasAttribute("title")).to.equal(false);
    el.remove();
  });

  it("T-06: nothing renders no content node and no attribute", async () => {
    const el = make();
    await el.updateComplete;
    const child = cy(el, "spike-dir-nothing-child");
    // lit-html keeps a comment marker for the child part itself — assert on
    // rendered content, not the raw childNodes count (conformance T-06).
    expect(child.textContent).to.equal("");
    expect(child.children.length).to.equal(0);
    expect([...child.childNodes].every((n) => n.nodeType === 8)).to.equal(true);
    expect(cy(el, "spike-dir-nothing-attr").hasAttribute("title")).to.equal(false);
    el.remove();
  });
});
