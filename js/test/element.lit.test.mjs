// FULL group: TesseraElement over LitElement — the second-host matrix.
// The core claim (shadow event → dispatchAction → re-render) is proven over
// plain HTMLElement in the FAST group (element.test.mjs); Lit is an additional
// host whose reactive-render/accessor interplay is exhaustive per-host coverage.
// The blocking e2e-smoke still exercises the Lit host end to end (the demo
// components extend TesseraElement(LitElement, …)). docs/notes/test-tiering.md.
import { expect, nextFrame } from "@open-wc/testing";
import { LitElement, html } from "lit";
import { TesseraElement } from "../../priv/js/src/element.mjs";
import { defineOnce } from "../../priv/js/src/define.mjs";
import { LIT_TAG, captureWarns } from "./helpers.mjs";

describe("TesseraElement over LitElement", () => {
  const litContract = {
    version: 1,
    tag: LIT_TAG,
    attrs: [{ name: "card-title", key: "cardTitle", type: "string" }],
    props: [{ name: "tagList", type: "list", json: true }],
    events: [{ name: "lit-select" }],
  };

  before(() => {
    class LitEl extends TesseraElement(LitElement, litContract) {
      static properties = {
        items: { type: Array },
      };
      render() {
        return html`<span data-cy="lit-tags">${(this.tagList ?? []).length}</span>`;
      }
    }
    defineOnce(LIT_TAG, LitEl);
  });

  it("observedAttributes merge Lit reactive props, contract attrs and tsr-props", () => {
    const observed = customElements.get(LIT_TAG).observedAttributes;
    expect(observed).to.include.members(["items", "card-title", "tsr-props"]);
  });

  it("attribute coercion works over Lit", async () => {
    const el = document.createElement(LIT_TAG);
    el.setAttribute("card-title", "Ada");
    document.body.appendChild(el);
    expect(el.cardTitle).to.equal("Ada");
    el.remove();
  });

  it("tsr-props assignment triggers a Lit reactive render", async () => {
    const el = document.createElement(LIT_TAG);
    el.setAttribute("tsr-props", JSON.stringify({ tagList: ["a", "b", "c"] }));
    document.body.appendChild(el);
    await el.updateComplete;
    await nextFrame();
    const text = el.shadowRoot?.querySelector("[data-cy=lit-tags]")?.textContent;
    expect(text).to.equal("3", "requestUpdate flows through Lit's reactive render");
    el.remove();
  });

  it("bad tsr-props JSON warns and never throws over Lit", async () => {
    const el = document.createElement(LIT_TAG);
    document.body.appendChild(el);
    await el.updateComplete;
    const warns = captureWarns(() => {
      el.setAttribute("tsr-props", "not-json");
    });
    await el.updateComplete;
    expect(warns.some((w) => w.includes("tsr-props"))).to.equal(true);
    el.remove();
  });

  it("tsr-props skips function-valued keys (requestUpdate) over Lit and warns once", async () => {
    const el = document.createElement(LIT_TAG);
    document.body.appendChild(el);
    await el.updateComplete;
    const seen = [];
    const original = console.warn;
    console.warn = (msg) => seen.push(String(msg));
    try {
      el.setAttribute("tsr-props", JSON.stringify({ requestUpdate: 1 }));
      el.setAttribute("tsr-props", JSON.stringify({ requestUpdate: 2 }));
    } finally {
      console.warn = original;
    }
    expect(typeof el.requestUpdate, "the method survives").to.equal("function");
    await el.updateComplete;
    expect(seen.filter((w) => w.includes('"requestUpdate"'))).to.have.lengthOf(1, "warned once per key");
    // The render pipeline is untouched: a reactive prop change still renders.
    el.setAttribute("card-title", "Grace");
    await el.updateComplete;
    expect(el.cardTitle).to.equal("Grace");
    el.remove();
  });

  it("removal resets accessor-backed Lit reactive props through the setter", async () => {
    const el = document.createElement(LIT_TAG);
    document.body.appendChild(el);
    await el.updateComplete;
    // `items` is declared in Lit `static properties` — assigning it goes
    // through Lit's accessor, so there is no own property to delete; the
    // reset must ride the setter instead.
    el.setAttribute("tsr-props", JSON.stringify({ items: ["x"] }));
    await el.updateComplete;
    expect(el.items).to.deep.equal(["x"]);

    el.removeAttribute("tsr-props");
    await el.updateComplete;
    expect(el.items).to.be.undefined;
    el.remove();
  });
});