/**
 * `TesseraElement(Base, contract)` — the contract-driven element mixin
 * (CONTRACT.md §4). Works over `HTMLElement` AND `LitElement`: no Lit
 * import here, everything is duck-typed through the `Base` class.
 *
 * Per instance it:
 *   - observes the contract attrs plus `tsr-props` (merged with whatever
 *     `Base.observedAttributes` already declares),
 *   - coerces attributes to typed properties (string / integer / float /
 *     boolean-by-presence) per the contract's `type`,
 *   - parses the `tsr-props` JSON and assigns each key as a property; bad
 *     JSON warns, never throws,
 *   - calls `requestUpdate()` when the base provides it, after property
 *     assignment,
 *   - on `connectedCallback` registers the contract's events with the
 *     bridge and runs the tag's behaviors, collecting their cleanups,
 *   - on `disconnectedCallback` runs those cleanups.
 */

import { registerEvents } from "./bridge.mjs";
import { behaviorsFor } from "./behaviors.mjs";

const TSR_PROPS_ATTR = "tsr-props";

/**
 * Coerce an attribute value to the contract type. `value` is the attribute
 * string, or `null` when the attribute was removed.
 */
function coerceValue(def, value) {
  switch (def.type) {
    case "boolean":
      // Booleans ride by presence/absence (CONTRACT.md §3).
      return value !== null && value !== undefined;
    case "integer": {
      const n = Number.parseInt(value, 10);
      return Number.isNaN(n) ? (def.default ?? null) : n;
    }
    case "float": {
      const n = Number.parseFloat(value);
      return Number.isNaN(n) ? (def.default ?? null) : n;
    }
    default:
      // string (and any untyped/any attr) passes through verbatim; removal ⇒ null
      return value;
  }
}

function applyTsrProps(el, contract, raw) {
  if (raw === null || raw === undefined || raw === "") return;
  let data;
  try {
    data = JSON.parse(raw);
  } catch (err) {
    console.warn(`[tessera] <${contract.tag}> ignoring invalid tsr-props JSON: ${err?.message ?? err}`);
    return;
  }
  if (data === null || typeof data !== "object" || Array.isArray(data)) {
    console.warn(`[tessera] <${contract.tag}> ignoring tsr-props: expected a JSON object`);
    return;
  }
  for (const [key, value] of Object.entries(data)) {
    try {
      el[key] = value;
    } catch (err) {
      console.warn(`[tessera] <${contract.tag}> could not set property "${key}" from tsr-props: ${err?.message ?? err}`);
    }
  }
  el.requestUpdate?.();
}

/**
 * @param {Function} Base `HTMLElement` or `LitElement` (or a subclass).
 * @param {object} contract a generated contract module (CONTRACT.md §2).
 * @returns {Function} the mixed class.
 */
export function TesseraElement(Base, contract) {
  const attrDefs = Array.isArray(contract?.attrs) ? contract.attrs : [];
  const eventNames = (Array.isArray(contract?.events) ? contract.events : [])
    .map((e) => e?.name)
    .filter((n) => typeof n === "string");
  const tag = contract?.tag ?? "(unknown tag)";
  const attrMap = new Map();
  for (const def of attrDefs) {
    if (def && typeof def.name === "string") attrMap.set(def.name, def);
  }

  return class extends Base {
    static get observedAttributes() {
      // `super.observedAttributes` binds `this` to THIS class (the mixin
      // result), so for a LitElement base it runs Lit's finalize-on-read and
      // returns this class's own reactive-attribute list; for a plain
      // HTMLElement base it is simply undefined.
      const own = super.observedAttributes;
      return [...new Set([...(Array.isArray(own) ? own : []), ...attrMap.keys(), TSR_PROPS_ATTR])];
    }

    constructor(...args) {
      super(...args);
      /** @type {Function[] | null} cleanups returned by behaviors */
      this.__tesseraCleanups = null;
      // Boolean attrs ride by presence/absence — an absent boolean is false,
      // not undefined (CONTRACT.md §3).
      for (const def of attrDefs) {
        if (def.type === "boolean") {
          const key = def.key ?? def.name;
          if (this[key] === undefined) this[key] = false;
        }
      }
    }

    attributeChangedCallback(name, oldValue, newValue) {
      // Lit first (it maps its own reactive attrs), then contract coercion
      // so contract types win for attrs declared in both places.
      super.attributeChangedCallback?.(name, oldValue, newValue);
      if (oldValue === newValue) return;
      if (name === TSR_PROPS_ATTR) {
        applyTsrProps(this, contract, newValue);
        return;
      }
      const def = attrMap.get(name);
      if (!def) return;
      const key = def.key ?? def.name;
      this[key] = coerceValue(def, newValue);
      this.requestUpdate?.();
    }

    connectedCallback() {
      super.connectedCallback?.();
      registerEvents(eventNames, contract?.tag);
      // Behaviors run on EVERY connect (CONTRACT.md §4); each may return a
      // cleanup, which runs on the matching disconnect. A behavior throwing
      // must not break the element's connection.
      const cleanups = [];
      for (const fn of behaviorsFor(contract?.tag)) {
        try {
          const cleanup = fn(this);
          if (typeof cleanup === "function") cleanups.push(cleanup);
        } catch (err) {
          console.warn(`[tessera] behavior for <${tag}> threw: ${err?.message ?? err}`);
        }
      }
      this.__tesseraCleanups = cleanups;
    }

    disconnectedCallback() {
      const cleanups = this.__tesseraCleanups;
      this.__tesseraCleanups = null;
      if (cleanups) {
        for (const cleanup of cleanups) {
          try {
            cleanup();
          } catch (err) {
            console.warn(`[tessera] behavior cleanup for <${tag}> threw: ${err?.message ?? err}`);
          }
        }
      }
      super.disconnectedCallback?.();
    }
  };
}
