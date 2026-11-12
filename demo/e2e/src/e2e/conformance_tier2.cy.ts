// Tier-2 conformance adapter — Cypress, Hologram-in-element harness.
//
// lit-parity §4.2 / EXTENSION-CONTRACT §9: the SAME tier-agnostic cases as the
// Tier-1 WTR adapter, run against standalone Hologram custom elements with an
// init wait (support/tessera/conformance.ts). A surface test that cannot pass
// identically on both tiers is a CONTRACT bug — report it, don't fork the test.
//
// Lanes (docs/notes/test-tiering.md, @cypress/grep): the describe tags are
// LITERAL so `grepFilterSpecs` can statically find them.
//   * @fast — behavior-defining core cases (`npm run test:fast`, grepTags=@fast)
//   * @slow — exhaustive matrices / redundant coverage (nightly only)
//
// HONESTY: the counter fixture (C/T/E core), the state probe fixture
// (extension-contract state/action family, brief 3d), the lifecycle probe
// fixture (tsr-holo-lifecycle — brief 3c: LC-01…04 + C-13/C-14), the slot
// probe (tsr-holo-slot-probe — brief 3e: SD-01…SD-04) and the forms probe
// (tsr-holo-form-probe — brief 3e: FM-01…FM-03) are wired on
// Tier 2 (SUPPORTED below). Implemented cases whose Tier-2 fixture is not yet
// wired are adapter-pending; registry-pending cases (unimplemented features)
// are pending. Neither is ever green. The remaining cases land with the feature
// briefs (2a–2f / 3f).
//
// Requires the Hologram demo on :5586 (CI boots it; see .github/workflows/ci.yml).

/// <reference types="cypress" />
// @ts-ignore — tier-agnostic ESM case modules (no .d.ts; Cypress transpiles only)
import {CASES, FAST_CASES} from "../../../../test/conformance/support/registry.mjs";
import {visitTier2Host, mount, cleanup} from "../support/tessera/conformance";

// Cases whose behavior + Tier-2 fixture are wired today: the shared counter
// (C-01/T-01/E) + the state/action family on the probe (X-03, X-05…X-11,
// X-20 — brief 3d; §9 runtime equivalence vs Tier 1) + the lifecycle family
// on the recording probe (LC-01…LC-04, C-13/C-14 — brief 3c: willUpdate /
// firstUpdated / updated / changed snapshots / updateComplete fence) + the
// slot family on the SlotProbe fixture (SD-01…SD-04 — brief 3e: the shim's
// data-tsr-slot → real <slot> vnode rewrite + the slotchange action binding)
// + the forms family on the FormProbe fixture (FM-01…FM-03 — brief 3e:
// manifest-declared formAssociated, ElementInternals attached by the gated
// constructor, setFormValue / formResetCallback / formDisabledCallback driven
// through the glue recording subclass) + the contract-surface sweep (X-02 —
// attrs/props/events/slots against the generated contract over the shared
// state/pipeline/slots fixtures) + the subclass-hooks contract (X-13 — §6.6,
// the StateProbe module mounted through the glue's StateSubProbeElement
// recording subclass). Cases outside this set remain adapter-pending on
// Tier 2 — never green.
const SUPPORTED = new Set<string>([
  "C-01", "C-13", "C-14", "T-01", "E-01", "E-02", "E-03",
  "LC-01", "LC-02", "LC-03", "LC-04",
  "SD-01", "SD-02", "SD-03", "SD-04",
  "FM-01", "FM-02", "FM-03",
  "X-03", "X-05", "X-06", "X-07", "X-08", "X-09", "X-10", "X-11", "X-16", "X-19", "X-20",
  "X-02", "X-13",
  "X-21",
  "SSR-01", "SSR-02",
]);

type ConfCase = {
  id: string;
  fast: boolean;
  title: string;
  status: string;
  // `mountFn` (not `mount`): naming the parameter `mount` shadowed the
  // imported mount() inside its own `typeof` annotation — TS2502. Case bodies
  // receive the real mount() positionally, unchanged.
  run: ((mountFn: typeof mount, expect: Chai.ExpectStatic) => Promise<void>) | null;
};

// Registers a fresh-host visit + one it() per case. Pending cases (registry-
// level or adapter-level) are skipped — never green.
//
// Each runnable case gets its OWN host visit: the standalone Hologram runtime
// keeps per-document interpreter state, and reusing one page across cases let
// a prior case's mounted/removed elements leak into the next (the case promise
// then never resolved). A fresh visit per case reproduces the isolated,
// proven-green pattern and keeps cases independent.
function registerCases(cases: ConfCase[]): void {
  afterEach(() => {
    cleanup();
  });

  for (const k of cases) {
    it(`${k.id} — ${k.title}`, function () {
      if (k.status === "pending") this.skip(); // unimplemented / accepted-as-gap
      if (!SUPPORTED.has(k.id)) this.skip(); // Tier-2 fixture not wired yet
      visitTier2Host(); // fresh page + ctx per case
      // The case body is a tier-agnostic async fn whose waitFor/nextEvent poll
      // via the AUT window's timers (cross-realm). Hand it to Cypress through a
      // .then command so the runner awaits it (a bare returned promise is torn
      // down mid-await); the assertions still run unchanged (non-vacuous).
      return cy.window({log: false}).then(() => k.run!(mount, expect));
    });
  }
}

describe("conformance — Tier 2 (Hologram-in-element, fast lane)", {tags: "@fast"}, () => {
  registerCases(FAST_CASES as ConfCase[]);
});

describe("conformance — Tier 2 (Hologram-in-element, slow lane)", {tags: "@slow"}, () => {
  registerCases((CASES as ConfCase[]).filter((k) => !k.fast));
});