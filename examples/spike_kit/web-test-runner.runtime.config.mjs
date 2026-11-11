// Shared-runtime variant lane (brief 1d step 4) — runs the BUILT dist bundles
// under an import map that mirrors demo/plain_html/react.html: bare `lit`,
// the `lit/directives/*.js` subpaths, and `@noizu/tessera-core` all resolve to
// the ONE shared dist/tessera-runtime.esm.js instance.
//
// Deliberately different from the default lane:
//   - nodeResolve: FALSE — bare specifiers must reach the browser intact so
//     the import map resolves them (nodeResolve would rewrite them to
//     /node_modules/... server-side, defeating the map).
//   - testRunnerHtml injects the import map into the test frame BEFORE the
//     framework module loads (import maps are only honored if declared first).
//   - tests avoid bare imports entirely (relative paths + inline asserts — no
//     @open-wc/testing, which would need nodeResolve).
// Run: npm run test:runtime
export default {
  rootDir: new URL(".", import.meta.url).pathname,
  nodeResolve: false,
  files: [
    "test/components/runtime_variant_test.mjs",
    "test/components/inlined_variant_test.mjs",
  ],
  concurrentBrowsers: 1,
  concurrency: 1,
  testRunnerHtml: (testFrameworkImport) => `<!DOCTYPE html>
<html>
  <head>
    <script type="importmap">
      {
        "imports": {
          "lit": "/dist/tessera-runtime.esm.js",
          "lit/directives/class-map.js": "/dist/tessera-runtime.esm.js",
          "lit/directives/style-map.js": "/dist/tessera-runtime.esm.js",
          "lit/directives/if-defined.js": "/dist/tessera-runtime.esm.js",
          "@noizu/tessera-core": "/dist/tessera-runtime.esm.js"
        }
      }
    </script>
  </head>
  <body>
    <script type="module" src="${testFrameworkImport}"></script>
  </body>
</html>`,
};
