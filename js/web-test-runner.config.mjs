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
        "test/pipeline.test.mjs",
        "test/events.test.mjs",
        "test/bus.test.mjs",
        "test/define.test.mjs",
        "test/index.test.mjs",
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
};