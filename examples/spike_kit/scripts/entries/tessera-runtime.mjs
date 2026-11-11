// The shared tessera runtime: one module re-exporting BOTH lit and
// @noizu/tessera-core, so an import map can point both bare specifiers at
// this single URL — one module instance, one defineOnce registry.
//
// Re-exports are EXPLICIT: esbuild tree-shakes `export *` chains when
// bundling (nothing in this entry uses the names), which silently drops
// them — the spike hit exactly that ("module 'lit' does not provide an
// export named 'html'"). Listing the names pins the contract: consumers of
// the shared-runtime variant may import the lit root surface below, the
// directive subpaths used by generated elements (brief 1d step 4), and
// anything the tessera core exports. The import map maps the bare
// `lit` specifiers AND the `lit/directives/*.js` subpaths at this single
// URL, so bundled elements share ONE directive module instance too.
export {
  LitElement,
  html,
  css,
  svg,
  render,
  nothing,
} from "lit";
export { classMap } from "lit/directives/class-map.js";
export { styleMap } from "lit/directives/style-map.js";
export { ifDefined } from "lit/directives/if-defined.js";
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
