// Family X — Extension contract (EXTENSION-CONTRACT.md §9, X-01…X-21).
//
// One spec, two engines: these pin the extension surface both tiers MUST
// implement identically (§9 runtime equivalence — "a surface test that
// cannot pass identically on both tiers is a bug in this document"). The
// state/action family (X-05…X-11, X-20) runs ONE tier-agnostic body set on
// BOTH adapters: bodies use only the mount-handle contract (`el.state`,
// `settle()`, `waitFor`, `nextEvent`) and NEVER a tier-specific affordance
// (no `el.updateComplete`, no Lit class-field reads like `el.count`, no
// declaration-order assumptions on snapshot keys — §6.2 does not mandate
// key order, so key arrays are compared sorted). Both tiers mount the same
// LOGICAL fixture "pipeline" (Tier 1 `<tsr-conf-pipeline>`, Tier 2 the
// HoloKit mirror `<tsr-holo-pipeline-probe>` — same state keys, same action
// semantics, same `internal:` annotation). X-01/X-04/X-18 pin scaffold
// representatives; X-15 is Tier-1-only by nature (generated manifest maps).
// Everything else lands with the extension briefs (2a–2f Tier 1, 3f Tier 2)
// and is pending — never green for an unimplemented feature. X-21 is
// explicitly [PENDING TIER-1] in §9.

import {defineCase, pendingCase} from "../support/case.mjs";
import {clickCy} from "../support/dom.mjs";
import manifests from "../../../js/test/fixtures/conformance/conformance_manifests.generated.mjs";

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
      // Compiled-DSL "pipeline" fixture: state count / selected_id / meta.
      const h = await mount({fixture: "pipeline"});
      const s1 = h.el.state;
      // canonical camel keys, enumerable (§6.2 does NOT mandate key ORDER —
      // Tier-1 inserts in declaration order, Tier-2 in Hologram term order,
      // so compare sorted; aliases never surface in Object.keys)
      expect(Object.keys(s1).slice().sort()).to.deep.equal(["count", "meta", "selectedId"]);
      expect(s1.selectedId).to.equal("none");
      // frozen top level — NOT deep (nested meta is shared by reference)
      expect(Object.isFrozen(s1)).to.equal(true);
      expect(Object.isFrozen(s1.meta)).to.equal(false);
      // snake alias: present, readable, identical, NON-enumerable
      expect(s1.selected_id).to.equal(s1.selectedId);
      expect(Object.getOwnPropertyDescriptor(s1, "selected_id").enumerable).to.equal(false);
      // JSON / spread see camelCase only (D3)
      expect(JSON.parse(JSON.stringify(s1)).selected_id).to.equal(undefined);
      expect(Object.keys({...s1}).slice().sort()).to.deep.equal(["count", "meta", "selectedId"]);
      // fresh object per access; nested values shared
      const s2 = h.el.state;
      expect(s2).to.not.equal(s1);
      expect(s2).to.deep.equal(s1);
      expect(s2.meta).to.equal(s1.meta);
    },
  }),

  defineCase({
    id: "X-06",
    family: "X",
    fast: true,
    title: "tsr-state-change — one event per transition, changed keys, post-state",
    async run(mount, expect) {
      const h = await mount({fixture: "pipeline"});
      const seen = [];
      const listener = (ev) => seen.push(ev.detail);
      h.win.document.addEventListener("tsr-state-change", listener); // composed+bubbling
      try {
        const r = await h.el.dispatchAction("selectItem", {itemName: "alpha"});
        expect(r.ok).to.equal(true);
        // event already scheduled at commit — settle() (mount-contract helper:
        // Tier 1 awaits el.updateComplete, Tier 2 is a tick — render is
        // synchronous at the Tier-2 commit point) sees the NEW DOM
        await h.settle();
        expect(h.shadowRoot.querySelector("[data-cy=conf-pipeline-selected]").textContent).to.equal("alpha");
        expect(h.shadowRoot.querySelector("[data-cy=conf-pipeline-count]").textContent).to.equal("1");
        // one transition changing TWO keys ⇒ exactly ONE event (keys sorted —
        // §6.2 does not mandate key order)
        expect(seen.length).to.equal(1);
        const d = seen[0];
        expect(d.keys.slice().sort()).to.deep.equal(["count", "selectedId"]);
        expect(d.state.selectedId).to.equal("alpha");
        expect(d.state.count).to.equal(1);
        // the dispatched action's snake-canonical name rides along (§6.2)
        expect(d.action).to.equal("select_item");
        // an action that changes nothing still fires one transition event, keys []
        expect((await h.el.dispatchAction("seedCache")).ok).to.equal(true);
        expect(seen.length).to.equal(2);
        expect(seen[1].keys).to.deep.equal([]);
        expect(seen[1].action).to.equal("seed_cache");
      } finally {
        h.win.document.removeEventListener("tsr-state-change", listener);
      }
    },
  }),

  defineCase({
    id: "X-07",
    family: "X",
    fast: true,
    title: "open dispatch — either casing runs; unknown-action ⇒ ok:false + warn",
    async run(mount, expect) {
      const h = await mount({fixture: "pipeline"});
      const warns = [];
      const orig = h.win.console.warn;
      h.win.console.warn = (m) => warns.push(String(m));
      const events = [];
      const listener = (ev) => events.push(ev.detail);
      h.win.document.addEventListener("tsr-state-change", listener);
      try {
        // both casings run (D2 open surface, D3 casing)
        expect((await h.el.dispatchAction("bump")).ok).to.equal(true);
        expect((await h.el.dispatchAction("select_item", {item_name: "snake"})).ok).to.equal(true);
        // select_item changes TWO keys — count is now 1 (bump) + 1 (select)
        expect(h.el.state.count).to.equal(2);
        expect(h.el.state.selectedId).to.equal("snake");
        // unknown action: no throw, ok:false, warn, NO state change, NO event
        const before = events.length;
        const u = await h.el.dispatchAction("nope_not_here");
        expect(u.ok).to.equal(false);
        expect(u.reason).to.equal("unknown-action");
        expect(h.el.state.count).to.equal(2);
        expect(events.length).to.equal(before);
        expect(warns.some((w) => w.includes("nope_not_here"))).to.equal(true);
        // internal action dispatches normally — annotation never restricts (D2)
        expect((await h.el.dispatchAction("seedCache")).ok).to.equal(true);
        // registering against the internal action warns ONCE but STILL WORKS
        let intercepted = 0;
        const off1 = h.el.onAction("seed_cache", (params, next) => {
          intercepted += 1;
          return next();
        });
        h.el.onAction("seed_cache", (params, next) => next()); // second: no repeat warn
        expect((await h.el.dispatchAction("seedCache")).ok).to.equal(true);
        expect(intercepted).to.equal(1);
        const internalWarns = warns.filter((w) => w.includes("internal action"));
        expect(internalWarns.length).to.equal(1);
        off1();
      } finally {
        h.win.console.warn = orig;
        h.win.document.removeEventListener("tsr-state-change", listener);
      }
    },
  }),

  defineCase({
    id: "X-08",
    family: "X",
    fast: true,
    title: "interceptor ordering — first-registered outermost, overrides flow down",
    async run(mount, expect) {
      const h = await mount({fixture: "pipeline"});
      const order = [];
      const seen = [];
      h.el.onAction("bump", (params, next) => {
        order.push("outer");
        seen.push(params);
        return next({step: 2}); // override flows downstream in camelCase
      });
      h.el.onAction("bump", (params, next) => {
        order.push("inner");
        seen.push(params);
        return next();
      });
      const r = await h.el.dispatchAction("bump", {step: 5});
      expect(order).to.deep.equal(["outer", "inner"]);
      expect(seen[0]).to.deep.equal({step: 5}); // camelCase at the boundary (D3)
      expect(seen[1]).to.deep.equal({step: 2}); // downstream sees the override
      expect(r.ok).to.equal(true);
      expect(r.value.count).to.equal(2); // invoke ran with the OVERRIDDEN step
      // template-bound ($click) invocations ride the SAME pipeline (§6.4)
      order.length = 0;
      clickCy(h, "conf-pipeline-inc");
      await h.waitFor(() => order.length === 2);
      expect(order).to.deep.equal(["outer", "inner"]);
      expect(h.el.state.count).to.equal(4); // second bump: step overridden to 2 again
    },
  }),

  defineCase({
    id: "X-09",
    family: "X",
    fast: true,
    title: "veto — no next ⇒ no state change, no events, result returned",
    async run(mount, expect) {
      const h = await mount({fixture: "pipeline"});
      const events = [];
      const listener = (ev) => events.push(ev);
      h.win.document.addEventListener("tsr-state-change", listener);
      const vetoReturn = {blocked: "by-policy"};
      const off = h.el.onAction("bump", () => vetoReturn); // never calls next ⇒ veto
      try {
        const r = await h.el.dispatchAction("bump");
        expect(r.ok).to.equal(false);
        expect(r.reason).to.equal("vetoed");
        expect(r.value).to.equal(vetoReturn); // veto carries the stage's return (U1)
        expect(h.el.state.count).to.equal(0);
        expect(events.length).to.equal(0);
        await h.settle();
        expect(h.shadowRoot.querySelector("[data-cy=conf-pipeline-count]").textContent).to.equal("0");
        // unsubscribe restores the direct path
        off();
        const r2 = await h.el.dispatchAction("bump");
        expect(r2.ok).to.equal(true);
        expect(h.el.state.count).to.equal(1);
      } finally {
        h.win.document.removeEventListener("tsr-state-change", listener);
      }
    },
  }),

  defineCase({
    id: "X-10",
    family: "X",
    fast: false,
    title: "async pipeline — post-disconnect resolution applies nothing",
    async run(mount, expect) {
      const h = await mount({fixture: "pipeline"});
      const preCount = h.el.state.count;
      const events = [];
      const listener = (ev) => events.push(ev);
      h.win.document.addEventListener("tsr-state-change", listener);
      try {
        let release;
        const gate = new Promise((res) => {
          release = res;
        });
        h.el.onAction("bump", async (params, next) => {
          await gate; // holds the pipeline open
          return next();
        });
        const pending = h.el.dispatchAction("bump");
        h.el.remove(); // disconnect WHILE the pipeline is still running
        release();
        const r = await pending;
        // U6 stale-drop: applies nothing, reports the veto convention, NO value
        expect(r.ok).to.equal(false);
        expect(r.reason).to.equal("vetoed");
        expect(r.value).to.equal(undefined);
        // Tier-2's post-destroy snapshot is the §6.2 frozen-EMPTY object (the
        // mount is gone), so the count read degrades to "unchanged" there;
        // Tier 1 still reads the pre-disconnect 0.
        expect(h.el.state.count ?? preCount).to.equal(preCount);
        expect(events.length).to.equal(0);
      } finally {
        h.win.document.removeEventListener("tsr-state-change", listener);
      }
    },
  }),

  defineCase({
    id: "X-11",
    family: "X",
    fast: true,
    title: "error path — throwing stage ⇒ tsr-action-error + ok:false",
    async run(mount, expect) {
      const h = await mount({fixture: "pipeline"});
      const errs = [];
      const listener = (ev) => errs.push(ev.detail);
      h.win.document.addEventListener("tsr-action-error", listener);
      let innerRan = 0;
      h.el.onAction("bump", () => {
        throw new Error("stage exploded"); // throws BEFORE next
      });
      h.el.onAction("bump", (params, next) => {
        innerRan += 1;
        return next();
      });
      try {
        const r = await h.el.dispatchAction("bump");
        expect(r.ok).to.equal(false);
        expect(r.reason).to.equal("error");
        expect(innerRan).to.equal(0); // downstream stages never see the poisoned dispatch
        expect(h.el.state.count).to.equal(0);
        expect(errs.length).to.equal(1);
        expect(errs[0].action).to.equal("bump");
        expect(errs[0].message).to.include("stage exploded");
      } finally {
        h.win.document.removeEventListener("tsr-action-error", listener);
      }
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
  defineCase({
    id: "X-15",
    family: "X",
    fast: true,
    title: "tesseraExtensionApi / manifest extension_api agree (CEM pinned in ExUnit)",
    async run(mount, expect) {
      // §8.3 three-way agreement. The CEM field is Elixir-only output
      // (Codegen.cem/1) — pinned against the SAME spec object in
      // codegen_test.exs; the manifest is the fixture generator's
      // Spec.to_manifest_map/1 output shipped below. This case proves the
      // runtime statics equal the manifest entries for every generated
      // fixture — the third edge of the triangle.
      for (const name of ["pipeline", "state"]) {
        const h = await mount({fixture: name});
        const ctor = h.win.customElements.get(h.tag);
        const m = manifests[h.tag];
        expect(m, `manifest entry for ${h.tag}`).to.be.an("object");
        expect(ctor.tesseraExtensionApi, `${h.tag} extensionApi`).to.equal(m.extension_api);
        expect(ctor.tesseraExtensionApi, `${h.tag} first-stable default`).to.equal("1.0.0");
        // D2 open surface: the static action list equals the manifest list
        // (declaration order — the same spec feeds both).
        expect(ctor.tesseraActions, `${h.tag} actions`).to.deep.equal(m.actions);
      }
      // Major-mismatch pin WARNINGS are a compile-time Elixir property
      // (Extension.check_pin!/3: CompileError on major, IO.warn on minor) —
      // firing is proven in test/noizu/tessera/component/extension_test.exs;
      // the JS lane pin check lands with the bridge briefs (2f/3f).
    },
  }),
  pendingCase({id: "X-16", family: "X", fast: true, title: "Elixir derivation end-to-end — derived tag registers, base untouched", reason: "derivation macro lands with brief 2c / 3f"}),
  defineCase({
    id: "X-17",
    family: "X",
    fast: true,
    title: "region replacement — override renders on derived; unknown region fails",
    async run(mount, expect) {
      // §5.4 regions as compiled-in fragments. Mount-handle contract only —
      // both tiers mount the LOGICAL pair (regionBase, regionVendor).
      const base = await mount({fixture: "regionBase"});
      const baseRow = base.shadowRoot.querySelector("[data-cy=conf-region-row]");
      expect(baseRow).to.not.equal(null);
      // the base's default region body renders through __region_row()
      expect(baseRow.textContent).to.include("base-row");
      expect(base.shadowRoot.querySelector("[data-cy=conf-region-vendor]")).to.equal(null);

      const vendor = await mount({fixture: "regionVendor"});
      const vendorSpan = vendor.shadowRoot.querySelector("[data-cy=conf-region-vendor]");
      expect(vendorSpan, "slot_template :row override renders").to.not.equal(null);
      expect(vendorSpan.classList.contains("vendor-row")).to.equal(true);
      // {%super%} composes the BASE body inside the override (real ES
      // super.__region_row() on the class chain — §5.4)
      expect(vendorSpan.textContent).to.include("base-row");
      // the overridden region still sits inside the inherited host structure
      expect(vendor.shadowRoot.querySelector("[data-cy=conf-region-vendor]").closest("li.row")).to.not.equal(null);
      // the compile-failure half of X-17 (slot_template for an UNKNOWN region
      // must fail the compile, §5.7) is Elixir-only: proven by
      // extension_test.exs "override of an unknown region is a CompileError".
    },
  }),

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
      const h = await mount({fixture: "pipeline"});
      const warns = [];
      const orig = h.win.console.warn;
      h.win.console.warn = (m) => warns.push(String(m));
      try {
        // camel action name + camel params → same Elixir action (its body
        // reads snake params.item_name — the state effect proves conversion)
        const a = await h.el.dispatchAction("selectItem", {itemName: "one"});
        expect(a.ok).to.equal(true);
        expect(h.el.state.selectedId).to.equal("one");
        // snake name + snake params accepted too
        const b = await h.el.dispatchAction("select_item", {item_name: "two"});
        expect(b.ok).to.equal(true);
        expect(h.el.state.selectedId).to.equal("two");
        // interceptor-facing params are camelCase regardless of input casing;
        // mixed keys normalize per key
        let seen;
        h.el.onAction("select_item", (params, next) => {
          seen = params;
          return next();
        });
        const c = await h.el.dispatchAction("selectItem", {item_name: "three"});
        expect(c.ok).to.equal(true);
        expect(seen).to.deep.equal({itemName: "three"});
        expect(h.el.state.selectedId).to.equal("three");
        // onAction accepts either casing for the NAME
        const off = h.el.onAction("seedCache", (params, next) => next());
        expect((await h.el.dispatchAction("seed_cache")).ok).to.equal(true);
        off();
        // untrusted params: `_`-prefixed keys stripped (with a warn);
        // function values REJECTED before any interceptor sees them
        const d = await h.el.dispatchAction("bump", {_secret: 1});
        expect(d.ok).to.equal(true);
        expect(warns.some((w) => w.includes("_secret"))).to.equal(true);
        const errs = [];
        const listener = (ev) => errs.push(ev.detail);
        h.win.document.addEventListener("tsr-action-error", listener);
        const f = await h.el.dispatchAction("bump", {fn: () => {}});
        h.win.document.removeEventListener("tsr-action-error", listener);
        expect(f.ok).to.equal(false);
        expect(f.reason).to.equal("error");
        expect(errs.length).to.equal(1);
        expect(errs[0].message).to.include("function");
      } finally {
        h.win.console.warn = orig;
      }
    },
  }),
  pendingCase({id: "X-21", family: "X", fast: false, title: "JS tag extension — extendElement composes pre-define mixins [PENDING TIER-1]", reason: "extendElement lands with brief 2e; marked [PENDING TIER-1] in EXTENSION-CONTRACT §9"}),
];