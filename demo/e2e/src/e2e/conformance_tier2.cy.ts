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
// HONESTY: only the counter fixture is wired on Tier 2 today (SUPPORTED below).
// Implemented cases whose Tier-2 fixture is not yet wired are adapter-pending;
// registry-pending cases (unimplemented features) are pending. Neither is ever
// green. The remaining cases land with the feature briefs (2a–2f / 3d / 3f).
//
// Requires the Hologram demo on :5586 (CI boots it; see .github/workflows/ci.yml).

/// <reference types="cypress" />
// @ts-ignore — tier-agnostic ESM case modules (no .d.ts; Cypress transpiles only)
import {CASES, FAST_CASES} from "../../../../test/conformance/support/registry.mjs";
import {visitTier2Host, mount, cleanup} from "../support/tessera/conformance";

// Cases whose behavior + Tier-2 fixture are wired today (the shared counter).
const SUPPORTED = new Set<string>(["C-01", "T-01", "E-01", "E-02", "E-03"]);

type ConfCase = {
  id: string;
  fast: boolean;
  title: string;
  status: string;
  run: ((mount: typeof mount, expect: Chai.ExpectStatic) => Promise<void>) | null;
};

// Registers the before/afterEach hooks + one it() per case. Pending cases
// (registry-level or adapter-level) are skipped — never green.
function registerCases(cases: ConfCase[]): void {
  before(() => {
    visitTier2Host();
  });

  afterEach(() => {
    cleanup();
  });

  for (const k of cases) {
    it(`${k.id} — ${k.title}`, function () {
      if (k.status === "pending") this.skip(); // unimplemented / accepted-as-gap
      if (!SUPPORTED.has(k.id)) this.skip(); // Tier-2 fixture not wired yet
      return k.run!(mount, expect);
    });
  }
}

describe("conformance — Tier 2 (Hologram-in-element, fast lane)", {tags: "@fast"}, () => {
  registerCases(FAST_CASES as ConfCase[]);
});

describe("conformance — Tier 2 (Hologram-in-element, slow lane)", {tags: "@slow"}, () => {
  registerCases((CASES as ConfCase[]).filter((k) => !k.fast));
});