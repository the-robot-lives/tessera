// Root = examples/spike_kit; tests import the GENERATED element modules in
// lib/ (written by `mix compile` from the Elixir DSL). Files listed
// explicitly (glob descent is unreliable on fresh dirs — see persona_kit).
export default {
  rootDir: new URL(".", import.meta.url).pathname,
  nodeResolve: true,
  files: [
    "test/components/counter_test.mjs",
    "test/components/toggle_chip_test.mjs",
    "test/components/styles_panel_test.mjs",
  ],
  concurrentBrowsers: 1,
  concurrency: 1,
};
