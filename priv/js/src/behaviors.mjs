/**
 * JS-side extension hook (the preferred extension path — docs/EXTENDING.md).
 *
 * `behaviors.add(tag, fn)` registers a function that runs on every
 * `connectedCallback` of the contract element registered for `tag`; `fn(el)`
 * may return a cleanup, which runs on `disconnectedCallback`. The registry
 * lives on the bridge singleton, so behaviors registered from one module
 * copy are seen by elements loaded from another (Hologram ships one module
 * copy per page bundle).
 */

import { getBridge } from "./bridge.mjs";

/**
 * @param {string} tag
 * @param {(el: HTMLElement) => (void | (() => void))} fn
 */
export function behaviorsAdd(tag, fn) {
  if (typeof tag !== "string" || typeof fn !== "function") {
    throw new TypeError("[tessera] behaviors.add(tag, fn) needs a tag string and a function");
  }
  const registry = getBridge().behaviors;
  let set = registry.get(tag);
  if (!set) {
    set = new Set();
    registry.set(tag, set);
  }
  set.add(fn);
}

/** @param {string} tag @param {Function} fn */
export function behaviorsRemove(tag, fn) {
  const registry = getBridge().behaviors;
  const set = registry.get(tag);
  if (!set) return;
  set.delete(fn);
  if (set.size === 0) registry.delete(tag);
}

/** @param {string} tag @returns {Function[]} fns registered for `tag` */
export function behaviorsFor(tag) {
  const set = getBridge().behaviors.get(tag);
  return set ? [...set] : [];
}

/** Stable namespace exported from `@noizu/tessera-core/behaviors` and `.`. */
export const behaviors = {
  add: behaviorsAdd,
  remove: behaviorsRemove,
  get: behaviorsFor,
};
