// FULL group: skipped-prop warn-once across duplicate module copies — the
// Hologram per-page esbuild bundle edge case (two instances of element.mjs in
// one document). Redundant-coverage hardening of the warn-once invariant whose
// behavior-defining core lives in the FAST group. docs/notes/test-tiering.md.
import { expect } from "@open-wc/testing";
import { defineOnce } from "../../priv/js/src/define.mjs";
import { PLAIN_TAG, plainContract, captureWarns } from "./helpers.mjs";

describe("skipped-prop warn-once across module copies", () => {
  const WARNED_KEY = Symbol.for("tessera.warned-props");
  const COPY2_TAG = "tsr-el-plain-copy2";
  const PROBE_KEY = "_cross-copy-warn-probe";

  it("two module copies share one globalThis warn set — a skipped key warns once per document", async () => {
    const element1 = await import("../../priv/js/src/element.mjs");
    // Cache-busting query: a SECOND instance of the module, exactly what
    // Hologram's per-page esbuild bundles produce.
    const element2 = await import("../../priv/js/src/element.mjs?copy=2");
    expect(element2.TesseraElement).to.not.equal(
      element1.TesseraElement,
      "precondition: two distinct module instances",
    );

    class Copy2El extends element2.TesseraElement(HTMLElement, plainContract) {}
    // Defined under a UNIQUE tag (one definition per tag per document) with
    // the SAME contract: the dedupe key is `${contract.tag}:${key}`, so this
    // is exactly the duplicate-bundle scenario the global set exists for.
    defineOnce(COPY2_TAG, Copy2El);

    const dedupe = `${PLAIN_TAG}:${PROBE_KEY}`;
    globalThis[WARNED_KEY]?.delete(dedupe);

    const el1 = document.createElement(PLAIN_TAG);
    const el2 = document.createElement(COPY2_TAG);
    document.body.appendChild(el1);
    document.body.appendChild(el2);

    const warns = captureWarns(() => {
      el1.setAttribute("tsr-props", JSON.stringify({ [PROBE_KEY]: 1 }));
      el2.setAttribute("tsr-props", JSON.stringify({ [PROBE_KEY]: 2 }));
    });

    expect(warns.filter((w) => w.includes(`"${PROBE_KEY}"`))).to.have.lengthOf(
      1,
      "the second copy's skipped-key application must NOT re-warn (shared globalThis set)",
    );
    expect(globalThis[WARNED_KEY], "the set lives on globalThis under the Symbol.for key").to.exist;
    expect(globalThis[WARNED_KEY].has(dedupe)).to.equal(true);

    el1.remove();
    el2.remove();
  });
});