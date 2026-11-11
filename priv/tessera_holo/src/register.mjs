// Runtime-free component registrar — the ONLY shim code that per-component
// bundles import. It never references the Hologram runtime, so esbuild
// never pulls the runtime into a component bundle and load order does not
// matter: descriptors queue on globalThis and are applied by whichever
// tessera runtime initializes (first or later — see tessera_holo.mjs).

const QUEUE_KEY = "__TesseraHoloComponents";

export function registerComponent(moduleName, defs, manifest = {}) {
  const g = globalThis;

  if (!Array.isArray(g[QUEUE_KEY])) {
    g[QUEUE_KEY] = [];
  }

  g[QUEUE_KEY].push({moduleName, defs, manifest});

  // Runtime already live? Apply immediately.
  if (typeof g.__TesseraHoloApply__ === "function") {
    g.__TesseraHoloApply__();
  }
}

export function takeQueuedComponents() {
  const g = globalThis;
  const queue = Array.isArray(g[QUEUE_KEY]) ? g[QUEUE_KEY] : [];
  g[QUEUE_KEY] = [];
  return queue;
}
