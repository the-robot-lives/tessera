// Family X — Extension contract (EXTENSION-CONTRACT.md §9, X-01…X-21).
//
// One spec, two engines: these pin the extension surface both tiers MUST
// implement identically. The scaffold implements the representatives whose
// behavior is on develop today (X-01 registration identity, X-04 bridge
// snake_case params, X-18 tsr-props key guards). The rest land with the
// extension briefs (2a–2f Tier 1, 3d/3f Tier 2) and are pending — never green
// for an unimplemented feature. X-21 is explicitly [PENDING TIER-1] in §9.

import {defineCase, pendingCase} from "../support/case.mjs";
import {clickCy} from "../support/dom.mjs";

export const cases = [
  defineCase({
    id: "X-01",
    family: "X",
    fast: true,
    title: "registration identity — mixed class owns the tag, observes tsr-props",
    async run(mount, expect) {
      const h = await mount({fixture: "counter"});
      const ctor = h.win.customElements.get(h.tag);
      expect(ctor).to.be.a("function");
      expect(h.el).to.be.instanceOf(ctor);
      // both runtimes observe the tsr-props JSON attribute (CONTRACT §1/§4)
      expect(ctor.observedAttributes).to.include("tsr-props");
      // defineOnce dedupe across module copies is pinned by js/test/define.test.mjs
      // and the FULL-lane element.copies/bridge.copies suites.
    },
  }),

  pendingCase({id: "X-02", family: "X", fast: false, title: "runtime attrs/props/events/slots match the generated contract exactly", reason: "full contract-surface fixture owed (2a/2b)"}),
  pendingCase({id: "X-03", family: "X", fast: true, title: "contract events dispatch composed+bubbling CustomEvents, camelCase detail", reason: "contract-declared event fixture owed (2a); E-family pins the emit boundary"}),

  defineCase({
    id: "X-04",
    family: "X",
    fast: true,
    title: "bridge maps data-tsr-on → action with deep snake_case params",
    async run(mount, expect) {
      const h = await mount({fixture: "events", attrs: {"data-tsr-on": "conf-select:chose@page"}});
      const calls = [];
      h.win.Hologram = {dispatchAction: (action, target, params) => calls.push({action, target, params})};
      clickCy(h, "conf-select-btn");
      await h.waitFor(() => calls.length > 0);
      expect(calls[0].action).to.equal("chose");
      expect(calls[0].target).to.equal("page");
      // camelCase detail keys converted recursively to snake_case at the boundary
      expect(calls[0].params).to.deep.equal({persona_id: "p1", nested: {max_score: 9}});
    },
  }),

  pendingCase({id: "X-05", family: "X", fast: true, title: "el.state canonical camelCase frozen snapshot + snake aliases", reason: "el.state lands with brief 2a (Tier 1) / 3d (Tier 2)"}),
  pendingCase({id: "X-06", family: "X", fast: true, title: "tsr-state-change — one event per transition, changed keys, post-state", reason: "tsr-state-change lands with brief 2a / 3d"}),
  pendingCase({id: "X-07", family: "X", fast: true, title: "open dispatch — either casing runs; unknown-action ⇒ ok:false + warn", reason: "dispatchAction/onAction land with brief 2a / 3d"}),
  pendingCase({id: "X-08", family: "X", fast: true, title: "interceptor ordering — first-registered outermost, overrides flow down", reason: "interceptor pipeline lands with brief 2a"}),
  pendingCase({id: "X-09", family: "X", fast: true, title: "veto — no next ⇒ no state change, no events, result returned", reason: "interceptor veto lands with brief 2a"}),
  pendingCase({id: "X-10", family: "X", fast: false, title: "async pipeline — post-disconnect resolution applies nothing", reason: "async interceptor pipeline lands with brief 2a"}),
  pendingCase({id: "X-11", family: "X", fast: true, title: "error path — throwing stage ⇒ tsr-action-error + ok:false", reason: "action error path lands with brief 2a"}),
  pendingCase({id: "X-12", family: "X", fast: true, title: "behaviors — add/connect/cleanup, throw isolation, remove, unsubscribe", reason: "behaviors conformance fixture owed (2f); core pinned by js/test/element.test.mjs"}),
  pendingCase({id: "X-13", family: "X", fast: false, title: "subclass hooks — allowed set super-chains; reserved members enforced", reason: "subclass hooks land with brief 2e / 3f"}),
  pendingCase({id: "X-14", family: "X", fast: true, title: "theming — declared parts exist; custom properties resolve with fallbacks", reason: "theming contract landed (1b); compiled-element fixture owed"}),
  pendingCase({id: "X-15", family: "X", fast: false, title: "tesseraExtensionApi / manifest / CEM agree; major-mismatch pin warns", reason: "extension_api versioning lands with brief 2b"}),
  pendingCase({id: "X-16", family: "X", fast: true, title: "Elixir derivation end-to-end — derived tag registers, base untouched", reason: "derivation macro lands with brief 2c / 3f"}),
  pendingCase({id: "X-17", family: "X", fast: true, title: "region replacement — override renders on derived; unknown region fails", reason: "template regions land with brief 2d"}),

  defineCase({
    id: "X-18",
    family: "X",
    fast: true,
    title: "tsr-props reserved-key and method-key skip warnings (pinned)",
    async run(mount, expect) {
      const h = await mount({fixture: "props"});
      const warns = [];
      const orig = h.win.console.warn;
      h.win.console.warn = (m) => warns.push(String(m));
      try {
        h.el.setAttribute("tsr-props", JSON.stringify({__tesseraCleanups: null, displayName: "ok"}));
      } finally {
        h.win.console.warn = orig;
      }
      // reserved `_`-prefixed key skipped (internal cleanups not clobbered)
      expect(h.el.__tesseraCleanups).to.not.equal(null);
      // a legitimate key still applies
      expect(h.el.displayName).to.equal("ok");
      expect(warns.some((w) => w.includes("reserved"))).to.equal(true);
    },
  }),

  pendingCase({id: "X-19", family: "X", fast: false, title: "tag-extension chain (D1) — inherit, deterministic order, base suite passes", reason: "tag-takeover chain lands with brief 2e"}),
  pendingCase({id: "X-20", family: "X", fast: true, title: "case normalization end-to-end (D3) — camel/snake both accepted", reason: "case normalization lands with brief 2a / 3d"}),
  pendingCase({id: "X-21", family: "X", fast: false, title: "JS tag extension — extendElement composes pre-define mixins [PENDING TIER-1]", reason: "extendElement lands with brief 2e; marked [PENDING TIER-1] in EXTENSION-CONTRACT §9"}),
];