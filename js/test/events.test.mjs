import { expect } from "@open-wc/testing";
import { emit, snakeKeysDeep, camelKeysDeep } from "../../priv/js/src/events.mjs";

describe("snakeKeysDeep", () => {
  it("converts flat camelCase keys", () => {
    expect(snakeKeysDeep({ personaId: "ada", clickCount: 2 })).to.deep.equal({ persona_id: "ada", click_count: 2 });
  });

  it("converts nested plain objects", () => {
    expect(snakeKeysDeep({ outer: { innerKey: { deepKey: 1 } } })).to.deep.equal({ outer: { inner_key: { deep_key: 1 } } });
  });

  it("converts keys inside arrays (nested arrays too)", () => {
    expect(snakeKeysDeep([{ aB: 1 }, "scalar", [{ cD: 2 }]])).to.deep.equal([{ a_b: 1 }, "scalar", [{ c_d: 2 }]]);
  });

  it("leaves primitives untouched", () => {
    expect(snakeKeysDeep("personaId")).to.equal("personaId");
    expect(snakeKeysDeep(42)).to.equal(42);
    expect(snakeKeysDeep(null)).to.equal(null);
  });

  it("leaves non-plain objects as-is (Date, Map, class instances)", () => {
    const ts = new Date("2026-11-10T00:00:00Z");
    const map = new Map([["someKey", 1]]);
    class Wrapper {
      constructor() {
        this.someProp = 1;
      }
    }
    const wrapper = new Wrapper();
    const out = snakeKeysDeep({ ts, map, wrapper });
    expect(out.ts).to.equal(ts);
    expect(out.map).to.equal(map);
    expect(out.wrapper).to.equal(wrapper);
    expect(out.ts.someProp).to.be.undefined;
    expect(ts.getTime()).to.equal(Date.parse("2026-11-10T00:00:00Z"));
  });
});

describe("camelKeysDeep", () => {
  it("converts flat snake_case keys", () => {
    expect(camelKeysDeep({ persona_id: "ada", click_count: 2 })).to.deep.equal({ personaId: "ada", clickCount: 2 });
  });

  it("converts nested objects and arrays", () => {
    expect(camelKeysDeep({ outer_key: [{ inner_key: 1 }] })).to.deep.equal({ outerKey: [{ innerKey: 1 }] });
  });

  it("round-trips with snakeKeysDeep", () => {
    const original = { personaId: "ada", meta: { maxScore: 9, items: [{ itemId: "x" }] } };
    expect(camelKeysDeep(snakeKeysDeep(original))).to.deep.equal(original);
  });

  it("leaves non-plain objects as-is", () => {
    const map = new Map();
    const out = camelKeysDeep({ map });
    expect(out.map).to.equal(map);
  });
});

describe("emit", () => {
  it("dispatches a composed, bubbling CustomEvent carrying the detail", () => {
    const host = document.createElement("div");
    document.body.appendChild(host);
    const seen = [];
    const listener = (e) => seen.push(e);
    document.addEventListener("tsr-test-emit", listener);

    // Emit from inside a shadow root: the event must still reach the document.
    const child = document.createElement("button");
    host.attachShadow({ mode: "open" }).appendChild(child);
    const result = emit(child, "tsr-test-emit", { personaId: "ada" });

    document.removeEventListener("tsr-test-emit", listener);
    expect(result).to.equal(true);
    expect(seen).to.have.lengthOf(1);
    expect(seen[0].type).to.equal("tsr-test-emit");
    expect(seen[0].detail).to.deep.equal({ personaId: "ada" });
    expect(seen[0].bubbles).to.equal(true);
    expect(seen[0].composed).to.equal(true);
    host.remove();
  });
});
