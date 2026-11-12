// Root = the tessera repo root, so tests in `js/test/` can import the
// package source directly at `../../priv/js/src/*.mjs` and (for the
// duplicate-module-copy test) import the same file twice with a
// cache-busting query — exactly the two-copies-per-page situation Hologram
// bundles create.
//
// Test tiering (docs/notes/test-tiering.md): `files` globs are relative to the
// cwd (js/). The default run is the FULL suite; `--group fast` is the
// per-change FAST subset (behavior-defining core). The per-host Lit matrix and
// cross-module-copy redundancy (*.lit.test.mjs / *.copies.test.mjs) are FULL-only.
import { chromeLauncher } from "@web/test-runner-chrome";

// TESSER-031: CI runs this suite against GitHub's preinstalled system Chrome
// via chrome-launcher with ZERO launch flags and the default 30s
// browserStartTimeout. On a cold 2-core runner the first test page can
// outlive that window ("browser was unable to create and start a test page
// after 30000ms" — js-fast 43178367276, js-integration 43127541770, and
// 43124786857 on develop, all 2026-11-12), failing the job even though every
// test that did run passed. Structural fix: an explicit launcher with the
// standard headless-Linux CI flags (--no-sandbox for runner-user policy
// noise, --disable-dev-shm-usage for shared-memory robustness, --disable-gpu
// for GPU-less runners) and a doubled page-start budget. --no-sandbox is
// acceptable ONLY inside ephemeral, single-tenant CI runners (isCI-gated);
// never enable it for local/dev browsers. Local dev keeps the
// stock zero-flag launch (CI is GitHub-set). concurrency stays 1 — the flake
// occurs fully serialized, so it is not a parallelism problem.
const isCI = Boolean(process.env.CI);

export default {
  rootDir: new URL("..", import.meta.url).pathname,
  nodeResolve: true,
  // FULL suite (default `npm test`): every test file, incl. the host matrix +
  // cross-copy hardening. helpers.mjs is not a `.test.mjs` so it is never run.
  files: ["test/**/*.test.mjs"],
  // FAST per-change group (`npm run test:fast` → `wtr --group fast`): the
  // core element/bridge/behaviors/events tests + the defineOnce/public-surface
  // packaging guards. Proves the shadow-event → dispatchAction → re-render claim.
  groups: [
    {
      name: "fast",
      files: [
        "test/bridge.test.mjs",
        "test/element.test.mjs",
        "test/behaviors.test.mjs",
        "test/pipeline.test.mjs",
        "test/events.test.mjs",
        "test/bus.test.mjs",
        "test/define.test.mjs",
        "test/index.test.mjs",
        // lit-parity #96: render_root: :light (BoE need #1).
        "test/light_dom.test.mjs",
        // lit-parity #63: keyed {%for} → repeat (BoE need #2).
        "test/repeat.test.mjs",
        // lit-parity #67: live() + .prop bindings (BoE need #3).
        "test/live.test.mjs",
        // lit-parity #71/#66: unsafe_html + guard (BoE need #4).
        "test/unsafe_guard.test.mjs",
        // TESSER-019: `mix tessera.from_lit` conversion rendered LIVE
        // (fixture: test/support/conformance/conf_from_lit.ex).
        "test/from_lit_render.test.mjs",
        // Phase 4b conformance suite — Tier-1 FAST lane (behavior-defining
        // core cases only; pending cases skipped, never green). The `.fast.mjs`
        // suffix keeps the default full glob from double-running it.
        "test/conformance.tier1.fast.mjs",
      ],
    },
    {
      // Targeted full conformance run (`npm run test:conformance`): every
      // Tier-1 case (fast + slow), pending skipped.
      name: "conformance",
      files: ["test/conformance.tier1.test.mjs"],
    },
  ],
  // Keep browsers/frames serialized: every file shares the document-level
  // bridge singleton inside its own iframe, but serializing keeps output
  // deterministic and matches the tobor-kit WTR setup style.
  concurrentBrowsers: 1,
  concurrency: 1,
  // TESSER-031: explicit chrome launcher (see note at top). The flags key is
  // chrome-launcher's `chromeFlags`; empty locally. Only browserStartTimeout
  // is actually raised (30000 -> 60000); testsStartTimeout is pinned at its
  // existing 60000 default purely for explicitness.
  browsers: [
    chromeLauncher({
      launchOptions: {
        chromeFlags: isCI
          ? ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"]
          : [],
      },
    }),
  ],
  browserStartTimeout: 60000,
  testsStartTimeout: 60000,
};