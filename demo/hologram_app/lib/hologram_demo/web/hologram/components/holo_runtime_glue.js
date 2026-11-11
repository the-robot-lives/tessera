/**
 * Tier 2 spike — Hologram-host glue.
 *
 * js_import'ed by HoloRuntimePage; the page bundle loads this module
 * eagerly on page load (initial SSR load AND client-side navigation), so
 * the bootstrap is a MODULE SIDE EFFECT below. (Hologram 0.10.1's JS.call
 * is a server-side pass-through when run in init/3 — client JS interop only
 * executes inside action handlers — so it cannot seed the bootstrap.)
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
    await import(BASE + "state_probe.esm.js");
    await import(BASE + "pipeline_probe.esm.js");
    await import(BASE + "editable_list.esm.js");
    await import(BASE + "fancy_list.esm.js");
    await import(BASE + "tidy_list.esm.js");

    rt.defineElement("tsr-holo-counter", "HoloKit.Components.Counter");
    // Tier-2 conformance fixture for the extension-contract state/action
    // surface (brief 3d; mirrors the Tier-1 `state` fixture behaviorally).
    rt.defineElement("tsr-holo-state-probe", "HoloKit.Components.StateProbe");
    // Tier-2 mirror of the Tier-1 `tsr-conf-pipeline` fixture — the shared
    // tier-agnostic X-05…X-11/X-20 bodies mount this tag.
    rt.defineElement("tsr-holo-pipeline-probe", "HoloKit.Components.PipelineProbe");
    // Tier-2 lifecycle recording fixture (brief 3c; LC-01…LC-04 + C-13/C-14
    // mount tag `tsr-holo-lifecycle`). Same Counter module, mounted through a
    // recording subclass of the runtime base class: every projected hook
    // appends {hook, changed, domText} to el.tesseraLifecycleLog, domText read
    // at hook time from [data-cy="holo-counter-count"] — the evidence that
    // willUpdate observes the PRE-patch DOM and firstUpdated/updated the
    // POST-patch DOM (test/conformance/cases/lc_lifecycle.mjs pins the shape).
    // ES6-safe on purpose (no class fields — the runtime's own bundler targets
    // es2021 and this file must mirror that discipline).
    class LifecycleProbeElement extends rt.TesseraHoloElement {
      recordLifecycle(hook, changed) {
        if (!this.tesseraLifecycleLog) this.tesseraLifecycleLog = [];
        const node = this.shadowRoot
          ? this.shadowRoot.querySelector('[data-cy="holo-counter-count"]')
          : null;
        this.tesseraLifecycleLog.push({
          hook,
          changed: {...(changed || {})},
          domText: node ? node.textContent.trim() : "",
        });
      }
      willUpdate(changed) {
        this.recordLifecycle("willUpdate", changed);
        super.willUpdate(changed);
      }
      firstUpdated(changed) {
        this.recordLifecycle("firstUpdated", changed);
        super.firstUpdated(changed);
      }
      updated(changed) {
        this.recordLifecycle("updated", changed);
        super.updated(changed);
      }
    }
    rt.defineElement("tsr-holo-lifecycle", "HoloKit.Components.Counter", LifecycleProbeElement);
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

// Module side effect: the page bundle executes this module on page load
// (initial load and every client-side navigation back onto the page — the
// ES-module registry caches it, so the bootstrap runs at most once per
// document, and custom-element definitions persist across navigations).
loadHoloRuntime();
