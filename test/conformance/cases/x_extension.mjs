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
// representatives; X-15 is Tier-1-only by nature (generated manifest maps);
// X-19 (tag-takeover chain) + X-21 (extendElement registry) landed with
// brief 2e — X-19 gates "the base tag's conformance suite MUST still pass"
// by REPLAYING the pipeline case bodies verbatim on the taken-over fixture,
// X-21 (the JS extendElement registry) runs on BOTH tiers: Tier 2 wires a
// glue fixture since TESSER-004. X-02 (contract-surface agreement: attrs, props, events, slots)
// and X-13 (§6.6 subclass hooks) close the registry after brief 3f -
// tier-agnostic bodies over the shared logical fixtures; their per-tier
// SUPPORTED sets are the adapters' honest accounting - never green for an
// unimplemented feature or an unwired fixture.

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

  defineCase({
    id: "X-02",
    family: "X",
    fast: false,
    title: "runtime attrs/props/events/slots match the generated contract exactly",
    run: contractSurfaceBody,
  }),
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
    run: stateSnapshotBody,
  }),

  defineCase({
    id: "X-06",
    family: "X",
    fast: true,
    title: "tsr-state-change — one event per transition, changed keys, post-state",
    run: stateChangeBody,
  }),

  defineCase({
    id: "X-07",
    family: "X",
    fast: true,
    title: "open dispatch — either casing runs; unknown-action ⇒ ok:false + warn",
    run: openDispatchBody,
  }),

  defineCase({
    id: "X-08",
    family: "X",
    fast: true,
    title: "interceptor ordering — first-registered outermost, overrides flow down",
    run: interceptorOrderBody,
  }),

  defineCase({
    id: "X-09",
    family: "X",
    fast: true,
    title: "veto — no next ⇒ no state change, no events, result returned",
    run: vetoBody,
  }),

  defineCase({
    id: "X-10",
    family: "X",
    fast: false,
    title: "async pipeline — post-disconnect resolution applies nothing",
    run: asyncStaleBody,
  }),

  defineCase({
    id: "X-11",
    family: "X",
    fast: true,
    title: "error path — throwing stage ⇒ tsr-action-error + ok:false",
    run: errorPathBody,
  }),
  defineCase({
    id: "X-12",
    family: "X",
    fast: true,
    title: "behaviors — add/connect/cleanup, throw isolation, remove, unsubscribe",
    async run(mount, expect) {
      // §6.5 (brief 2f): the mount handle exposes this tier's behaviors
      // namespace — the SAME registry the mounted element consults on every
      // connect. Registered fns ride the fixture tag, so the body is
      // tier-agnostic (the adapter supplies `behaviors` alongside `el`).
      const h = await mount({fixture: "counter"});
      const trace = [];
      const run = () => {
        trace.push("run");
        return () => trace.push("cleanup");
      };
      const boom = () => {
        throw new Error("behavior boom");
      };

      // add returns an UNSUBSCRIBE function (§6.5 — additive to the void
      // the pre-2f registry returned).
      const unsub = h.behaviors.add(h.tag, run);
      expect(typeof unsub).to.equal("function");

      // Behaviors run on EVERY connect — the mount already connected, so
      // force a fresh connect to observe the registration.
      h.el.remove();
      h.win.document.body.appendChild(h.el);
      await h.waitFor(() => trace.includes("run"));

      // Throw isolation: the throwing behavior is caught + warned, never
      // breaking the element or its sibling registration.
      h.behaviors.add(h.tag, boom);
      h.el.remove();
      h.win.document.body.appendChild(h.el);
      await h.waitFor(() => trace.filter((t) => t === "run").length >= 2);
      expect(h.el.isConnected).to.equal(true);

      // Cleanups run on the matching disconnect — one per connect (the
      // throwing behavior returns no cleanup; it must not disturb the count).
      h.el.remove();
      await h.waitFor(() => trace.includes("cleanup"));
      const runs = trace.filter((t) => t === "run").length;
      expect(trace.filter((t) => t === "cleanup").length).to.equal(runs);

      // remove() AND the unsubscribe both deregister — a re-connected
      // element runs nothing further.
      h.behaviors.remove(h.tag, boom);
      unsub();
      expect(h.behaviors.get(h.tag)).to.not.include(run);
      expect(h.behaviors.get(h.tag)).to.not.include(boom);
      h.win.document.body.appendChild(h.el);
      await h.settle();
      expect(trace.filter((t) => t === "run").length).to.equal(runs);
    },
  }),
  defineCase({
    id: "X-13",
    family: "X",
    fast: true,
    title: "subclass hooks — allowed set super-chains; reserved members enforced",
    run: subclassHooksBody,
  }),
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
  defineCase({
    id: "X-16",
    family: "X",
    fast: true,
    title: "Elixir derivation end-to-end — derived tag registers, merged surface, base untouched",
    async run(mount, expect) {
      // §5.10 (brief 3f): `use Vendor, tag: "own-tag"` derives a NEW element
      // on its own tag with the MERGED surface — the vendor's inherited
      // actions + the derive-declared additions — while the vendor base
      // stays untouched under its own tag. Tier-agnostic: bodies use only
      // the mount-handle contract; the literal tags live in each adapter's
      // fixture map. (Tier 2 wired: `tsr-holo-takeover-derived`; Tier 1
      // adapter-pending until its generated derived fixture lands.)
      const d = await mount({fixture: "derived"});

      // 1. the fresh tag registers and exactly one class owns it
      const ctor = d.win.customElements.get(d.tag);
      expect(ctor).to.be.a("function");
      expect(d.el.constructor).to.equal(ctor);

      // 2. inherited surface: the derived init delegates to the vendor's —
      //    the same state shape as the pipeline mirror (no new keys)
      expect(Object.keys(d.el.state).sort()).to.deep.equal(["count", "meta", "selectedId"]);

      // 3. an inherited action runs through the merged surface
      expect((await d.el.dispatchAction("bump")).ok).to.equal(true);
      expect(d.el.state.count).to.equal(1);

      // 4. the derive-declared NEW action works
      expect((await d.el.dispatchAction("reset")).ok).to.equal(true);
      expect(d.el.state.count).to.equal(0);

      // 5. the vendor base is untouched: no derived-only action on it, and
      //    its own surface still dispatches
      const base = await mount({fixture: "pipeline"});
      const reset = await base.el.dispatchAction("reset");
      expect(reset.ok).to.equal(false);
      expect(reset.reason).to.equal("unknown-action");
      expect((await base.el.dispatchAction("bump")).ok).to.equal(true);
      expect(base.el.state.count).to.equal(1);
    },
  }),
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

  defineCase({
    id: "X-19",
    family: "X",
    fast: true,
    title: "tag-extension chain (D1) — takeover registers, deterministic chain, base suite passes",
    async run(mount, expect) {
      // Identity (§5.9): the COMPOSED class owns the base tag. The three
      // `tag: :inherit` layers queued themselves as registry mixins at
      // import (they define NO element of their own) and the base module's
      // defineOnce composed the whole chain at the tag's first definition.
      const h = await mount({fixture: "takeover"});
      // Identity (§5.9): the COMPOSED class owns the base tag — whatever
      // tag the tier's fixture map names ("tsr-conf-takeover" on Tier 1,
      // "tsr-holo-takeover-probe" on Tier 2); the literal is adapter
      // knowledge, the identity is the contract.
      const ctor = h.win.customElements.get(h.tag);
      expect(ctor).to.be.a("function");
      expect(h.el.constructor).to.equal(ctor);

      // Deterministic chain (§5.9: dependency depth → priority → module
      // name). Ccc (depth 2, extends Bbb) sits outermost; Bbb (depth 1,
      // priority 10) outside Aaa (depth 1, priority 0). The layers' marker
      // events trace the down-chain: the outermost layer runs first, every
      // layer hands off via real ES `super`, and the vendor base body still
      // runs last. Layers this dispatch never overrides stay silent.
      const trace = [];
      const names = {["conf-ext-aaa"]: "aaa", ["conf-ext-bbb"]: "bbb", ["conf-ext-ccc"]: "ccc"};
      const listeners = Object.entries(names).map(([event, label]) => {
        const fn = () => trace.push(label);
        h.win.document.addEventListener(event, fn);
        return [event, fn];
      });
      try {
        expect((await h.el.dispatchAction("bump")).ok).to.equal(true);
        expect(trace).to.deep.equal(["ccc", "aaa"]); // Bbb never overrides bump
        expect(h.el.state.count).to.equal(1); // the vendor body still ran
        trace.length = 0;
        expect((await h.el.dispatchAction("selectItem", {itemName: "taken"})).ok).to.equal(true);
        expect(trace).to.deep.equal(["bbb"]); // Aaa never overrides select_item
        expect(h.el.state.selectedId).to.equal("taken");
        expect(h.el.state.count).to.equal(2); // the vendor body still ran
      } finally {
        for (const [event, fn] of listeners) h.win.document.removeEventListener(event, fn);
      }

      // THE GATE (§5.9): the BASE tag's conformance suite passes on the
      // extended element — the pipeline case bodies replay VERBATIM on the
      // taken-over fixture (mirror state keys, action semantics and data-cy
      // surface; the layers add NO state keys, so every snapshot pin holds).
      await stateSnapshotBody(mount, expect, "takeover"); // X-05
      await stateChangeBody(mount, expect, "takeover"); // X-06
      await openDispatchBody(mount, expect, "takeover"); // X-07
      await interceptorOrderBody(mount, expect, "takeover"); // X-08
      await vetoBody(mount, expect, "takeover"); // X-09
      await asyncStaleBody(mount, expect, "takeover"); // X-10
      await errorPathBody(mount, expect, "takeover"); // X-11
      await caseNormalizationBody(mount, expect, "takeover"); // X-20

      // The §5.7 chain-conflict WARNING is a compile-time Elixir property —
      // the JS registry cannot compile — so it is proven in
      // test/noizu/tessera/component/extension_test.exs. The takeover
      // fixtures deliberately have NO same-depth overlap (Aaa overrides
      // bump, Bbb select_item): every silence traced above is a per-action
      // miss, never a conflict-induced one.
    },
  }),
  defineCase({
    id: "X-20",
    family: "X",
    fast: true,
    title: "case normalization end-to-end (D3) — camel/snake both accepted",
    run: caseNormalizationBody,
  }),
  defineCase({
    id: "X-21",
    family: "X",
    fast: true,
    title: "JS tag extension — extendElement composes pre-define mixins; post-define warns",
    async run(mount, expect) {
      // Pre-define composition (§5.9): the harness queued two UNLABELLED
      // mixins on <tsr-conf-x21> at module load and the FIRST defineOnce
      // composed them into the single definition. A perfect tie (no depth /
      // priority / module coordinates) resolves by the §6.4 onion fallback:
      // FIRST-REGISTERED OUTERMOST ⇒ m1 outer, m2 inner.
      const h = await mount({fixture: "x21"});
      expect(h.el.layerTrace()).to.deep.equal(["base", "m2", "m1"]);
      // exactly ONE class owns the tag — the composed one
      const ctor = h.win.customElements.get(h.tag);
      expect(h.el.constructor).to.equal(ctor);

      // Post-define registration can no longer layer onto a defined class:
      // extendElement returns false and warns ONCE, pointing at the
      // sanctioned post-define paths (behaviors §6.5 / onAction §6.4).
      const warns = [];
      const orig = h.win.console.warn;
      h.win.console.warn = (m) => warns.push(String(m));
      let queued;
      try {
        queued = h.extend((Base) => class extends Base {});
      } finally {
        h.win.console.warn = orig;
      }
      expect(queued).to.equal(false);
      expect(warns.filter((w) => w.includes("already defined")).length).to.equal(1);
      // The warning names a sanctioned post-define path. onAction (§6.4) is
      // the one both tiers share; Tier 1 also names behaviors (§6.5), and
      // Tier 2, which has no behaviors API, names compiled takeover modules.
      expect(warns.some((w) => w.includes("onAction"))).to.equal(true);

      // warn-once per tag: a second late registration stays silent
      h.win.console.warn = (m) => warns.push(String(m));
      try {
        expect(h.extend((Base) => class extends Base {})).to.equal(false);
      } finally {
        h.win.console.warn = orig;
      }
      expect(warns.filter((w) => w.includes("already defined")).length).to.equal(1);

      // neither late layer composed — the definition is immutable after the
      // first define; layering happens pre-define or via the pipeline
      expect(h.el.layerTrace()).to.deep.equal(["base", "m2", "m1"]);
    },
  }),
];

// -- tier-agnostic pipeline bodies (X-05…X-11, X-20) ---------------------------
//
// Function DECLARATIONS (hoisted — the cases array above references them).
// Each body mounts a LOGICAL fixture and uses only the mount-handle contract
// (`el.state`, `settle()`, `waitFor`, `nextEvent`), so BOTH tiers and — for
// X-19 — the tag-takeover mirror of the pipeline run them verbatim: the
// `fixture` argument names which mount to pin ("pipeline" default; X-19
// passes "takeover", whose data-cy + action surface mirrors it exactly).

async function stateSnapshotBody(mount, expect, fixture = "pipeline") {
  // state count / selected_id / meta (identical in the takeover mirror).
  const h = await mount({fixture});
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
}

async function stateChangeBody(mount, expect, fixture = "pipeline") {
  const h = await mount({fixture});
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
}

async function openDispatchBody(mount, expect, fixture = "pipeline") {
  const h = await mount({fixture});
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
    // (warn-once is per tag+action, so the takeover replay warns fresh)
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
}

async function interceptorOrderBody(mount, expect, fixture = "pipeline") {
  const h = await mount({fixture});
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
}

async function vetoBody(mount, expect, fixture = "pipeline") {
  const h = await mount({fixture});
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
}

async function asyncStaleBody(mount, expect, fixture = "pipeline") {
  const h = await mount({fixture});
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
}

async function errorPathBody(mount, expect, fixture = "pipeline") {
  const h = await mount({fixture});
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
}

async function caseNormalizationBody(mount, expect, fixture = "pipeline") {
  const h = await mount({fixture});
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
}

// -- X-02: contract-surface agreement (attrs / props / events / slots) --------
//
// The generated manifest maps are the CONTRACT for the shared logical
// fixtures (§9 rule 1 — one spec, two engines); the physical tags are adapter
// knowledge, so the body keys by logical fixture name and reads the contract
// under the spec's Tier-1 tag. Runtime observation is through the
// mount-handle contract only:
//   * attrs — a DECLARED attr is accepted and cast (integer step drives the
//     bump); an UNdeclared attribute is inert on both engines (never a prop);
//   * props — tsr-props camelCase JSON overrides the attr default;
//   * events — sweeping every declared action while the window's
//     HTMLElement.prototype.dispatchEvent is recorded (both engines dispatch
//     contract events through it) proves the fired set is exactly
//     declared ∪ runtime plumbing (§6.2 tsr-state-change / §6.4
//     tsr-action-error), and each declared event fires with EXACTLY its
//     declared detail keys;
//   * slots — the shadow root renders exactly the declared named slots plus
//     the implicit default.
async function contractSurfaceBody(mount, expect) {
  const stateContract = manifests["tsr-conf-state"];
  const pipelineContract = manifests["tsr-conf-pipeline"];
  const slotsContract = manifests["tsr-conf-slots"];

  // attrs — declared default, declared + cast, undeclared inert
  const def = await mount({fixture: "state"});
  expect((await def.el.dispatchAction("bump")).ok).to.equal(true);
  expect(def.el.state.count).to.equal(1); // declared attr default (step = 1)

  const typed = await mount({fixture: "state", attrs: {step: "3"}});
  expect((await typed.el.dispatchAction("bump")).ok).to.equal(true);
  expect(typed.el.state.count).to.equal(3); // declared attr, integer cast

  const inert = await mount({fixture: "state", attrs: {"not-in-contract": "5"}});
  expect((await inert.el.dispatchAction("bump")).ok).to.equal(true);
  expect(inert.el.state.count).to.equal(1); // undeclared attr is NOT a prop

  // props — tsr-props camelCase JSON overrides the attribute default
  const props = await mount({fixture: "state", attrs: {"tsr-props": JSON.stringify({step: 2})}});
  expect((await props.el.dispatchAction("bump")).ok).to.equal(true);
  expect(props.el.state.count).to.equal(2);

  // events — declared-set sweep with dispatchEvent recorded
  const plumbing = ["tsr-state-change", "tsr-action-error"]; // §6.2/§6.4 runtime events
  const sweeps = [
    ["state", stateContract, ["bump"]],
    ["pipeline", pipelineContract, ["bump", "selectItem", "seedCache"]],
  ];
  for (const [fixture, contract, actions] of sweeps) {
    const h = await mount({fixture});
    const fired = [];
    const proto = h.win.HTMLElement.prototype;
    const orig = proto.dispatchEvent;
    const inScope = (node) => node === h.el || node.getRootNode() === h.shadowRoot;
    proto.dispatchEvent = function (ev) {
      if (inScope(this)) fired.push(ev);
      return orig.call(this, ev);
    };
    try {
      for (const name of actions) {
        expect((await h.el.dispatchAction(name)).ok, `${fixture}:${name} dispatches`).to.equal(true);
        await h.settle();
      }
    } finally {
      proto.dispatchEvent = orig;
    }
    const types = fired.filter((ev) => ev instanceof h.win.CustomEvent).map((ev) => ev.type);
    const declared = contract.events.map((e) => e.name);
    for (const t of types) {
      expect(
        declared.includes(t) || plumbing.includes(t),
        `undeclared event "${t}" fired on ${fixture}`,
      ).to.equal(true);
    }
    for (const decl of contract.events) {
      expect(types, `${fixture} fires declared event ${decl.name}`).to.include(decl.name);
      const hit = fired.find((ev) => ev.type === decl.name);
      expect(Object.keys(hit.detail ?? {}).slice().sort()).to.deep.equal(
        Object.keys(decl.detail).slice().sort(),
      );
    }
  }

  // slots — exactly the declared named slots + the implicit default
  const s = await mount({fixture: "slots"});
  const names = [...s.shadowRoot.querySelectorAll("slot")].map((sl) => sl.getAttribute("name") ?? "");
  expect(names.filter((n) => n !== "").sort()).to.deep.equal(slotsContract.slots.slice().sort());
  expect(names.filter((n) => n === "")).to.have.lengthOf(1);
}

// -- X-13: §6.6 subclass hooks -------------------------------------------------
//
// The ALLOWED hook set (connected/disconnected/attributeChangedCallback MUST
// super; firstUpdated/updated SHOULD super — present on both engines, Tier 2
// via the brief-3c lifecycle projection) is exercised through the shared
// "subclass" fixture: EACH adapter supplies the subclass wiring (the LC/FM
// recording-subclass precedent — a defined tag cannot be re-defined, and the
// tier-2 registration path runs through the runtime's defineElement), and the
// SHARED body asserts the CONTRACT on the subclass instance using only the
// mount-handle contract. The adapter subclass overrides every documented hook
// with a REAL super call, tracing through the NON-reserved `x13Trace` array
// (§6.8: `_`-prefixed members are tessera-internal). Super-chaining is proven
// by EFFECT — the component mounts, re-observes tsr-props, and survives
// disconnect/reconnect. Reserved members are enforced where the platform makes
// that observable: the state accessor is read-only (getter, no setter), the
// tag cannot be re-defined (first definition wins), and the §6.1 static
// surface inherits unmutated. The render() row of §6.6 is deliberately NOT
// exercised here — it is Tier-1-overridable and Tier-2-reserved by decision
// U5, so no shared body can assert it; the divergence is pinned by the
// contract itself, not by this case.
async function subclassHooksBody(mount, expect) {
  const base = await mount({fixture: "state"});
  const baseCtor = base.win.customElements.get(base.tag);
  const h = await mount({fixture: "subclass"});
  const subCtor = h.win.customElements.get(h.tag);

  // allowed set: the hooks ran AND their super-chains are live (the component
  // mounted — state reads report the real snapshot, §6.2)
  await h.settle();
  const trace = h.el.x13Trace ?? [];
  expect(trace, "connected").to.include("connected");
  expect(Object.keys(h.el.state).length).to.be.greaterThan(0);
  expect(trace, "firstUpdated").to.include("firstUpdated");
  expect(trace, "updated").to.include("updated");

  // attributeChangedCallback super-chain: tsr-props applies POST-connect on
  // both engines (the Tier-2 guard only forwards on a live mount)
  h.el.setAttribute("tsr-props", JSON.stringify({step: 5}));
  await h.settle();
  expect(trace, "tsr-props observed").to.include("tsr-props");
  // What a shared body may assert about the attribute's EFFECT is that the
  // super-chain left the engine live, not prop propagation into action state:
  // Tier 1 syncs attrs -> properties reactively (the bump would observe step
  // 5), while Tier 2 seeds component state from props at init and a live
  // tsr-props update reaches the render view only (lit-parity SS2.2 - attrs
  // flow one-way in). The propagation delta is a SS2.2 fact, not an X-13
  // failure; X-13's contract surface is the hook chain + reserved set.
  expect((await h.el.dispatchAction("bump")).ok, "bump after live tsr-props").to.equal(true);

  // reserved members enforced
  expect(() => {
    h.el.state = {}; // getter without a setter — strict-mode TypeError
  }).to.throw();
  expect(() => h.win.customElements.define(h.tag, baseCtor)).to.throw(); // first definition wins
  expect(subCtor.tesseraActions.slice().sort()).to.deep.equal(baseCtor.tesseraActions.slice().sort());
  expect(subCtor.observedAttributes.slice().sort()).to.deep.equal(baseCtor.observedAttributes.slice().sort());
  expect(subCtor.tesseraExtensionApi).to.equal(baseCtor.tesseraExtensionApi);

  // disconnect → reconnect: super-chained teardown AND re-establishment.
  // Count continuity is tier-divergent by contract (§6.2 — Tier 2 remounts
  // fresh; Tier 1 keeps the element), so only the result convention holds.
  h.el.remove();
  await h.settle();
  expect(trace, "disconnected").to.include("disconnected");
  h.win.document.body.appendChild(h.el);
  await h.settle();
  expect(h.el.isConnected).to.equal(true);
  expect((await h.el.dispatchAction("bump")).ok).to.equal(true);
}
