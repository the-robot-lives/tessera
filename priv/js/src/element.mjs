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
 *     JSON warns, never throws; `_`-prefixed (reserved) keys and keys whose
 *     current value is a function (methods) are skipped with a warn-once,
 *   - removing or replacing `tsr-props` clears the keys previous
 *     applications assigned, so stale values never outlive their payload,
 *   - calls `requestUpdate()` when the base provides it, after property
 *     assignment,
 *   - on `connectedCallback` registers the contract's events with the
 *     bridge and runs the tag's behaviors, collecting their cleanups,
 *   - on `disconnectedCallback` runs those cleanups.
 */

import { registerEvents } from "./bridge.mjs";
import { behaviorsFor } from "./behaviors.mjs";

const TSR_PROPS_ATTR = "tsr-props";

// Warn-once set for skipped tsr-props keys, pinned to `globalThis` under a
// `Symbol.for` key — the SAME singleton design as the bridge and `defineOnce`:
// Hologram's per-page bundles routinely load two copies of this module, and
// "warn once" must hold ACROSS copies, not per module instance.
const WARNED_SKIPPED_PROPS_KEY = Symbol.for("tessera.warned-props");
const warnedSkippedProps = (globalThis[WARNED_SKIPPED_PROPS_KEY] ??= new Set());

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
    case "map":
    case "list": {
      // Lit's Object/Array converters JSON-parse attribute values; match them
      // so the contract coercion never clobbers a parsed value with the raw
      // string (lit-parity C-06/#21). Parse failure keeps the raw string,
      // exactly like Lit's defaultConverter.
      if (value === null || value === undefined) return value;
      try {
        return JSON.parse(value);
      } catch (_e) {
        return value;
      }
    }
    default:
      // string (and any untyped/any attr) passes through verbatim; removal ⇒ null
      return value;
  }
}

function applyTsrProps(el, contract, raw) {
  // Keys previous applications of tsr-props ASSIGNED (skipped reserved/method
  // keys are never tracked) — so a removal or replacement can clear them.
  const applied = el.__tesseraAppliedProps ?? (el.__tesseraAppliedProps = new Set());

  if (raw === null || raw === undefined || raw === "") {
    // Attribute REMOVED (e.g. a Hologram patch dropped it): clear everything a
    // previous application assigned — stale property values must not keep
    // serving after their payload is gone.
    clearAppliedTsrProps(el, contract, applied, new Set());
    if (typeof el.requestUpdate === "function") el.requestUpdate();
    return;
  }
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
  const assigned = new Set();
  for (const [key, value] of Object.entries(data)) {
    // Reserved keys: anything starting with "_" is tessera-internal
    // (e.g. `__tesseraCleanups`), and a key whose CURRENT value is a function
    // is a method (Lit's `requestUpdate`, lifecycle callbacks). Letting
    // tsr-props clobber either breaks the element, so both are skipped with a
    // single warning per tag+key.
    let current;
    try {
      current = el[key];
    } catch {
      current = undefined; // exotic getter; fall through to the guarded set
    }
    if (key.startsWith("_") || typeof current === "function") {
      const dedupe = `${contract.tag}:${key}`;
      if (!warnedSkippedProps.has(dedupe)) {
        warnedSkippedProps.add(dedupe);
        console.warn(
          key.startsWith("_")
            ? `[tessera] <${contract.tag}> ignoring tsr-props key "${key}": keys starting with "_" are reserved`
            : `[tessera] <${contract.tag}> ignoring tsr-props key "${key}": it would overwrite a method`,
        );
      }
      continue;
    }
    try {
      el[key] = value;
      assigned.add(key);
    } catch (err) {
      console.warn(`[tessera] <${contract.tag}> could not set property "${key}" from tsr-props: ${err?.message ?? err}`);
    }
  }
  // Attribute REPLACED: keys the previous application assigned that the new
  // payload no longer carries must be cleared, not left stale.
  clearAppliedTsrProps(el, contract, applied, assigned);
  // tsr-props may have clobbered or been skipped for any key — only call a
  // real function, never trust `el.requestUpdate` to exist (or stay sane).
  if (typeof el.requestUpdate === "function") el.requestUpdate();
}

/**
 * Clear every key in `applied` that `keep` does not carry, then track `keep`
 * as the new applied set. Plain own properties are deleted (removing the
 * shadowing assignment); accessor-backed keys (e.g. Lit reactive props, which
 * survive `delete`) are forced to `undefined` through the setter so the base
 * class observes the reset.
 */
function clearAppliedTsrProps(el, contract, applied, keep) {
  for (const key of applied) {
    if (keep.has(key)) continue;
    try {
      delete el[key];
    } catch (err) {
      console.warn(`[tessera] <${contract.tag}> could not clear tsr-props property "${key}": ${err?.message ?? err}`);
    }
    if (el[key] !== undefined) {
      try {
        el[key] = undefined;
      } catch (err) {
        console.warn(`[tessera] <${contract.tag}> could not reset tsr-props property "${key}": ${err?.message ?? err}`);
      }
    }
  }
  el.__tesseraAppliedProps = keep;
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
