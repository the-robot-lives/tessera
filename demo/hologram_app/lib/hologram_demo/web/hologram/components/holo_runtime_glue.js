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
    await import(BASE + "slot_probe.esm.js");
    await import(BASE + "form_probe.esm.js");
    await import(BASE + "editable_list.esm.js");
    await import(BASE + "fancy_list.esm.js");
    await import(BASE + "tidy_list.esm.js");
    // brief 3f X-19: the §5.9 takeover chain — vendor + three tag: :inherit
    // layers, each a compiled bundle of its own.
    await import(BASE + "takeover_probe.esm.js");
    await import(BASE + "takeover_probe_ext_aaa.esm.js");
    await import(BASE + "takeover_probe_ext_bbb.esm.js");
    await import(BASE + "takeover_probe_ext_ccc.esm.js");
    await import(BASE + "takeover_probe_derived.esm.js");

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
    // Tier-2 slot fixture (brief 3e; SD-01…SD-04 mount `tsr-holo-slot-probe`).
    // The template uses the shim's data-tsr-slot markers (Hologram consumes
    // real <slot> markup — see HoloKit.Components.SlotProbe @moduledoc).
    rt.defineElement("tsr-holo-slot-probe", "HoloKit.Components.SlotProbe");
    // Tier-2 forms fixture (brief 3e; FM-01…FM-03 mount `tsr-holo-form-probe`).
    // The module declares __tsr_form_associated__ ⇒ the manifest carries
    // formAssociated ⇒ defineElement sets static formAssociated and the
    // constructor attaches ElementInternals (§6.7). This subclass is the
    // DOCUMENTED seam pattern the FM cases exercise: every render pushes
    // state.value through internals.setFormValue (#147), formResetCallback
    // (#148) dispatches the component's reset_value (which re-renders and
    // re-pushes), formDisabledCallback (#149) records the transition — all
    // signals land in el.tesseraFormSignals. ES6-safe like the lifecycle
    // subclass above (no class fields, no ??=).
    class FormProbeElement extends rt.TesseraHoloElement {
      pushFormValue() {
        if (this.internals) {
          const v = this.state.value;
          this.internals.setFormValue(v == null ? "" : String(v));
        }
      }
      firstUpdated(changed) {
        super.firstUpdated(changed);
        this.pushFormValue();
      }
      updated(changed) {
        super.updated(changed);
        this.pushFormValue();
      }
      formResetCallback() {
        if (!this.tesseraFormSignals) this.tesseraFormSignals = [];
        this.tesseraFormSignals.push("reset");
        super.formResetCallback();
        this.dispatchAction("reset_value");
      }
      formDisabledCallback(disabled) {
        if (!this.tesseraFormSignals) this.tesseraFormSignals = [];
        this.tesseraFormSignals.push(disabled ? "disabled" : "enabled");
        super.formDisabledCallback(disabled);
      }
    }
    rt.defineElement("tsr-holo-form-probe", "HoloKit.Components.FormProbe", FormProbeElement);
    // takeover first: markup elements upgrade against the layered module
    rt.defineElement("tsr-holo-editable-list", "ThirdParty.TidyList");
    // the untouched vendor element stays mountable under an explicit alias
    rt.defineElement("plain-list", "HoloKit.Components.EditableList");
    rt.defineElement("fancy-list", "ThirdParty.FancyList");
    // brief 3f (X-19): §5.9 tag-takeover chain. The vendor's defineElement
    // call DEFINES the tag; each `tag: :inherit` layer then joins as a
    // MODULE layer with its §5.9 chain coordinates (mirroring the Elixir
    // specs — a linear spine ccc → bbb → aaa → vendor, since Hologram's IR
    // has no `super`). The wrapper re-points the mount module to the
    // chain-OUTERMOST layer (Ccc): its compiled base_action/3 spine contains
    // every layer, so the mounted component runs the whole chain — marker
    // events included (layers js_emit synchronously).
    rt.defineElement("tsr-holo-takeover-probe", "HoloKit.Components.TakeoverProbe");
    rt.defineElement("tsr-holo-takeover-probe", "HoloKit.Components.TakeoverProbeExtAaa", undefined, {depth: 1});
    rt.defineElement("tsr-holo-takeover-probe", "HoloKit.Components.TakeoverProbeExtBbb", undefined, {depth: 2, priority: 10});
    rt.defineElement("tsr-holo-takeover-probe", "HoloKit.Components.TakeoverProbeExtCcc", undefined, {depth: 3});
    // brief 3f (X-16): §5.10 derivation — the vendor derived onto its OWN
    // tag (fresh surface: inherited actions + a new :reset), base untouched.
    rt.defineElement("tsr-holo-takeover-derived", "HoloKit.Components.TakeoverProbeDerived");

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
