/**
 * `@noizu/tessera-core` — the Tessera JS core (CONTRACT.md §4).
 * No runtime dependencies; `lit` is an optional peer (the core never
 * imports it). Plain ESM, usable directly via `file:` deps — Hologram's
 * esbuild consumes `src/` without a build step.
 */

export { defineOnce } from "./define.mjs";
export { extendElement } from "./extend.mjs";
export { emit, snakeKeysDeep, camelKeysDeep, snakeCaseKey, camelCaseKey } from "./events.mjs";
export { getBridge, registerEvents, parseTsrOn } from "./bridge.mjs";
export { behaviors } from "./behaviors.mjs";
export { TesseraElement } from "./element.mjs";
export { makeSnapshot, normalizeActionName, normalizeParams, runPipeline } from "./pipeline.mjs";
export { BusClient, noneTransport, envelope } from "./bus.mjs";
