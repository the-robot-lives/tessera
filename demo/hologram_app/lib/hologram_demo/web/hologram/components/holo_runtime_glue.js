/**
 * Tier 2 spike — Hologram-host glue.
 *
 * js_import'ed by HoloRuntimePage and invoked via Hologram.JS.call in the
 * page's init/3 (replayed client-side after mount as a pending JS interop
 * action — script tags don't execute under Hologram's snabbdom patching).
 *
 * Loads the PREBUILT standalone bundles from /tessera/ with dynamic
 * imports (non-analyzable specifiers so Hologram's page esbuild leaves
 * them as runtime imports instead of inlining the tessera runtime into
 * the page bundle — the runtime stays shared exactly once) and registers
 * the custom elements. The tessera bridge (document-level
 * data-tsr-on listener) registers the emitted event names; the HOST's
 * globalThis.Hologram receives the dispatched page actions.
 *
 * Same-tag layering (EXTENSION-CONTRACT v0.1 §5.9): ThirdParty.TidyList
 * takes over the vendor tag `tsr-holo-editable-list` as an EXTENSION —
 * defined here under the vendor tag BEFORE any element connects, so the
 * page's markup elements resolve the layered module. The vendor module
 * itself stays mountable under an explicit alias (`plain-list`), and the
 * vendor behaviour is reachable through the injected base_action/3
 * dispatcher inside the layered module.
 */

import { registerEvents } from "@noizu/tessera-core";

const BASE = "/tessera/";
const BUNDLE = "tessera-runtime.esm.js";

let loadPromise = null;

export function loadHoloRuntime() {
  if (loadPromise) return loadPromise;

  loadPromise = (async () => {
    const rt = await import(BASE + BUNDLE);

    await import(BASE + "counter.esm.js");
    await import(BASE + "editable-list.esm.js");
    await import(BASE + "fancy-list.esm.js");
    await import(BASE + "tidy-list.esm.js");

    rt.defineElement("tsr-holo-counter", "HoloKit.Components.Counter");
    // takeover first: markup elements upgrade against the layered module
    rt.defineElement("tsr-holo-editable-list", "ThirdParty.TidyList");
    // the untouched vendor element stays mountable under an explicit alias
    rt.defineElement("plain-list", "HoloKit.Components.EditableList");
    rt.defineElement("fancy-list", "ThirdParty.FancyList");

    registerEvents(["count-changed", "item-saved", "item-archived"]);
  })().catch((error) => {
    loadPromise = null;
    console.error("[tessera-holo] host glue failed", error);
  });

  return loadPromise;
}
