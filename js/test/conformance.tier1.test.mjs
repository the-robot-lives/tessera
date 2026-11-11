// Tier-1 conformance adapter — FULL lane (Web Test Runner).
//
// lit-parity §4.2: each tier provides its own runner adapter; the suite defines
// behavior, not runners. This entry runs EVERY case (fast + slow) against the
// JS-core fixtures in conformance-tier1-harness.mjs. Picked up by the default
// WTR glob (`npm test`) and the `conformance` group (`npm run test:conformance`).
//
// The FAST per-change lane is the sibling entry conformance.tier1.fast.mjs
// (no `.test.mjs` suffix, so the default glob never double-runs it). Pending
// cases — registry-level (unimplemented feature) or adapter-level (Tier-1
// fixture not wired) — are skipped, never green. docs/notes/test-tiering.md.

import {CASES} from "../../test/conformance/support/registry.mjs";
import {runConformance} from "./conformance-tier1-harness.mjs";

runConformance(CASES, "full");