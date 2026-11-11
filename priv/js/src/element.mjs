/**
 * `TesseraElement(Base, contract, extension?)` — the contract-driven element
 * mixin (CONTRACT.md §4) plus the extension surface (EXTENSION-CONTRACT.md §6:
 * `el.state`, `onAction`, `dispatchAction`, `tsr-state-change`,
 * `tsr-action-error`). Works over `HTMLElement` AND `LitElement`: no Lit
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
 *   - on `disconnectedCallback` runs those cleanups,
 *   - when an `extension` descriptor is given (`{state, actions,
 *     internalActions}` — emitted by the element codegen from the spec):
 *     the contract §6 state snapshot + action pipeline.
 */

import { registerEvents } from "./bridge.mjs";
import { behaviorsFor } from "./behaviors.mjs";
import { emit, camelCaseKey } from "./events.mjs";
import { makeSnapshot, normalizeActionName, runPipeline } from "./pipeline.mjs";

const TSR_PROPS_ATTR = "tsr-props";

// Warn-once set for skipped tsr-props keys, pinned to `globalThis` under a
// `Symbol.for` key — the SAME singleton design as the bridge and `defineOnce`:
// Hologram's per-page bundles routinely load two copies of this module, and
// "warn once" must hold ACROSS copies, not per module instance.
const WARNED_SKIPPED_PROPS_KEY = Symbol.for("tessera.warned-props");
const warnedSkippedProps = (globalThis[WARNED_SKIPPED_PROPS_KEY] ??= new Set());

// Warn-once set for interceptors registered against `internal:`-annotated
// actions (EXTENSION-CONTRACT.md §6.4/D2 — advisory, NEVER blocks). Same
// singleton design as above; keyed by `<tag>:<snake-action>`.
const WARNED_INTERNAL_KEY = Symbol.for("tessera.warned-internal");
const warnedInternalActions = (globalThis[WARNED_INTERNAL_KEY] ??= new Set());

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
 * @param {{state?: string[], actions?: string[], internalActions?: string[]} | null} [extension]
 *   the EXTENSION-CONTRACT.md §6 descriptor (snake_case state keys; ALL
 *   declared action names — open surface, D2; the `internal:` subset is the
 *   advisory warn set). Without it the mixed class keeps its §4 shape.
 * @returns {Function} the mixed class.
 */
export function TesseraElement(Base, contract, extension = null) {
  const attrDefs = Array.isArray(contract?.attrs) ? contract.attrs : [];
  const eventNames = (Array.isArray(contract?.events) ? contract.events : [])
    .map((e) => e?.name)
    .filter((n) => typeof n === "string");
  const tag = contract?.tag ?? "(unknown tag)";
  const attrMap = new Map();
  for (const def of attrDefs) {
    if (def && typeof def.name === "string") attrMap.set(def.name, def);
  }

  // -- extension surface (EXTENSION-CONTRACT.md §6) --------------------------
  const stateKeys = (Array.isArray(extension?.state) ? extension.state : [])
    .filter((k) => typeof k === "string");
  const actionNames = (Array.isArray(extension?.actions) ? extension.actions : [])
    .filter((n) => typeof n === "string");
  const actionSet = new Set(actionNames);
  const internalSet = new Set(
    (Array.isArray(extension?.internalActions) ? extension.internalActions : []).filter(
      (n) => typeof n === "string",
    ),
  );
  const warnTagged = (msg) => console.warn(`[tessera] <${tag}> ${msg}`);

  return class extends Base {
    // Contract statics (§6.1): identity + the OPEN action surface (D2) —
    // every declared name, snake canonical, internal ones included.
    static tesseraTag = tag;
    static tesseraContractVersion = contract?.version ?? 1;
    static tesseraActions = [...actionNames];

    /**
     * Fresh FROZEN camelCase snapshot (§6.2, U2/Q5): canonical camel keys
     * enumerable, declared snake keys attached as NON-ENUMERABLE aliases,
     * top-level freeze only. `{}` (frozen) when the component declares no
     * state. A fresh object per access — never cache it.
     */
    get state() {
      return makeSnapshot(this, stateKeys);
    }

    /**
     * Register an action interceptor (§6.4). `name` in either casing;
     * registration is per instance, survives disconnect/reconnect, and
     * returns an unsubscribe function. Registering against an
     * `internal:`-annotated action fires a dev-mode warn-once per tag+action
     * and STILL WORKS (advisory, D2/§10).
     *
     * @param {string} name
     * @param {(params: object, next: Function) => unknown} interceptor
     * @returns {() => void}
     */
    onAction(name, interceptor) {
      if (typeof interceptor !== "function") {
        throw new TypeError(`tessera onAction("${String(name)}") requires an interceptor function`);
      }
      const snake = normalizeActionName(name) ?? String(name);
      if (internalSet.has(snake)) {
        const dedupe = `${tag}:${snake}`;
        if (!warnedInternalActions.has(dedupe)) {
          warnedInternalActions.add(dedupe);
          warnTagged(
            `interceptor registered against internal action "${snake}" — the internal: ` +
              `annotation is advisory (EXTENSION-CONTRACT.md §6.4); the interception works`,
          );
        }
      }
      const registry = (this.__tesseraInterceptors ??= new Map());
      const list = registry.get(snake) ?? [];
      list.push(interceptor);
      registry.set(snake, list);
      return () => {
        const current = registry.get(snake);
        if (!current) return;
        const idx = current.indexOf(interceptor);
        if (idx >= 0) current.splice(idx, 1);
      };
    }

    /**
     * The ONLY sanctioned invocation path for page scripts (§6.3). Returns a
     * sync `DispatchResult` or a `Promise<DispatchResult>` when the pipeline
     * goes async — callers MUST treat both shapes as possible.
     *
     * @param {string} name action name, either casing
     * @param {object} [params] data-only params, either casing per key
     */
    dispatchAction(name, params) {
      return this.__tesseraDispatch(name, params, null);
    }

    /**
     * Shared pipeline entry — `dispatchAction` (external, ev = null) and the
     * generated `__tesseraRunAction` (template `$click`, carries the DOM
     * event) both route through it, so internal invocations are interceptable
     * under the same rules (§6.4). Not contract: `__`-prefixed internal.
     */
    __tesseraDispatch(name, params, ev) {
      const snake = normalizeActionName(name);
      if (snake === null || !actionSet.has(snake)) {
        warnTagged(`has no action "${String(name)}"`);
        return { ok: false, reason: "unknown-action" };
      }
      const interceptors = this.__tesseraInterceptors?.get(snake) ?? [];
      const outcome = runPipeline({
        interceptors: [...interceptors],
        invoke: (p, e) => this[`__action_${snake}`]?.(p, e),
        params,
        ev,
        isConnected: () => this.__tesseraConnected === true,
        warn: warnTagged,
      });
      if (outcome != null && typeof outcome.then === "function") {
        return outcome.then((settled) => this.__tesseraFinish(snake, settled));
      }
      return this.__tesseraFinish(snake, outcome);
    }

    /**
     * Map a pipeline outcome to a DispatchResult, committing transitions:
     * apply via the generated `__tesseraSetState`, compute the changed keys,
     * `requestUpdate` (render SCHEDULED), then fire `tsr-state-change` —
     * subscribers awaiting `el.updateComplete` see the new DOM (§6.2).
     */
    __tesseraFinish(snake, outcome) {
      switch (outcome.status) {
        case "stale":
          // U6: async settle after disconnect — no state, no event.
          // Reuse reason "vetoed" (no new enum value in the contract).
          return { ok: false, reason: "vetoed" };
        case "vetoed":
          return { ok: false, reason: "vetoed", value: outcome.value };
        case "error": {
          const message = outcome.error?.message ?? String(outcome.error);
          if (outcome.applied) this.__tesseraCommit(snake, outcome.invokeValue);
          emit(this, "tsr-action-error", { action: snake, message, error: outcome.error });
          return { ok: false, reason: "error" };
        }
        case "applied":
        default: {
          const value = this.__tesseraCommit(snake, outcome.value);
          return { ok: true, value };
        }
      }
    }

    /**
     * Apply a committed transition + fire `tsr-state-change` (one event per
     * transition, camelCase changed keys, post-transition snapshot). The
     * result's `value` = that snapshot (U1/Q3).
     */
    __tesseraCommit(snake, next) {
      // A "transition" only exists when the action produced a next-state
      // object. Handlers returning null/undefined applied nothing — no
      // requestUpdate, no event (a thrown action's half-run lands here too).
      if (next == null || typeof next !== "object") return makeSnapshot(this, stateKeys);
      const before =
        typeof this.__tesseraState === "function"
          ? this.__tesseraState()
          : Object.fromEntries(stateKeys.map((k) => [k, this[k]]));
      if (next != null && typeof next === "object") {
        if (typeof this.__tesseraSetState === "function") this.__tesseraSetState(next);
        else for (const k of Object.keys(next)) this[k] = next[k];
      }
      const changed = stateKeys.filter((k) => !Object.is(before?.[k], this[k]));
      this.requestUpdate?.();
      const snapshot = makeSnapshot(this, stateKeys);
      emit(this, "tsr-state-change", {
        keys: changed.map((k) => camelCaseKey(k)),
        state: snapshot,
        action: snake,
      });
      return snapshot;
    }

    constructor(...args) {
      super(...args);
      /** @type {Function[] | null} cleanups returned by behaviors */
      this.__tesseraCleanups = null;
      // Connection tracking for the pipeline's stale-drop (§6.4/U6).
      this.__tesseraConnected = false;
      // Boolean attrs ride by presence/absence — an absent boolean is false,
      // not undefined (CONTRACT.md §3).
      for (const def of attrDefs) {
        if (def.type === "boolean") {
          const key = def.key ?? def.name;
          if (this[key] === undefined) this[key] = false;
        }
      }
    }

    static get observedAttributes() {
      // `super.observedAttributes` binds `this` to THIS class (the mixin
      // result), so for a LitElement base it runs Lit's finalize-on-read and
      // returns this class's own reactive-attribute list; for a plain
      // HTMLElement base it is simply undefined.
      const own = super.observedAttributes;
      return [...new Set([...(Array.isArray(own) ? own : []), ...attrMap.keys(), TSR_PROPS_ATTR])];
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
      this.__tesseraConnected = true;
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
      this.__tesseraConnected = false;
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
