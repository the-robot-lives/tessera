/**
 * JS-side extension hook (the preferred extension path — docs/EXTENDING.md).
 *
 * `behaviors.add(tag, fn, opts?)` registers a function that runs on every
 * `connectedCallback` of the contract element registered for `tag`; `fn(el)`
 * may return a cleanup, which runs on `disconnectedCallback`. `add` returns an
 * UNSUBSCRIBE function (EXTENSION-CONTRACT.md §6.5) — calling it removes the
 * registration (idempotent; `behaviors.remove(tag, fn)` still works too).
 * `opts.api` pins the extender's supported extension_api range (§8.4): the
 * pin is checked at CONNECT against the element's `tesseraExtensionApi`
 * static — major mismatch ⇒ warn + SKIP the behavior (never break the
 * element, Q1/U3), minor mismatch ⇒ warn only, no range / unparsable range ⇒
 * no gate.
 *
 * The registry lives on the bridge singleton, so behaviors registered from
 * one module copy are seen by elements loaded from another (Hologram ships
 * one module copy per page bundle).
 */

import { getBridge } from "./bridge.mjs";

/**
 * @param {string} tag
 * @param {(el: HTMLElement) => (void | (() => void))} fn
 * @param {{api?: string}} [opts] `api` = the extender's supported
 *   extension_api range (`"^1.0.0"`, `"~1.2"`, `"1"`, exact semver); checked
 *   at connect (§8.4), NOT here — the tag may have no runtime yet at
 *   registration time.
 * @returns {() => void} unsubscribe
 */
export function behaviorsAdd(tag, fn, opts = {}) {
  if (typeof tag !== "string" || typeof fn !== "function") {
    throw new TypeError("[tessera] behaviors.add(tag, fn) needs a tag string and a function");
  }
  const api = opts?.api ?? null;
  const registry = getBridge().behaviors;
  let set = registry.get(tag);
  if (!set) {
    set = new Set();
    registry.set(tag, set);
  }
  // Re-adding the SAME fn keeps Set semantics (runs once per connect); a
  // later registration refreshes its pin.
  for (const entry of set) {
    if (entry.fn === fn) {
      entry.api = api;
      return makeUnsubscribe(tag, fn);
    }
  }
  set.add({ fn, api });
  return makeUnsubscribe(tag, fn);
}

/**
 * @param {string} tag
 * @param {Function} fn
 */
export function behaviorsRemove(tag, fn) {
  const registry = getBridge().behaviors;
  const set = registry.get(tag);
  if (!set) return;
  for (const entry of set) {
    if (entry.fn === fn) set.delete(entry);
  }
  if (set.size === 0) registry.delete(tag);
}

/** @param {string} tag @returns {Function[]} the registered fns (unwrapped, mixin order) */
export function behaviorsFor(tag) {
  return behaviorsEntriesFor(tag).map((e) => e.fn);
}

/**
 * @param {string} tag
 * @returns {Array<{fn: Function, api: string | null}>} registry ENTRIES in
 *   insertion order — the connect-time pin check (element.mjs §8.4) needs the
 *   `api` pin alongside each fn; `behaviorsFor/1` stays the unwrapped view.
 */
export function behaviorsEntriesFor(tag) {
  const set = getBridge().behaviors.get(tag);
  return set ? [...set] : [];
}

function makeUnsubscribe(tag, fn) {
  let done = false;
  return () => {
    if (done) return; // idempotent
    done = true;
    behaviorsRemove(tag, fn);
  };
}

// -- §8.4 pin check ----------------------------------------------------------

/**
 * Compare a behavior's `api` range against the runtime's extension_api
 * (CONTRACT §8.4, brief 2f). Deliberately SMALL: the pin is a floor + major
 * gate, not a full semver implementation —
 *   - MAJOR differs ⇒ "major" (skip the behavior, U3/Q1: never break the
 *     element over an extender that declared itself incompatible);
 *   - same major, runtime below the range floor ⇒ "minor" (warn only, still
 *     run — a minor-range miss is advisory);
 *   - satisfied ⇒ "ok".
 * Caret (^), tilde (~ / ~>), >= and exact ranges all parse to the same floor;
 * bare "1" / "1.2" mean .0 for the missing segments. An unparsable range ⇒
 * "invalid" (warn + run — a broken pin must not disable an extender
 * silently, but it gates nothing).
 *
 * @param {string} range the extender's declared pin
 * @param {string | undefined} runtimeApi the element's tesseraExtensionApi
 * @returns {"ok" | "minor" | "major" | "invalid"}
 */
export function checkApiPin(range, runtimeApi) {
  const floor = parseApiRange(range);
  const runtime = parseApiRange(runtimeApi);
  if (!floor || !runtime) return "invalid";
  if (floor[0] !== runtime[0]) return "major";
  if (runtime[1] < floor[1] || (runtime[1] === floor[1] && runtime[2] < floor[2])) return "minor";
  return "ok";
}

/** `["^1.2.3" | "~1.2" | ">=1" | "1.2.3", …] → [major, minor, patch] | null` */
function parseApiRange(value) {
  if (typeof value !== "string") return null;
  const m = /^\s*(?:\^|~|~>|>=)?\s*(\d+)(?:\.(\d+))?(?:\.(\d+))?\s*$/.exec(value);
  if (!m) return null;
  return [Number(m[1]), Number(m[2] ?? 0), Number(m[3] ?? 0)];
}

/** Stable namespace exported from `@noizu/tessera-core/behaviors` and `.`. */
export const behaviors = {
  add: behaviorsAdd,
  remove: behaviorsRemove,
  get: behaviorsFor,
};
