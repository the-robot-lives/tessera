// Tier-1 conformance harness — Web Test Runner adapter support (NOT a test
// file: no `.test.mjs` suffix, so WTR never runs it as a suite).
//
// Supplies the tier-agnostic `mount(spec)` handle the case bodies use, backed
// by the @noizu/tessera-core JS runtime (priv/js/src). Fixtures are minimal
// custom elements built on the REAL runtime primitives — TesseraElement
// (attr coercion / tsr-props / behaviors), defineOnce (registration), emit
// (composed+bubbling CustomEvents), and the document bridge (data-tsr-on).
// The shadow DOM a fixture renders is test scaffolding; the behaviors the
// cases assert are the runtime's. Compiled-DSL fixtures (template/styles)
// land with the feature briefs; until then those cases are pending.
//
// Mount handle contract (both tiers satisfy it — see test/conformance/README.md):
//   { el, tag, shadowRoot, win, waitFor(fn, timeout?), nextEvent(name, node?, timeout?), settle() }

import {expect} from "@open-wc/testing";
import {TesseraElement} from "../../priv/js/src/element.mjs";
import {defineOnce} from "../../priv/js/src/define.mjs";
import {emit} from "../../priv/js/src/events.mjs";
import {CASES, tally} from "../../test/conformance/support/registry.mjs";

// Compiled-DSL fixtures (brief 4b case-fill): REAL Lit elements generated from
// test/support/conformance/*.ex by the element DSL + LitCodegen, committed
// under fixtures/conformance/ (regenerate: MIX_ENV=test mix run
// test/conformance/support/generate_fixtures.exs). Each auto-registers on
// import via defineOnce; the core import is rewritten to ../../../../priv/js/src
// so these share the SAME runtime module instances as the JS-core fixtures.
import {tag as STATE_TAG, TsrConfState} from "./fixtures/conformance/tsr-conf-state.element.generated.mjs";
import {tag as TEMPLATE_TAG, TsrConfTemplate} from "./fixtures/conformance/tsr-conf-template.element.generated.mjs";
import {tag as STYLES_TAG, TsrConfStyles} from "./fixtures/conformance/tsr-conf-styles.element.generated.mjs";
import {tag as SLOTS_TAG, TsrConfSlots} from "./fixtures/conformance/tsr-conf-slots.element.generated.mjs";
import {tag as DIRECTIVES_TAG, TsrConfDirectives} from "./fixtures/conformance/tsr-conf-directives.element.generated.mjs";
import {tag as PIPELINE_TAG, TsrConfPipeline} from "./fixtures/conformance/tsr-conf-pipeline.element.generated.mjs";
// X-17 (brief 2d): region base + slot_template-derived vendor. Importing the
// vendor module side-effect-registers the base too (it imports it by relative
// path); defineOnce keeps both registrations idempotent.
import {tag as REGION_TAG, TsrConfRegion} from "./fixtures/conformance/tsr-conf-region.element.generated.mjs";
import {tag as REGION_VENDOR_TAG, TsrConfRegionVendor} from "./fixtures/conformance/tsr-conf-region-vendor.element.generated.mjs";

const COUNTER_TAG = "tsr-conf-counter";
const PROPS_TAG = "tsr-conf-props";
const EVENTS_TAG = "tsr-conf-events";

const counterContract = {
  version: 1,
  tag: COUNTER_TAG,
  attrs: [
    {name: "label", key: "label", type: "string", default: "Count"},
    {name: "step", key: "step", type: "integer", default: 1},
  ],
  props: [],
  events: [{name: "count-changed", detail: {count: "integer", delta: "integer"}}],
  slots: ["default"],
};

const propsContract = {
  version: 1,
  tag: PROPS_TAG,
  attrs: [
    {name: "display-name", key: "displayName", type: "string", required: true, default: null},
    {name: "count", key: "count", type: "integer", default: 0},
    {name: "ratio", key: "ratio", type: "float"},
    {name: "active", key: "active", type: "boolean"},
  ],
  props: [{name: "tagList", type: "list", json: true, default: []}],
  events: [],
  slots: ["default"],
};

const eventsContract = {
  version: 1,
  tag: EVENTS_TAG,
  attrs: [],
  props: [],
  events: [{name: "conf-select", detail: {personaId: "string", nested: "object"}}],
  slots: ["default"],
};

// <tsr-conf-counter> — mirrors the Tier-2 tsr-holo-counter surface: a
// [data-cy=holo-counter-inc] button increments state and emits the composed,
// bubbling `count-changed` event with camelCase {count, delta} detail; the
// running count renders into [data-cy=holo-counter-count].
class ConfCounter extends TesseraElement(HTMLElement, counterContract) {
  connectedCallback() {
    super.connectedCallback();
    this.__count = 0;
    const root = this.attachShadow({mode: "open"});
    root.innerHTML =
      `<div data-cy="holo-counter-root">` +
      `<button type="button" data-cy="holo-counter-inc">+</button>` +
      `<span data-cy="holo-counter-count">0</span>` +
      `</div>`;
    root.querySelector("[data-cy=holo-counter-inc]").addEventListener("click", () => {
      const step = typeof this.step === "number" ? this.step : 1;
      this.__count += step;
      root.querySelector("[data-cy=holo-counter-count]").textContent = String(this.__count);
      emit(this, "count-changed", {count: this.__count, delta: step});
    });
  }
}

// <tsr-conf-events> — a [data-cy=conf-select-btn] button emits `conf-select`
// with nested camelCase detail, for the bridge (data-tsr-on) case X-04.
class ConfEvents extends TesseraElement(HTMLElement, eventsContract) {
  connectedCallback() {
    super.connectedCallback();
    const root = this.attachShadow({mode: "open"});
    root.innerHTML = `<button type="button" data-cy="conf-select-btn">select</button>`;
    root.querySelector("[data-cy=conf-select-btn]").addEventListener("click", () => {
      emit(this, "conf-select", {personaId: "p1", nested: {maxScore: 9}});
    });
  }
}

// <tsr-conf-props> — contract-driven attr coercion + tsr-props (no template).
class ConfProps extends TesseraElement(HTMLElement, propsContract) {}

const FIXTURES = {
  counter: {tag: COUNTER_TAG, ctor: ConfCounter},
  props: {tag: PROPS_TAG, ctor: ConfProps},
  events: {tag: EVENTS_TAG, ctor: ConfEvents},
  // Compiled-DSL fixtures (Tier-1 only; Tier-2 reports these adapter-pending
  // until its compiled fixtures land with the feature briefs).
  state: {tag: STATE_TAG, ctor: TsrConfState},
  template: {tag: TEMPLATE_TAG, ctor: TsrConfTemplate},
  styles: {tag: STYLES_TAG, ctor: TsrConfStyles},
  slots: {tag: SLOTS_TAG, ctor: TsrConfSlots},
  directives: {tag: DIRECTIVES_TAG, ctor: TsrConfDirectives},
  pipeline: {tag: PIPELINE_TAG, ctor: TsrConfPipeline},
  regionBase: {tag: REGION_TAG, ctor: TsrConfRegion},
  regionVendor: {tag: REGION_VENDOR_TAG, ctor: TsrConfRegionVendor},
};

let defined = false;
const mounted = [];

/** Register the fixture elements once (idempotent via defineOnce). */
export function defineFixtures() {
  if (defined) return;
  for (const {tag, ctor} of Object.values(FIXTURES)) defineOnce(tag, ctor);
  defined = true;
}

function waitFor(fn, timeout = 2000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const tick = () => {
      let ok = false;
      try {
        ok = fn();
      } catch {
        ok = false;
      }
      if (ok) return resolve();
      if (Date.now() - start > timeout) return reject(new Error("conformance: waitFor timed out"));
      setTimeout(tick, 10);
    };
    tick();
  });
}

function nextEvent(name, node = window.document, timeout = 2000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      node.removeEventListener(name, handler);
      reject(new Error(`conformance: nextEvent("${name}") timed out`));
    }, timeout);
    function handler(event) {
      clearTimeout(timer);
      node.removeEventListener(name, handler);
      resolve(event.detail);
    }
    node.addEventListener(name, handler);
  });
}

/**
 * mount(spec) — create a fresh fixture element, apply attrs, connect it, wait
 * for readiness, and return the tier-agnostic handle.
 * @param {{fixture:string, attrs?:Object}} spec
 */
export async function mount(spec) {
  const fixture = FIXTURES[spec.fixture];
  if (!fixture) throw new Error(`conformance: unknown Tier-1 fixture "${spec.fixture}"`);
  const el = document.createElement(fixture.tag);
  for (const [name, value] of Object.entries(spec.attrs ?? {})) el.setAttribute(name, value);
  document.body.appendChild(el);
  mounted.push(el);
  // JS-core fixtures render synchronously on connect; honor updateComplete if
  // a future fixture base provides it (Lit), matching the Tier-2 wait shape.
  if (el.updateComplete) await el.updateComplete;
  await Promise.resolve();
  return {
    el,
    tag: fixture.tag,
    shadowRoot: el.shadowRoot,
    win: window,
    waitFor,
    nextEvent,
    // Tier-agnostic settle (§9): Lit re-renders are scheduled — await
    // updateComplete so DOM assertions see the committed state.
    settle: async () => {
      if (el.updateComplete) await el.updateComplete;
      await Promise.resolve();
    },
  };
}

/** afterEach cleanup — remove mounted elements and any Hologram stub. */
export function cleanup() {
  while (mounted.length) mounted.pop().remove();
  delete window.Hologram;
}

// Cases whose behavior + Tier-1 fixture are wired today. A case outside this
// set is adapter-pending on Tier 1 (its fixture lands with a feature brief).
const SUPPORTED = new Set([
  "C-01", "C-03", "C-04", "C-05", "C-06", "C-07", "C-10",
  "T-01", "T-02", "T-04", "T-05", "T-06", "T-07", "T-08", "T-09",
  "D-01", "D-02", "D-06",
  "S-01", "S-02", "S-03", "S-04", "S-05", "S-06",
  "SD-01", "SD-02", "SD-03",
  "E-01", "E-02", "E-03",
  "X-01", "X-03", "X-04", "X-05", "X-06", "X-07", "X-08", "X-09", "X-10",
  "X-11", "X-14", "X-15", "X-17", "X-18", "X-20",
]);

/**
 * Register the WTR describe/it blocks for a lane of cases. Shared by the two
 * lane entry files (full + fast) so there is ONE execution path and no
 * browser-side process.env reads. Pending cases (registry-level or
 * adapter-level) are skipped — never green.
 * @param {Array} cases
 * @param {string} laneName
 */
export function runConformance(cases, laneName) {
  describe("conformance registry integrity", () => {
    it("aggregates every family with unique ids and honest pending accounting", () => {
      const t = tally();
      expect(t.total).to.equal(CASES.length);
      expect(t.implemented + t.pending).to.equal(t.total);
      expect(t.implemented, "scaffold ships representative implemented cases").to.be.greaterThan(0);
      expect(t.pending, "scaffold honestly marks unimplemented features pending").to.be.greaterThan(0);
      expect(new Set(CASES.map((k) => k.id)).size).to.equal(CASES.length);
    });
  });

  describe(`conformance — Tier 1 (WTR, ${laneName} lane)`, () => {
    before(() => {
      defineFixtures();
    });

    afterEach(() => {
      cleanup();
    });

    for (const k of cases) {
      it(`${k.id} — ${k.title}`, async function () {
        if (k.status === "pending") this.skip(); // unimplemented / accepted-as-gap
        if (!SUPPORTED.has(k.id)) this.skip(); // Tier-1 fixture not wired yet
        await k.run(mount, expect);
      });
    }

    after(() => {
      const t = tally();
      const supported = CASES.filter((k) => k.status === "implemented" && SUPPORTED.has(k.id)).length;
      console.info(
        `[conformance tier1] registry: ${t.total} cases (${t.implemented} implemented, ${t.pending} pending); ` +
          `tier1-supported: ${supported}; ${laneName} lane: ${cases.length} cases`,
      );
    });
  });
}