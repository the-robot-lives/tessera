import { defineConfig } from "cypress";

export default defineConfig({
  e2e: {
    supportFile: "src/support/e2e.ts",
    specPattern: "src/e2e/**/*.cy.ts",
    // Full URLs in the specs — two servers (Hologram :5586, plain :5587).
    video: false,
    defaultCommandTimeout: 10_000,
    retries: { runMode: 1, openMode: 0 },
  },
});
