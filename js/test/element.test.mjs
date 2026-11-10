import { expect, nextFrame } from "@open-wc/testing";
import { LitElement, html } from "lit";
import { TesseraElement } from "../../priv/js/src/element.mjs";
import { defineOnce } from "../../priv/js/src/define.mjs";
import { behaviors } from "../../priv/js/src/behaviors.mjs";
import { getBridge } from "../../priv/js/src/bridge.mjs";

const PLAIN_TAG = "tsr-el-plain";
const LIT_TAG = "tsr-el-lit";

const plainContract = {
  version: 1,
  tag: PLAIN_TAG,
  attrs: [
    { name: "display-name", key: "displayName", type: "string", required: true, default: null },
    { name: "count", key: "count", type: "integer", default: 0 },
    { name: "ratio", key: "ratio", type: "float" },
    { name: "active", key: "active", type: "boolean" },
  ],
  props: [{ name: "tagList", type: "list", json: true, default: [] }],
  events: [{ name: "plain-select", detail: { personaId: "string" } }],
  slots: ["default"],
  cy: "plain-el-root",
};

function captureWarns(fn) {
  const warns = [];
  const original = console.warn;
  console.warn = (msg) => warns.push(String(msg));
  try {
    fn();
  } finally {
    console.warn = original;
  }
  return warns;
}

describe("TesseraElement over plain HTMLElement", () => {
  before(() => {
    class PlainEl extends TesseraElement(HTMLElement, plainContract) {}
    defineOnce(PLAIN_TAG, PlainEl);
  });

  function make(attrs = {}, tsrProps) {
    const el = document.createElement(PLAIN_TAG);
    for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, value);
    if (tsrProps !== undefined) el.setAttribute("tsr-props", typeof tsrProps === "string" ? tsrProps : JSON.stringify(tsrProps));
    document.body.appendChild(el);
    return el;
  }

  it("observedAttributes = contract attrs + tsr-props, deduped", () => {
    const observed = customElements.get(PLAIN_TAG).observedAttributes;
    expect(observed).to.include.members(["display-name", "count", "ratio", "active", "tsr-props"]);
    expect(new Set(observed).size).to.equal(observed.length);
  });

  it("merges with Base's own observedAttributes", () => {
    class Base2 extends HTMLElement {
      static observedAttributes = ["own-attr"];
    }
    class Merged extends TesseraElement(Base2, plainContract) {}
    const observed = Merged.observedAttributes;
    expect(observed).to.include("own-attr");
    expect(observed).to.include("tsr-props");
    expect(observed.filter((a) => a === "tsr-props")).to.have.lengthOf(1);
  });

  it("coerces attribute types (string / integer / float / boolean presence)", () => {
    const el = make({ "display-name": "Ada", count: "42", ratio: "1.5", active: "" });
    expect(el.displayName).to.equal("Ada");
    expect(el.count).to.equal(42);
    expect(el.ratio).to.equal(1.5);
    expect(el.active).to.equal(true);
    el.remove();
  });

  it("boolean attrs default to false when absent", () => {
    const el = make({ "display-name": "Ada" });
    expect(el.active).to.equal(false);
    el.remove();
  });

  it("tracks attribute changes live (set and remove)", () => {
    const el = make({ "display-name": "Ada", count: "42", active: "" });
    el.setAttribute("count", "7");
    expect(el.count).to.equal(7);
    el.removeAttribute("active");
    expect(el.active).to.equal(false);
    el.setAttribute("active", "");
    expect(el.active).to.equal(true);
    el.setAttribute("ratio", "2.25");
    expect(el.ratio).to.equal(2.25);
    el.remove();
  });

  it("unparseable numbers fall back to the attr default (or null)", () => {
    const el = make({ count: "not-a-number", ratio: "x" });
    expect(el.count).to.equal(0); // contract default
    expect(el.ratio).to.equal(null);
    el.remove();
  });

  it("parses tsr-props into properties (pre-upgrade assignment included)", () => {
    const el = make({}, { tagList: ["a", "b"], meta: { maxScore: 9 } });
    expect(el.tagList).to.deep.equal(["a", "b"]);
    expect(el.meta).to.deep.equal({ maxScore: 9 });
    el.remove();
  });

  it("bad tsr-props JSON warns and never throws", () => {
    let el;
    const warns = captureWarns(() => {
      el = make({}, "{not json");
    });
    expect(warns.some((w) => w.includes("tsr-props"))).to.equal(true);
    expect(el.tagList).to.be.undefined;
    el.remove();
  });

  it("non-object tsr-props JSON warns and is ignored", () => {
    let el;
    const warns = captureWarns(() => {
      el = make({}, "[1,2]");
    });
    expect(warns.some((w) => w.includes("tsr-props"))).to.equal(true);
    el.remove();
  });

  describe("tsr-props guard (reserved and method keys)", () => {
    it("ignores `_`-prefixed reserved keys, so `__tesseraCleanups` cannot break disconnect cleanups", () => {
      let cleaned = 0;
      const probe = () => () => {
        cleaned += 1;
      };
      behaviors.add(PLAIN_TAG, probe);
      const el = make({});
      expect(el.__tesseraCleanups).to.have.lengthOf(1);

      captureWarns(() => {
        el.setAttribute("tsr-props", JSON.stringify({ __tesseraCleanups: null }));
      });

      expect(el.__tesseraCleanups, "reserved key was not clobbered").to.not.equal(null);
      expect(el.__tesseraCleanups).to.have.lengthOf(1);
      el.remove();
      expect(cleaned).to.equal(1, "disconnect cleanups still ran");
      behaviors.remove(PLAIN_TAG, probe);
    });

    it("warns once per skipped key, not once per application", () => {
      const el = make({});
      const seen = [];
      const original = console.warn;
      console.warn = (msg) => seen.push(String(msg));
      try {
        el.setAttribute("tsr-props", JSON.stringify({ _second: 1 }));
        el.setAttribute("tsr-props", JSON.stringify({ _second: 2 }));
        el.setAttribute("tsr-props", JSON.stringify({ _second: 3, _fresh: 4 }));
      } finally {
        console.warn = original;
      }
      el.remove();
      expect(seen.filter((w) => w.includes('"_second"')), "exactly one warning for the key across re-applications").to.have.lengthOf(1);
      expect(seen.filter((w) => w.includes('"_fresh"')), "a new key warns on first sight").to.have.lengthOf(1);
    });

    it("skips keys whose current value is a function (plain-element contrast: non-functions still assign)", () => {
      const el = make({});
      const seen = [];
      const original = console.warn;
      console.warn = (msg) => seen.push(String(msg));
      try {
        el.setAttribute("tsr-props", JSON.stringify({ requestUpdate: 1 }));
      } finally {
        console.warn = original;
      }
      expect(el.requestUpdate).to.equal(1, "plain HTMLElement has no requestUpdate method — nothing to protect, value assigns");
      expect(() => el.setAttribute("tsr-props", JSON.stringify({ more: "x" }))).to.not.throw(
        undefined,
        "a clobbered requestUpdate must not break applyTsrProps",
      );
      expect(seen.filter((w) => w.includes('"requestUpdate"'))).to.have.lengthOf(0);
      el.remove();
    });
  });

  it("connectedCallback registers the contract's events with the bridge", () => {
    const el = make({});
    expect(getBridge().listeners.has("plain-select")).to.equal(true);
    expect(getBridge().tags.has(PLAIN_TAG)).to.equal(true);
    el.remove();
  });

  describe("behaviors", () => {
    const BEHAVIOR_TAG = PLAIN_TAG; // registry is keyed by contract tag
    let runs;
    let cleanups;

    beforeEach(() => {
      runs = [];
      cleanups = [];
      behaviors.add(BEHAVIOR_TAG, (el) => {
        runs.push(el);
        return () => cleanups.push(el);
      });
    });

    afterEach(() => {
      for (const fn of behaviors.get(BEHAVIOR_TAG)) behaviors.remove(BEHAVIOR_TAG, fn);
    });

    it("behavior runs on connect; cleanup runs on disconnect", () => {
      const el = make({});
      expect(runs).to.have.lengthOf(1);
      expect(runs[0]).to.equal(el);
      el.remove();
      expect(cleanups).to.have.lengthOf(1);
      expect(cleanups[0]).to.equal(el);
    });

    it("behavior runs again on every reconnect", () => {
      const el = make({});
      el.remove();
      document.body.appendChild(el);
      expect(runs).to.have.lengthOf(2);
      expect(cleanups).to.have.lengthOf(1);
      el.remove();
      expect(cleanups).to.have.lengthOf(2);
    });

    it("a throwing behavior does not break connection (warn only)", () => {
      behaviors.add(BEHAVIOR_TAG, () => {
        throw new Error("boom");
      });
      let el;
      const warns = captureWarns(() => {
        el = make({});
      });
      expect(runs).to.have.lengthOf(1, "first behavior still ran");
      expect(warns.some((w) => w.includes("boom"))).to.equal(true);
      el.remove();
    });
  });
});

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
});
