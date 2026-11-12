// render_root: :light (lit-parity row #96, BoE need #1) — a compiled Tier-1
// element that renders into ITSELF instead of a shadow root. Fixture:
// test/support/conformance/conf_light.ex → tsr-conf-light.element.generated.mjs.
import { expect } from "@open-wc/testing";
import "./fixtures/conformance/wtr-no-auto-register.mjs";
import { tag, register } from "./fixtures/conformance/tsr-conf-light.element.generated.mjs";

register();

async function mount() {
  const el = document.createElement(tag);
  document.body.appendChild(el);
  await el.updateComplete;
  return el;
}

describe("render_root: :light (Tier 1)", () => {
  afterEach(() => {
    for (const el of document.querySelectorAll(tag)) el.remove();
  });

  it("renders into the element itself — no shadow root", async () => {
    const el = await mount();

    expect(el.shadowRoot).to.equal(null);
    expect(el.renderRoot).to.equal(el);
    expect(el.querySelector('[data-cy="conf-light-count"]').textContent).to.equal("0");
    // light content is reachable from the document, which is the point
    expect(document.querySelector(`${tag} [data-cy="conf-light-root"]`)).to.exist;
  });

  it("template bindings, actions and contract events still work", async () => {
    const el = await mount();
    const heard = [];
    document.addEventListener("conf-light-ping", (e) => heard.push(e.detail), { once: true });

    el.querySelector('[data-cy="conf-light-inc"]').click();
    await el.updateComplete;

    expect(el.querySelector('[data-cy="conf-light-count"]').textContent).to.equal("1");
    expect(heard).to.deep.equal([{ count: 1 }]);
  });

  it("adopts the element styles into the document additively, once", async () => {
    const sentinel = new CSSStyleSheet();
    sentinel.replaceSync(".light-sentinel { color: red; }");
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, sentinel];

    const a = await mount();
    const before = document.adoptedStyleSheets.length;
    await mount(); // a second instance must not re-adopt

    expect(document.adoptedStyleSheets.length).to.equal(before);
    expect(document.adoptedStyleSheets).to.include(sentinel); // never replaced
    const color = getComputedStyle(a.querySelector('[data-cy="conf-light-count"]')).color;
    expect(color).to.equal("rgb(1, 2, 3)");
  });
});
