/**
 * The contract action pipeline + state snapshot (EXTENSION-CONTRACT.md §6.2–§6.4).
 *
 * Pure module: no Lit, no DOM, no bridge — everything here runs against plain
 * objects so it is unit-testable in isolation (pipeline.test.mjs) AND inside
 * the element mixin (element.mjs), which supplies `invoke`, `isConnected` and
 * `warn`. Case conversion comes from events.mjs — the SAME code path as the
 * bridge's `snakeKeysDeep` (CONTRACT §1), so params normalize identically on
 * both surfaces (X-20).
 *
 * Decisions implemented here (parity plan §U1/U2/U6, user-confirmed D3):
 *   - snapshot: fresh frozen top-level object, canonical camelCase keys,
 *     non-enumerable snake aliases; nested values shared, never deep-frozen.
 *   - veto: the interceptor's return value becomes the DispatchResult `value`
 *     (§6.4 "becomes the pipeline result").
 *   - stale-drop (async settle after disconnect) reuses `reason: "vetoed"`
 *     with no `value` (U6) — applies no state, emits nothing.
 *   - `ok:true` results carry the POST-transition snapshot as `value` (U1/Q3).
 */

import { snakeKeysDeep, camelKeysDeep, snakeCaseKey, camelCaseKey } from "./events.mjs";

function isThenable(value) {
  return value != null && typeof value.then === "function";
}

/**
 * Fresh frozen state snapshot of `el` (EXTENSION-CONTRACT.md §6.2).
 *
 * For each declared snake key `k` the canonical property is `camel(k)`;
 * `k` itself is attached as a NON-ENUMERABLE own alias mirroring the same
 * value (only when the two differ). Top-level `Object.freeze` only — nested
 * values stay shared references.
 *
 * @param {object} el element (or any object) carrying snake-state properties
 * @param {string[]} stateKeys declared snake_case state key names
 * @returns {Readonly<object>} fresh snapshot
 */
export function makeSnapshot(el, stateKeys) {
  const snap = {};
  const aliases = [];
  for (const key of stateKeys) {
    const canonical = camelCaseKey(key);
    snap[canonical] = el[key];
    if (canonical !== key) aliases.push(key);
  }
  for (const alias of aliases) {
    Object.defineProperty(snap, alias, {
      value: snap[camelCaseKey(alias)],
      enumerable: false,
      writable: false,
      configurable: false,
    });
  }
  return Object.freeze(snap);
}

/**
 * Normalize an action name given in either casing to the canonical snake
 * declaration (D3: Elixir always receives snake_case).
 *
 * @param {string} name
 * @returns {string | null} snake canonical, or null for a non-string
 */
export function normalizeActionName(name) {
  if (typeof name !== "string" || name.length === 0) return null;
  return snakeCaseKey(name);
}

/**
 * Reject function-valued params ANYWHERE in the payload (plain-object/array
 * walk) — data-only dispatch (D3). Non-plain objects pass through unscanned,
 * matching snakeKeysDeep's stance.
 */
function hasFunctionValue(value) {
  if (typeof value === "function") return true;
  if (Array.isArray(value)) return value.some(hasFunctionValue);
  if (value !== null && typeof value === "object") {
    const proto = Object.getPrototypeOf(value);
    if (proto === Object.prototype || proto === null) {
      return Object.values(value).some(hasFunctionValue);
    }
  }
  return false;
}

/**
 * Normalize dispatch/override params (EXTENSION-CONTRACT.md §6.3):
 *   - non-object input is treated as `{}`;
 *   - top-level `_`-prefixed reserved keys are STRIPPED with a warn (the
 *     tsr-props reserved-key guard, applied to params);
 *   - function values (at any depth) are REJECTED — `{ok: false}`;
 *   - remaining keys are deep-normalized to snake_case (either input casing).
 *
 * @param {object | undefined | null} params
 * @param {(msg: string) => void} warn
 * @returns {{ok: true, snake: object} | {ok: false, message: string}}
 */
export function normalizeParams(params, warn = () => {}) {
  if (params === undefined || params === null) return { ok: true, snake: {} };
  if (typeof params !== "object" || Array.isArray(params)) {
    return { ok: false, message: `action params must be a plain object, got ${typeof params}` };
  }
  let cleaned = params;
  for (const key of Object.keys(params)) {
    if (key.startsWith("_")) {
      warn(`ignoring action params key "${key}": keys starting with "_" are reserved`);
      if (cleaned === params) cleaned = { ...params };
      delete cleaned[key];
    }
  }
  if (hasFunctionValue(cleaned)) {
    return { ok: false, message: "action params must be data-only (function values are rejected)" };
  }
  return { ok: true, snake: snakeKeysDeep(cleaned) };
}

/**
 * Outcome union produced by `runPipeline` (the element maps it to a
 * DispatchResult and performs the state commit + events):
 *   {status:"applied", value}  — the action ran; `value` is its raw return
 *                                (the next-state object, or null/undefined)
 *   {status:"vetoed", value}   — some stage cancelled; `value` = its return
 *   {status:"error", error, applied?, invokeValue?}
 *                            — a stage threw / params rejected; `applied: true`
 *                              when the action HAD already run (throw after
 *                              `next` — the element still commits it)
 *   {status:"stale"}         — async settle after disconnect (U6): apply
 *                              nothing, emit nothing
 *
 * @returns {object | Promise<object>} sync outcome, or a Promise when any
 *          stage (or the downstream chain) was async.
 */
export function runPipeline({ interceptors = [], invoke, params, ev = null, isConnected = () => true, warn = () => {} }) {
  const normalized = normalizeParams(params, warn);
  if (!normalized.ok) {
    return { status: "error", error: new Error(`tessera: ${normalized.message}`) };
  }

  const stages = interceptors;
  const n = stages.length;
  // Mutable pipeline state — outcomes flow through it, never through the
  // interceptors' return values (a stage may return anything it likes after
  // calling next; only the VETOING stage's return carries into the result).
  const state = { invoked: false, invokeValue: undefined, error: null, vetoed: false, vetoValue: undefined };

  // Returns undefined (sync path) or a Promise (async chain). Errors are
  // always CAPTURED into state.error, never re-thrown out of the chain —
  // dispatchAction's async shape must not reject (internal invocations catch
  // for free; page scripts get `{ok:false, reason:"error"}`).
  function runStage(i, snakeP) {
    if (i === n) {
      state.invoked = true;
      try {
        state.invokeValue = invoke(snakeP, ev);
      } catch (err) {
        state.error ??= err;
      }
      return undefined;
    }
    let nextReturn;
    let nextCalled = false;
    const next = (override) => {
      nextCalled = true;
      if (override !== undefined && override !== null) {
        const norm = normalizeParams(override, warn);
        if (!norm.ok) {
          state.error ??= new Error(`tessera: ${norm.message}`);
          return undefined;
        }
        snakeP = norm.snake;
      }
      nextReturn = runStage(i + 1, snakeP);
      return nextReturn;
    };

    try {
      const camelP = camelKeysDeep(snakeP);
      const ret = stages[i](camelP, next);
      if (isThenable(ret)) {
        return ret.then(
          (resolved) => {
            if (!nextCalled && !state.vetoed) {
              state.vetoed = true;
              state.vetoValue = resolved;
            }
            return isThenable(nextReturn) ? nextReturn.then(() => undefined) : undefined;
          },
          (err) => {
            state.error ??= err;
            // A stage rejecting AFTER next must still await the downstream
            // chain ("cannot roll back" — the action may already have run).
            return isThenable(nextReturn) ? nextReturn.then(() => undefined) : undefined;
          },
        );
      }
      if (!nextCalled) {
        state.vetoed = true;
        state.vetoValue = ret;
        return undefined;
      }
      return isThenable(nextReturn) ? nextReturn.then(() => undefined) : undefined;
    } catch (err) {
      // Threw BEFORE next (or synchronously after calling an already-finished
      // next): downstream stages are unwound by the throw and never run.
      state.error ??= err;
      return undefined;
    }
  }

  function finalize(asyncSettled) {
    // Stale-drop (U6): an ASYNC resolution that lands after the element
    // disconnected applies no state and emits NOTHING (no tsr-state-change,
    // no tsr-action-error either — "no state/no event").
    if (asyncSettled && !isConnected()) return { status: "stale" };
    if (state.error !== null) {
      // A stage that threw AFTER `next` cannot roll back — if the action
      // already ran, its transition still commits (the element applies
      // `invokeValue`), while the error still surfaces (§6.4 Errors).
      if (state.invoked) {
        return { status: "error", error: state.error, applied: true, invokeValue: state.invokeValue };
      }
      return { status: "error", error: state.error };
    }
    if (state.invoked) return { status: "applied", value: state.invokeValue };
    if (state.vetoed) return { status: "vetoed", value: state.vetoValue };
    // No stage threw, none invoked, none returned a value we could record as a
    // veto (e.g. a stage swallowed next into a never-settling promise): treat
    // as cancelled — honest "nothing happened", no state applied.
    return { status: "vetoed", value: undefined };
  }

  const root = runStage(0, normalized.snake);
  if (isThenable(root)) {
    return root.then(() => finalize(true), () => finalize(true));
  }
  return finalize(false);
}
