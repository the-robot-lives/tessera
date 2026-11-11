// Tier-1 conformance adapter — FAST per-change lane (Web Test Runner).
//
// Runs only the behavior-defining core cases (fast:true) — the @fast subset of
// the conformance suite (docs/notes/test-tiering.md). Listed explicitly in the
// WTR `fast` group; the `.fast.mjs` suffix (NOT `.test.mjs`) keeps the default
// full glob from double-running it. Pending fast cases are skipped, never green.

import {FAST_CASES} from "../../test/conformance/support/registry.mjs";
import {runConformance} from "./conformance-tier1-harness.mjs";

runConformance(FAST_CASES, "fast");