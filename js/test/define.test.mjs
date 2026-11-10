import { expect } from "@open-wc/testing";
import { defineOnce } from "../../priv/js/src/define.mjs";

describe("defineOnce", () => {
  it("defines a fresh tag and returns the ctor", () => {
    class A extends HTMLElement {}
    const result = defineOnce("tsr-define-a", A);
    expect(result).to.equal(A);
    expect(customElements.get("tsr-define-a")).to.equal(A);
  });

  it("double-define: warns once, does not throw, first definition wins", () => {
    class First extends HTMLElement {}
    defineOnce("tsr-define-b", First);

    const warns = [];
    const original = console.warn;
    console.warn = (msg) => warns.push(String(msg));
    let returned;
    try {
      returned = defineOnce("tsr-define-b", class extends HTMLElement {});
    } finally {
      console.warn = original;
    }

    expect(returned).to.equal(First, "existing ctor is returned");
    expect(customElements.get("tsr-define-b")).to.equal(First, "first definition wins");
    expect(warns).to.have.lengthOf(1, "exactly one warning for the tag");
    expect(warns[0]).to.include("tsr-define-b");
  });

  it("warns at most ONCE per tag across repeated duplicate defines", () => {
    class Keeper extends HTMLElement {}
    defineOnce("tsr-define-c", Keeper);
    let warnCount = 0;
    const original = console.warn;
    console.warn = () => {
      warnCount += 1;
    };
    try {
      defineOnce("tsr-define-c", class extends HTMLElement {});
      defineOnce("tsr-define-c", class extends HTMLElement {});
    } finally {
      console.warn = original;
    }
    expect(warnCount).to.equal(1, "the first duplicate warns; every later duplicate is silent");
  });

  it("re-defining with the SAME ctor warns nothing", () => {
    class Same extends HTMLElement {}
    defineOnce("tsr-define-d", Same);
    let warnCount = 0;
    const original = console.warn;
    console.warn = () => {
      warnCount += 1;
    };
    try {
      const returned = defineOnce("tsr-define-d", Same);
      expect(returned).to.equal(Same);
    } finally {
      console.warn = original;
    }
    expect(warnCount).to.equal(0);
  });
});
