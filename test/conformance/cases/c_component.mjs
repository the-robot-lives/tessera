// Family C — Component model (lit-parity §4.1, C-01…C-15).
//
// Implemented representatives run against the adapter's "counter" and "props"
// fixtures (see README.md). The "props" fixture is Tier-1-only today (a
// contract-driven TesseraElement); Tier-2 reports those cases adapter-pending
// until its props fixture lands. Lifecycle C-13/C-14 ride the "lifecycle"
// fixture (Tier 2: tsr-holo-lifecycle, brief 3c); reflection / same-value
// cases stay pending on brief 1c.

import {defineCase, pendingCase} from "../support/case.mjs";
import {clickCy, textCy} from "../support/dom.mjs";

export const cases = [
  defineCase({
    id: "C-01",
    family: "C",
    fast: true,
    title: "element registration — customElements.get(tag) returns the class",
    async run(mount, expect) {
      const h = await mount({fixture: "counter"});
      const ctor = h.win.customElements.get(h.tag);
      expect(ctor, "tag is registered").to.be.a("function");
      expect(h.el).to.be.instanceOf(ctor);
    },
  }),

  pendingCase({
    id: "C-02",
    family: "C",
    fast: true,
    title: "property → attribute reflection",
    reason: "reflect:true property option lands with brief 1c (Tier 1) / 3d (Tier 2)",
  }),

  defineCase({
    id: "C-03",
    family: "C",
    fast: true,
    title: "attribute → property coercion (string + integer)",
    async run(mount, expect) {
      const h = await mount({fixture: "props", attrs: {"display-name": "Ada", count: "42"}});
      expect(h.el.displayName).to.equal("Ada");
      expect(h.el.count).to.equal(42);
    },
  }),

  defineCase({
    id: "C-04",
    family: "C",
    fast: true,
    title: "boolean attribute rides by presence/absence",
    async run(mount, expect) {
      const h = await mount({fixture: "props", attrs: {active: ""}});
      expect(h.el.active).to.equal(true);
      h.el.removeAttribute("active");
      expect(h.el.active).to.equal(false);
      h.el.setAttribute("active", "");
      expect(h.el.active).to.equal(true);
    },
  }),

  defineCase({
    id: "C-05",
    family: "C",
    fast: true,
    title: "number attribute coerces to a number (integer + float)",
    async run(mount, expect) {
      const h = await mount({fixture: "props", attrs: {count: "42", ratio: "1.5"}});
      expect(h.el.count).to.equal(42);
      expect(h.el.ratio).to.equal(1.5);
    },
  }),

  defineCase({
    id: "C-06",
    family: "C",
    fast: true,
    title: "object property parsed from JSON (tsr-props)",
    async run(mount, expect) {
      // tessera's object-property mechanism is the tsr-props JSON attribute
      // (CONTRACT §1/§4) — the analogue of @property({type: Object}).
      const h = await mount({fixture: "props", attrs: {"tsr-props": JSON.stringify({tagList: ["a", "b"]})}});
      expect(h.el.tagList).to.deep.equal(["a", "b"]);
    },
  }),

  defineCase({
    id: "C-07",
    family: "C",
    fast: true,
    title: "@state internal-state reactivity re-renders",
    async run(mount, expect) {
      // Compiled-DSL "state" fixture: an action returns the next state and the
      // element re-renders {@count} reactively (no manual DOM write).
      const h = await mount({fixture: "state"});
      expect(textCy(h, "conf-state-count")).to.equal("0");
      clickCy(h, "conf-state-inc");
      await h.waitFor(() => textCy(h, "conf-state-count") === "1");
      clickCy(h, "conf-state-inc");
      await h.waitFor(() => textCy(h, "conf-state-count") === "2");
      expect(textCy(h, "conf-state-count")).to.equal("2");
    },
  }),

  pendingCase({
    id: "C-08",
    family: "C",
    fast: false,
    title: "no re-render on same value (hasChanged default)",
    reason: "hasChanged default semantics land with brief 1c",
  }),

  pendingCase({
    id: "C-09",
    family: "C",
    fast: true,
    title: "property reflection updates the HTML attribute (reflect:true)",
    reason: "reflect:true lands with brief 1c (Tier 1) / 3d (Tier 2)",
  }),

  defineCase({
    id: "C-10",
    family: "C",
    fast: true,
    title: "custom attribute name maps to a different property key",
    async run(mount, expect) {
      const h = await mount({fixture: "props", attrs: {"display-name": "Grace"}});
      // attribute "display-name" → property "displayName" (name ≠ key)
      expect(h.el.displayName).to.equal("Grace");
      expect(h.el["display-name"]).to.equal(undefined);
    },
  }),

  pendingCase({
    id: "C-11",
    family: "C",
    fast: true,
    title: "connectedCallback fires on insert",
    reason: "needs a lifecycle-observable fixture (behaviors connect probe); owed by 1c/3c harness",
  }),

  pendingCase({
    id: "C-12",
    family: "C",
    fast: true,
    title: "disconnectedCallback fires on remove",
    reason: "needs a lifecycle-observable fixture (behaviors cleanup probe); owed by 1c/3c harness",
  }),

  defineCase({
    id: "C-13",
    family: "C",
    fast: true,
    title: "firstUpdated fires once after first render",
    async run(mount, expect) {
      // Lifecycle fixture records {hook, changed, domText} per render (see
      // lc_lifecycle.mjs for the shared recording surface).
      const h = await mount({fixture: "lifecycle"});
      await h.waitFor(() => (h.el.tesseraLifecycleLog ?? []).some((e) => e.hook === "firstUpdated"));
      // A second interaction must NOT fire firstUpdated again.
      clickCy(h, "holo-counter-inc");
      await h.el.updateComplete;
      await h.settle();
      const log = h.el.tesseraLifecycleLog;
      const firsts = log.filter((e) => e.hook === "firstUpdated");
      expect(firsts.length, "firstUpdated fires exactly once").to.equal(1);
      const wills = log.map((e) => e.hook).indexOf("willUpdate");
      const firstIdx = log.map((e) => e.hook).indexOf("firstUpdated");
      expect(firstIdx, "willUpdate precedes firstUpdated").to.be.above(wills);
      expect(h.shadowRoot.querySelector('[data-cy="holo-counter-root"]'), "first render committed").to.exist;
      expect(firsts[0].domText, "firstUpdated sees the patched first-render DOM").to.equal("0");
    },
  }),

  defineCase({
    id: "C-14",
    family: "C",
    fast: true,
    title: "updateComplete resolves after the DOM updates",
    async run(mount, expect) {
      // The #220 Lit-test pattern: mutate, await el.updateComplete, assert DOM —
      // no waitFor polling. Tier 2 (3c): updateComplete is the render-commit
      // fence; async-stage renders need `await dispatchAction(...)` first.
      const h = await mount({fixture: "lifecycle"});
      await h.settle();
      expect(textCy(h, "holo-counter-count")).to.equal("0");
      clickCy(h, "holo-counter-inc");
      await h.el.updateComplete;
      expect(textCy(h, "holo-counter-count"), "count after awaited update").to.equal("1");
      h.el.setProps({label: "Renamed"});
      await h.el.updateComplete;
      expect(textCy(h, "holo-counter-label"), "label after awaited setProps").to.equal("Renamed");
    },
  }),

  pendingCase({
    id: "C-15",
    family: "C",
    fast: false,
    title: "shouldUpdate returning false skips re-render",
    reason: "should_update DSL opt lands with brief 1c",
  }),
];