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
// HONESTY: the counter fixture (C/T/E core) and the state probe fixture
// (extension-contract state/action family, brief 3d) are wired on Tier 2
// (SUPPORTED below). Implemented cases whose Tier-2 fixture is not yet wired
// are adapter-pending; registry-pending cases (unimplemented features) are
// pending. Neither is ever green. The remaining cases land with the feature
// briefs (2a–2f / 3f).
//
// Requires the Hologram demo on :5586 (CI boots it; see .github/workflows/ci.yml).

/// <reference types="cypress" />
// @ts-ignore — tier-agnostic ESM case modules (no .d.ts; Cypress transpiles only)
import {CASES, FAST_CASES} from "../../../../test/conformance/support/registry.mjs";
import {visitTier2Host, mount, cleanup} from "../support/tessera/conformance";

// Cases whose behavior + Tier-2 fixture are wired today: the shared counter
// (C-01/T-01/E) + the state/action family on the probe (X-03, X-05…X-11,
// X-20 — brief 3d; §9 runtime equivalence vs Tier 1).
const SUPPORTED = new Set<string>([
  "C-01", "T-01", "E-01", "E-02", "E-03",
  "X-03", "X-05", "X-06", "X-07", "X-08", "X-09", "X-10", "X-11", "X-20",
]);

type ConfCase = {
  id: string;
  fast: boolean;
  title: string;
  status: string;
  run: ((mount: typeof mount, expect: Chai.ExpectStatic) => Promise<void>) | null;
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