// The shared tessera runtime: one module re-exporting BOTH lit and
// @noizu/tessera-core, so an import map can point both bare specifiers at
// this single URL — one module instance, one defineOnce registry.
//
// Re-exports are EXPLICIT: esbuild tree-shakes `export *` chains when
// bundling (nothing in this entry uses the names), which silently drops
// them — the spike hit exactly that ("module 'lit' does not provide an
// export named 'html'"). Listing the names pins the contract: consumers of
// the shared-runtime variant may import the lit root surface below (plus
// anything the tessera core exports); lit subpath imports
// (`lit/directives/*.js`) are NOT served by the single-module import map.
export {
  LitElement,
  html,
  css,
  svg,
  render,
  nothing,
} from "lit";
export {
  defineOnce,
  emit,
  snakeKeysDeep,
  camelKeysDeep,
  getBridge,
  registerEvents,
  parseTsrOn,
  behaviors,
  TesseraElement,
  BusClient,
  noneTransport,
  envelope,
} from "@noizu/tessera-core";
