// Root = the tessera repo root, so tests in `js/test/` can import the
// package source directly at `../../priv/js/src/*.mjs` and (for the
// duplicate-module-copy test) import the same file twice with a
// cache-busting query — exactly the two-copies-per-page situation Hologram
// bundles create.
export default {
  rootDir: new URL("..", import.meta.url).pathname,
  nodeResolve: true,
  files: ["test/**/*.test.mjs"],
  // Keep browsers/frames serialized: every file shares the document-level
  // bridge singleton inside its own iframe, but serializing keeps output
  // deterministic and matches the tobor-kit WTR setup style.
  concurrentBrowsers: 1,
  concurrency: 1,
};
