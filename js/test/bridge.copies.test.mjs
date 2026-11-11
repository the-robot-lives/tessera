// FULL group: bridge singleton across duplicate module copies — the Hologram
// per-page esbuild bundle edge case (two instances of bridge.mjs sharing one
// globalThis singleton). Redundant-coverage hardening; the behavior-defining
// dispatch/parse core lives in the FAST group (bridge.test.mjs).
// docs/notes/test-tiering.md.
import { expect } from "@open-wc/testing";

const BRIDGE_KEY = Symbol.for("tessera.bridge");

describe("bridge singleton across module copies", () => {
  const BRIDGE_SRC = "../../priv/js/src/bridge.mjs";

  it("two independent module instances share one globalThis singleton", async () => {
    const copy1 = await import(BRIDGE_SRC);
    // Cache-busting query forces the dev server to evaluate a SECOND copy of
    // the module — what Hologram's per-page esbuild bundles produce.
    const copy2 = await import(`${BRIDGE_SRC}?copy=2`);
    expect(copy2).to.not.equal(copy1, "precondition: two distinct module instances");

    // The singleton is created lazily by getBridge(); in the original single
    // file the dispatch tests had already initialized it. This file runs in
    // isolation, so initialize it explicitly via copy1 before asserting.
    copy1.getBridge();
    const singleton = globalThis[BRIDGE_KEY];
    expect(singleton, "the bridge singleton exists on globalThis").to.exist;

    // Both copies register the same event name: still exactly ONE listener,
    // proven by exactly one dispatch per fired event.
    copy1.registerEvents(["singleton-evt"]);
    copy2.registerEvents(["singleton-evt"]);

    const host = document.createElement("div");
    host.setAttribute("data-tsr-on", "singleton-evt:ping@page");
    document.body.appendChild(host);

    const dispatches = [];
    const saved = globalThis.Hologram;
    globalThis.Hologram = { dispatchAction: (...a) => dispatches.push(a) };
    try {
      host.dispatchEvent(new CustomEvent("singleton-evt", { bubbles: true, composed: true, detail: { onceOnly: true } }));
    } finally {
      if (saved === undefined) delete globalThis.Hologram;
      else globalThis.Hologram = saved;
    }

    expect(dispatches).to.have.lengthOf(1, "one event ⇒ exactly one dispatch, even with two module copies");
    expect(dispatches[0]).to.deep.equal(["ping", "page", { once_only: true }]);
    expect(singleton.listeners.has("singleton-evt")).to.equal(true);
    host.remove();
  });

  it("behaviors registered through the singleton are visible to every copy", async () => {
    const behaviors1 = (await import("../../priv/js/src/behaviors.mjs")).behaviors;
    const behaviors2 = (await import(`${BRIDGE_SRC}?copy=2`)).getBridge().behaviors;
    behaviors1.add("singleton-behavior-tag", () => {});
    expect(behaviors2.has("singleton-behavior-tag")).to.equal(true, "one registry, shared via globalThis");
    behaviors1.remove("singleton-behavior-tag", behaviors1.get("singleton-behavior-tag")[0]);
    expect(behaviors2.has("singleton-behavior-tag")).to.equal(false);
  });
});