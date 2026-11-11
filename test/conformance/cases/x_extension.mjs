// Family X — Extension contract (EXTENSION-CONTRACT.md §9, X-01…X-21).
//
// One spec, two engines: these pin the extension surface both tiers MUST
// implement identically. The scaffold implements the representatives whose
// behavior is on develop today (X-01 registration identity, X-04 bridge
// snake_case params, X-18 tsr-props key guards) plus the state/action family
// (X-03, X-05…X-11, X-20 — brief 3d: Tier-2 wired on the HoloKit state probe;
// the Tier-1 adapter gates them until brief 2a extends its `state` fixture).
// The rest land with the extension briefs (2a–2f Tier 1, 3f Tier 2) and are
// pending — never green for an unimplemented feature. X-21 is explicitly
// [PENDING TIER-1] in §9.

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
  defineCase({
    id: "X-03",
    family: "X",
    fast: true,
    title: "contract events dispatch composed+bubbling CustomEvents, camelCase detail",
    async run(mount, expect) {
      // Compiled-DSL "state" fixture declares conf-state-ping (detail count /
      // delta); the action emits it through @noizu/tessera-core's emit().
      const h = await mount({fixture: "state"});
      // document is OUTSIDE the shadow tree — only a composed event reaches it.
      const detail = h.nextEvent("conf-state-ping", h.win.document);
      clickCy(h, "conf-state-inc");
      const got = await detail;
      expect(got).to.deep.equal({count: 1, delta: 1});
    },
  }),

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

  defineCase({
    id: "X-05",
    family: "X",
    fast: true,
    title: "el.state canonical camelCase frozen snapshot + snake aliases",
    async run(mount, expect) {
      const h = await mount({fixture: "state"});
      const s = h.el.state;

      // canonical camelCase keys = CONTRACT §1 transform of the declared
      // state keys (selected_id/item_count → selectedId/itemCount);
      // `_`-prefixed internals (the $h bridge slot) never surface.
      expect(Object.keys(s).slice().sort()).to.deep.equal(["count", "itemCount", "selectedId", "step"]);
      expect(s.count).to.equal(0);
      expect(s.selectedId).to.equal("none");

      // snake_case READS work as aliases with identical values…
      expect(s.selected_id).to.equal(s.selectedId);
      expect(s.item_count).to.equal(s.itemCount);

      // …but are NON-ENUMERABLE: keys / JSON / spread expose camelCase only.
      expect(Object.keys(s)).to.not.include("selected_id");
      expect(JSON.stringify(s)).to.not.contain("selected_id");
      expect(Object.keys({...s})).to.not.include("selected_id");

      // frozen top-level; fresh snapshot per access (not identity-stable).
      expect(Object.isFrozen(s)).to.equal(true);
      try {
        s.count = 99;
      } catch (_err) {
        /* strict-mode assignment to frozen throws — both are "no write" */
      }
      expect(s.count).to.equal(0);
      expect(h.el.state).to.not.equal(s);
      expect(h.el.state).to.eql(s);
    },
  }),
  defineCase({
    id: "X-06",
    family: "X",
    fast: true,
    title: "tsr-state-change — one event per transition, changed keys, post-state",
    async run(mount, expect) {
      const h = await mount({fixture: "state"});
      const events = [];
      h.el.addEventListener("tsr-state-change", (e) => events.push(e));

      // one action changing TWO keys ⇒ ONE event with exactly those keys
      const r = await h.el.dispatchAction("select_item", {selectedId: "alpha"});
      expect(r.ok).to.equal(true);

      await h.waitFor(() => events.length === 1);
      const ev = events[0];
      expect(ev.detail.keys.slice().sort()).to.deep.equal(["itemCount", "selectedId"]);
      // state in the detail is the POST-transition snapshot
      expect(ev.detail.state.selectedId).to.equal("alpha");
      expect(ev.detail.state.itemCount).to.equal(1);
      expect(ev.detail.state).to.eql(h.el.state);
      // composed + bubbling CustomEvent on the element
      expect(ev.bubbles).to.equal(true);
      expect(ev.composed).to.equal(true);
      expect(ev.target).to.equal(h.el);

      // a non-transitioning no-op dispatch (same selection) still runs but
      // changes only item_count — exactly the changed key, never stale keys
      await h.el.dispatchAction("select_item", {selectedId: "alpha"});
      await h.waitFor(() => events.length === 2);
      expect(events[1].detail.keys).to.deep.equal(["itemCount"]);
    },
  }),
  defineCase({
    id: "X-07",
    family: "X",
    fast: true,
    title: "open dispatch — either casing runs; unknown-action ⇒ ok:false + warn",
    async run(mount, expect) {
      const h = await mount({fixture: "state"});
      const stateEvents = [];
      h.el.addEventListener("tsr-state-change", (e) => stateEvents.push(e));

      // declared actions are all invokable, param keys in either casing (D2)
      const r1 = await h.el.dispatchAction("bump", {delta: 2});
      expect(r1.ok).to.equal(true);
      // U1: value = the post-transition snapshot
      expect(r1.value).to.not.equal(undefined);
      expect(r1.value.count).to.equal(2);

      // UNKNOWN name: {ok:false, reason:"unknown-action"} + dev warn, no
      // state change, NO event, no throw (§6.3).
      const before = h.el.state;
      const warns = [];
      const orig = h.win.console.warn;
      h.win.console.warn = (m) => warns.push(String(m));
      let r2;
      try {
        r2 = await h.el.dispatchAction("no_such_action_at_all");
      } finally {
        h.win.console.warn = orig;
      }

      expect(r2.ok).to.equal(false);
      expect(r2.reason).to.equal("unknown-action");
      expect(warns.some((w) => w.includes("no_such_action_at_all"))).to.equal(true);
      expect(h.el.state.count).to.equal(before.count);
      expect(stateEvents).to.have.length(1); // only the earlier committed bump
    },
  }),
  defineCase({
    id: "X-08",
    family: "X",
    fast: true,
    title: "interceptor ordering — first-registered outermost, overrides flow down",
    async run(mount, expect) {
      const h = await mount({fixture: "state"});
      const order = [];

      // onion order (D3): FIRST-registered runs OUTERMOST
      h.el.onAction("select_item", (params, next) => {
        order.push(`outer:${params.selectedId}`);
        return next({...params, selected_id: "outer-forced"}); // override in snake
      });
      h.el.onAction("select_item", (params, next) => {
        order.push(`inner:${params.selectedId}`); // sees the camelCase override
        return next();
      });

      const r = await h.el.dispatchAction("selectItem", {selectedId: "ignored"});
      expect(r.ok).to.equal(true);
      expect(order).to.deep.equal(["outer:ignored", "inner:outer-forced"]);
      expect(h.el.state.selectedId).to.equal("outer-forced");
      expect(h.el.state.itemCount).to.equal(1);
    },
  }),
  defineCase({
    id: "X-09",
    family: "X",
    fast: true,
    title: "veto — no next ⇒ no state change, no events, result returned",
    async run(mount, expect) {
      const h = await mount({fixture: "state"});
      const before = h.el.state.count;
      const stateEvents = [];
      const pings = [];
      const onState = (e) => stateEvents.push(e);
      const onPing = (e) => pings.push(e);
      h.el.addEventListener("tsr-state-change", onState);
      h.win.document.addEventListener("conf-state-ping", onPing);

      const off = h.el.onAction("bump", (_params) => "blocked-by-veto");
      expect(off).to.be.a("function");

      const r = await h.el.dispatchAction("bump", {delta: 5});
      expect(r.ok).to.equal(false);
      expect(r.reason).to.equal("vetoed");
      // no state change, no tsr-state-change, no contract event (§6.4)
      expect(h.el.state.count).to.equal(before);
      expect(stateEvents).to.have.length(0);
      expect(pings).to.have.length(0);

      // unsubscribe — the action runs again downstream of nothing
      off();
      const r2 = await h.el.dispatchAction("bump", {delta: 5});
      expect(r2.ok).to.equal(true);
      expect(h.el.state.count).to.equal(before + 5);
      expect(stateEvents).to.have.length(1);
      // contract emits are scheduled via Hologram.scheduleAction (a timer
      // macrotask), so the ping lands after the sync commit — poll for it.
      await h.waitFor(() => pings.length === 1);

      h.el.removeEventListener("tsr-state-change", onState);
      h.win.document.removeEventListener("conf-state-ping", onPing);
    },
  }),
  defineCase({
    id: "X-10",
    family: "X",
    fast: false,
    title: "async pipeline — Promise chaining; post-disconnect resolution applies nothing",
    async run(mount, expect) {
      const h = await mount({fixture: "state"});
      const before = h.el.state.count;

      // async stage while connected: the Promise chains, commit lands on it
      h.el.onAction("bump", (params, next) =>
        new Promise((resolve) => h.win.setTimeout(() => resolve(next()), 20)),
      );
      const r = await h.el.dispatchAction("bump", {delta: 1});
      expect(r.ok).to.equal(true);
      expect(h.el.state.count).to.equal(before + 1);

      // stale-resolution drop (§6.4): the stage resolves AFTER disconnect —
      // no state application, no emit, reported as vetoed (U6)
      h.el.onAction("select_item", (params, next) =>
        new Promise((resolve) => h.win.setTimeout(() => resolve(next()), 60)),
      );
      const pending = h.el.dispatchAction("select_item", {selectedId: "late"});
      h.el.remove(); // disconnect mid-flight (cleanup tears the mount down)

      const r2 = await pending;
      expect(r2.ok).to.equal(false);
      expect(r2.reason).to.equal("vetoed");
    },
  }),
  defineCase({
    id: "X-11",
    family: "X",
    fast: true,
    title: "error path — throwing stage ⇒ tsr-action-error + ok:false",
    async run(mount, expect) {
      const h = await mount({fixture: "state"});
      const before = h.el.state.count;
      const errors = [];
      h.el.addEventListener("tsr-action-error", (e) => errors.push(e.detail));

      let downstreamRan = 0;
      h.el.onAction("bump", () => {
        throw new Error("boom-outer-stage");
      });
      h.el.onAction("bump", (params, next) => {
        downstreamRan += 1;
        return next();
      });

      const r = await h.el.dispatchAction("bump", {delta: 3});
      expect(r.ok).to.equal(false);
      expect(r.reason).to.equal("error");
      // downstream skipped, no state change, no transition event
      expect(downstreamRan).to.equal(0);
      expect(h.el.state.count).to.equal(before);
      // tsr-action-error: composed+bubbling, {action, message, error?} (§6.4)
      expect(errors).to.have.length(1);
      expect(errors[0].action).to.equal("bump");
      expect(errors[0].message).to.contain("boom-outer-stage");
    },
  }),
  pendingCase({id: "X-12", family: "X", fast: true, title: "behaviors — add/connect/cleanup, throw isolation, remove, unsubscribe", reason: "behaviors conformance fixture owed (2f); core pinned by js/test/element.test.mjs"}),
  pendingCase({id: "X-13", family: "X", fast: false, title: "subclass hooks — allowed set super-chains; reserved members enforced", reason: "subclass hooks land with brief 2e / 3f"}),
  defineCase({
    id: "X-14",
    family: "X",
    fast: true,
    title: "theming — declared parts exist; custom properties resolve with fallbacks",
    async run(mount, expect) {
      const h = await mount({fixture: "styles"});
      // The host exposes a root part (connectedCallback); the template declares
      // row + accent parts.
      expect(h.el.getAttribute("part")).to.equal("root");
      expect(h.shadowRoot.querySelector("[part=row]")).to.not.equal(null);
      expect(h.shadowRoot.querySelector("[part=accent]")).to.not.equal(null);
      // A declared tag-scoped custom property resolves via its fallback.
      const accent = h.shadowRoot.querySelector("[data-cy=conf-styles-accent]");
      expect(h.win.getComputedStyle(accent).color).to.equal("rgb(102, 204, 255)");
    },
  }),
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
  defineCase({
    id: "X-20",
    family: "X",
    fast: true,
    title: "case normalization end-to-end (D3) — camel/snake both accepted",
    async run(mount, expect) {
      const h = await mount({fixture: "state"});
      let seen;
      h.el.onAction("select_item", (params, next) => {
        seen = Object.keys(params).slice().sort();
        return next(); // pass through; records the casing it received
      });

      // camelCase ACTION name + snake param key ⇒ runs identically…
      const a = await h.el.dispatchAction("selectItem", {selected_id: "via-camel"});
      expect(a.ok).to.equal(true);
      expect(h.el.state.selectedId).to.equal("via-camel");
      // …and interceptors always receive camelCase params (D3)
      expect(seen).to.deep.equal(["selectedId"]);

      // snake action name + camelCase param key ⇒ the same transition
      const b = await h.el.dispatchAction("select_item", {selectedId: "via-snake"});
      expect(b.ok).to.equal(true);
      expect(h.el.state.selectedId).to.equal("via-snake");
      expect(h.el.state.itemCount).to.equal(2);

      // single-word names are casing-invariant; camel param flows down
      const c = await h.el.dispatchAction("bump", {delta: 1});
      expect(c.ok).to.equal(true);
      expect(c.value.count).to.equal(1);
    },
  }),
  pendingCase({id: "X-21", family: "X", fast: false, title: "JS tag extension — extendElement composes pre-define mixins [PENDING TIER-1]", reason: "extendElement lands with brief 2e; marked [PENDING TIER-1] in EXTENSION-CONTRACT §9"}),
];