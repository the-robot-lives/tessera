// unsafe_html(expr) → Lit unsafeHTML (lit-parity #71) and guard([deps], expr)
// → Lit guard (#66), BoE need #4. Fixture: conf_unsafe_guard.ex.
import { expect } from "@open-wc/testing";
import "./fixtures/conformance/wtr-no-auto-register.mjs";
import { tag, register } from "./fixtures/conformance/tsr-conf-unsafe-guard.element.generated.mjs";

register();

async function mount() {
  const el = document.createElement(tag);
  document.body.appendChild(el);
  await el.updateComplete;
  return el;
}

const q = (el, cy) => el.shadowRoot.querySelector(`[data-cy="${cy}"]`);

describe("unsafe_html + guard (Tier 1)", () => {
  afterEach(() => {
    for (const el of document.querySelectorAll(tag)) el.remove();
  });

  it("unsafe_html renders the string as real markup, not escaped text", async () => {
    const el = await mount();
    const em = q(el, "conf-ug-html").querySelector('[data-cy="conf-ug-em"]');
    expect(em, "an <em> element exists").to.exist;
    expect(em.tagName).to.equal("EM");
    expect(q(el, "conf-ug-html").textContent).to.equal("trusted");
  });

  it("guard skips its body on unrelated changes and re-runs when a dependency changes", async () => {
    const el = await mount();
    expect(q(el, "conf-ug-guard").textContent).to.equal("n0:0");

    await el.dispatchAction("bump_other");
    await el.updateComplete;
    expect(q(el, "conf-ug-other").textContent).to.equal("1");
    expect(q(el, "conf-ug-guard").textContent, "guarded body stays stale").to.equal("n0:0");

    await el.dispatchAction("set_note", { note: "n1" });
    await el.updateComplete;
    expect(q(el, "conf-ug-guard").textContent, "dependency changed → re-evaluated").to.equal("n1:1");
  });
});
