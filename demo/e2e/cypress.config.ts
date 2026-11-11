import { defineConfig } from "cypress";
import { plugin as cypressGrepPlugin } from "@cypress/grep/plugin";

// Test tiering (docs/notes/test-tiering.md): specs carry @fast / @slow tags.
// The fast per-change lane runs `npm run test:fast` (grepTags=@fast) — the
// core-claim smoke + quick specs; the full/nightly lane runs every host.
export default defineConfig({
  expose: {
    // When a grep/tag filter is active, skip loading specs that contain no
    // matching tests (the fast lane loads only the @fast smoke specs).
    grepFilterSpecs: true,
  },
  e2e: {
    supportFile: "src/support/e2e.ts",
    specPattern: "src/e2e/**/*.cy.ts",
    // Full URLs in the specs — two servers (Hologram :5586, plain :5587).
    video: false,
    defaultCommandTimeout: 10_000,
    retries: { runMode: 1, openMode: 0 },
    setupNodeEvents(on, config) {
      cypressGrepPlugin(config);
      return config;
    },
  },
});