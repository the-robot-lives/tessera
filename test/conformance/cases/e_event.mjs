// Family E — Events (lit-parity §4.1, E-01…E-03).
//
// All three run against the shared "counter" fixture, whose `count-changed`
// emission is composed + bubbling with camelCase detail on BOTH tiers
// (Tier 1: priv/js/src/events.mjs emit(); Tier 2: the Hologram-in-element
// runtime re-dispatches component emits as composed, bubbling CustomEvents).

import {defineCase} from "../support/case.mjs";
import {clickCy} from "../support/dom.mjs";

export const cases = [
  defineCase({
    id: "E-01",
    family: "E",
    fast: true,
    title: "CustomEvent dispatch carries camelCase detail",
    async run(mount, expect) {
      const h = await mount({fixture: "counter", attrs: {step: "1"}});
      const detail = h.nextEvent("count-changed");
      clickCy(h, "holo-counter-inc");
      const got = await detail;
      expect(got).to.deep.equal({count: 1, delta: 1});
    },
  }),

  defineCase({
    id: "E-02",
    family: "E",
    fast: true,
    title: "bubbles:true — a parent listener receives the event",
    async run(mount, expect) {
      const h = await mount({fixture: "counter", attrs: {step: "1"}});
      const detail = h.nextEvent("count-changed", h.el.parentNode);
      clickCy(h, "holo-counter-inc");
      const got = await detail;
      expect(got.count).to.equal(1);
    },
  }),

  defineCase({
    id: "E-03",
    family: "E",
    fast: true,
    title: "composed:true — the event crosses the shadow boundary",
    async run(mount, expect) {
      const h = await mount({fixture: "counter", attrs: {step: "1"}});
      // document is OUTSIDE the element's shadow tree; only a composed event
      // reaches this listener.
      const detail = h.nextEvent("count-changed", h.win.document);
      clickCy(h, "holo-counter-inc");
      const got = await detail;
      expect(got.delta).to.equal(1);
    },
  }),
];