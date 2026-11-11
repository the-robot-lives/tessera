// Family LC — Lifecycle hooks (lit-parity §4 extension; brief 1c Tier 1 /
// brief 3c Tier 2: willUpdate / updated / firstUpdated / changedProperties).
//
// SHARED FIXTURE SURFACE the case bodies assert (documented contract for the
// recording fixture on EVERY tier):
//
//   el.tesseraLifecycleLog : Array<{hook, changed, domText}> — one entry per
//     hook invocation, in call order, where
//       hook    = "willUpdate" | "firstUpdated" | "updated"
//       changed = the OLD-values snapshot handed to the hook (plain object,
//                 camelCase props+state keys — lit-parity row #34; firstUpdated
//                 records the same snapshot)
//       domText = the [data-cy="holo-counter-count"] textContent inside the
//                 element's shadow root AT HOOK TIME (null when absent) — this
//                 is what proves willUpdate observed the PRE-patch DOM and
//                 updated/firstUpdated the POST-patch DOM.
//   el.hasUpdated          : boolean, true after the first committed render
//                 (lit-parity row #18).
//
// Tier-2 adapter fixture: tag `tsr-holo-lifecycle` — HoloKit.Components.Counter
// mounted through a recording subclass of TesseraHoloElement (registration in
// demo/hologram_app glue, holo_runtime_glue.js). Tier 1 needs the equivalent
// recording fixture from brief 1c's case-fill wave (the hooks landed; the
// recording element + these bodies' Tier-1 wiring are owed there) — until then
// Tier 1 reports LC-01…LC-04 + C-13 adapter-pending. Never green by accident.
//
// Known Tier-2 divergences (documented, lit-parity §2.1 rows #7/#11/#34):
//   * the FIRST render's willUpdate `changed` carries the props view only —
//     the Hologram state struct is created by renderDom itself, so state keys
//     cannot be observed before it exists;
//   * `changed` is a plain object snapshot, never a live Map;
//   * a hook that throws is caught + warned (the shared Hologram.render loop
//     must survive for every other mounted instance) — Lit propagates.

import {defineCase} from "../support/case.mjs";
import {clickCy} from "../support/dom.mjs";

const logOf = (el) => el.tesseraLifecycleLog || [];
const entries = (el, hook) => logOf(el).filter((e) => e.hook === hook);
const last = (list) => list[list.length - 1];

export const cases = [
  defineCase({
    id: "LC-01",
    family: "LC",
    fast: true,
    title: "willUpdate runs before render with changed old-values",
    async run(mount, expect) {
      const h = await mount({fixture: "lifecycle"});
      await h.waitFor(() => entries(h.el, "updated").length >= 1); // first render committed

      clickCy(h, "holo-counter-inc");
      await h.settle();

      const wills = entries(h.el, "willUpdate");
      expect(wills.length, "one willUpdate per render").to.be.at.least(2);
      const second = wills[1];
      expect(second.domText, "willUpdate saw the PRE-patch DOM").to.equal("0");
      expect(second.changed.count, "changed carries the OLD value").to.equal(0);

      const upds = entries(h.el, "updated");
      expect(last(upds).domText, "updated saw the POST-patch DOM").to.equal("1");
      expect(
        logOf(h.el).indexOf(second),
        "willUpdate precedes the updated of the same cycle",
      ).to.be.lessThan(logOf(h.el).indexOf(last(upds)));
    },
  }),

  defineCase({
    id: "LC-02",
    family: "LC",
    fast: true,
    title: "updated runs after each render",
    async run(mount, expect) {
      const h = await mount({fixture: "lifecycle"});
      await h.waitFor(() => entries(h.el, "updated").length >= 1);
      clickCy(h, "holo-counter-inc");
      await h.settle();
      clickCy(h, "holo-counter-inc");
      await h.settle();
      await h.waitFor(() => entries(h.el, "updated").length >= 3);

      const upds = entries(h.el, "updated");
      expect(upds.length, "one updated per render (mount + 2 clicks)").to.equal(3);
      expect(entries(h.el, "willUpdate").length, "one willUpdate per render too").to.equal(3);
      expect(upds.map((e) => e.domText), "DOM seen by each updated").to.deep.equal(["0", "1", "2"]);
    },
  }),

  defineCase({
    id: "LC-03",
    family: "LC",
    fast: true,
    title: "firstUpdated fires exactly once",
    async run(mount, expect) {
      const h = await mount({fixture: "lifecycle"});
      await h.waitFor(() => entries(h.el, "firstUpdated").length >= 1);
      clickCy(h, "holo-counter-inc");
      await h.settle();
      clickCy(h, "holo-counter-dec");
      await h.settle();
      await h.waitFor(() => entries(h.el, "updated").length >= 3);

      expect(entries(h.el, "firstUpdated").length, "firstUpdated fires exactly once").to.equal(1);
      const order = logOf(h.el);
      expect(order[0].hook, "first render order — willUpdate").to.equal("willUpdate");
      expect(order[1].hook, "first render order — firstUpdated").to.equal("firstUpdated");
      expect(order[2].hook, "first render order — updated").to.equal("updated");
      expect(order[1].domText, "rendered DOM is available at firstUpdated").to.equal("0");
      expect(h.el.hasUpdated, "hasUpdated latches after the first committed render").to.equal(true);
    },
  }),

  defineCase({
    id: "LC-04",
    family: "LC",
    fast: true,
    title: "changedProperties carries old values",
    async run(mount, expect) {
      const h = await mount({fixture: "lifecycle"});
      await h.waitFor(() => entries(h.el, "updated").length >= 1);
      clickCy(h, "holo-counter-inc");
      await h.settle();
      clickCy(h, "holo-counter-inc");
      await h.settle();
      await h.waitFor(() => entries(h.el, "updated").length >= 3);

      const wills = entries(h.el, "willUpdate");
      expect(wills[1].changed.count, "old value at willUpdate #2").to.equal(0);
      expect(wills[2].changed.count, "old value at willUpdate #3").to.equal(1);
      expect(last(entries(h.el, "updated")).changed.count, "old value at updated #3").to.equal(1);

      const changed = wills[1].changed;
      expect(Object.keys(changed), "plain object keyed by the changed names").to.include("count");
      expect(changed.get, "NOT a live Map — plain old-value snapshot").to.be.undefined;
    },
  }),
];
