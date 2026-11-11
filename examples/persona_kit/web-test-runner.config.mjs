// Root = examples/persona_kit, so the tests in `test/components/` import the
// colocated element modules directly (`../../lib/persona_kit/*.mjs`) — the
// same files Hologram bundles via the adapter's js_import. `@noizu/tessera-core`
// resolves through node_modules (file: dep on the tessera repo's priv/js).
//
// The test files are listed EXPLICITLY instead of via a `**` glob on
// purpose: fast-glob's `dir/**/*.ext` descent has proven unreliable on
// freshly-created directories (APFS dentry lag on the owner's volume) — an
// explicit list is deterministic everywhere. Add a line here per new test.
export default {
  rootDir: new URL(".", import.meta.url).pathname,
  nodeResolve: true,
  files: [
    "test/components/persona_card_test.mjs",
    "test/components/persona_picker_test.mjs",
  ],
  concurrentBrowsers: 1,
  concurrency: 1,
};
