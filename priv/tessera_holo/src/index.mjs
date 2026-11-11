// Public API of the tessera-holo runtime shim (Tier 2 spike).
//
// Bundled (once) into tessera-runtime.esm.js / tessera-runtime.umd.js next
// to the Hologram client runtime. Hosts import from there; per-component
// bundles import only register.mjs (runtime-free).

import {
  initRuntime,
  isRuntimeReady,
  mountComponent,
  setBus,
  getDescriptor,
  toJs,
} from "./tessera_holo.mjs";
import {TesseraHoloElement, defineElement, extendElement} from "./element.mjs";

export {
  initRuntime,
  isRuntimeReady,
  mountComponent,
  setBus,
  getDescriptor,
  toJs,
  TesseraHoloElement,
  defineElement,
  extendElement,
};

export function ensureRuntime() {
  if (!isRuntimeReady()) {
    throw new Error("[tessera-holo] runtime bundle executed but not initialized");
  }

  return {
    mountComponent,
    setBus,
    defineElement,
    extendElement,
    TesseraHoloElement,
  };
}
