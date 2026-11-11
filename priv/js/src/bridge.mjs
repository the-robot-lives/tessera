/**
 * The document-level event bridge (CONTRACT.md §4).
 *
 * A singleton at `globalThis[Symbol.for("tessera.bridge")]` holding ONE
 * capture-phase `document` listener per registered event name. Hologram
 * bundles every `js_import`'d module into each page's esbuild bundle, so two
 * module copies of this file routinely run on the same page; all mutable
 * state lives on the singleton so duplicate copies share one listener per
 * event and one dispatch per fired event.
 *
 * When a registered event fires:
 *   1. Resolve the host element (`event.target` after shadow retargeting;
 *      if a nested element re-dispatched the event, fall back to scanning
 *      `event.composedPath()` for the first element carrying `data-tsr-on`
 *      whose tag is a registered contract tag).
 *   2. Parse its `data-tsr-on` (`event:action@target;…`) and find the entry
 *      for `event.type`.
 *   3. Call `globalThis.Hologram.dispatchAction(action, target,
 *      snakeKeysDeep(event.detail ?? {}))`.
 *
 * No matching entry, or no `globalThis.Hologram`, ⇒ no-op — the plain-HTML /
 * React case never errors.
 */

import { snakeKeysDeep } from "./events.mjs";

const BRIDGE_KEY = Symbol.for("tessera.bridge");

/**
 * Parse a `data-tsr-on` attribute value into `Map<event, {action, target}>`.
 * Grammar (CONTRACT.md §3): `entry (";" entry)*`, `entry = event ":" action
 * "@" target`, `target ∈ page | layout | <cid>`. Tolerant by design: empty
 * input yields an empty map; malformed entries are skipped with a
 * `console.warn` and never throw.
 *
 * @param {string | null | undefined} str
 * @returns {Map<string, { action: string, target: string }>}
 */
export function parseTsrOn(str) {
  const out = new Map();
  if (typeof str !== "string" || str.length === 0) return out;
  for (const rawEntry of str.split(";")) {
    // Entry-level trim is redundant with the per-slice trims of event/action/
    // target below — but it keeps the empty-entry skip SILENT (a whitespace-
    // only entry would otherwise fall through to the malformed-entry warn).
    const entry = rawEntry.trim();
    if (entry.length === 0) continue;
    const colon = entry.indexOf(":");
    const at = entry.lastIndexOf("@");
    // The trailing-`@` guard is redundant with the `!target` emptiness check
    // below (every entry this rejects is rejected there too) — kept so the
    // malformed-shape test reads directly.
    if (colon <= 0 || at < colon + 1 || at === entry.length - 1) {
      console.warn(`[tessera] skipping malformed data-tsr-on entry: "${entry}"`);
      continue;
    }
    const event = entry.slice(0, colon).trim();
    const action = entry.slice(colon + 1, at).trim();
    const target = entry.slice(at + 1).trim();
    if (!event || !action || !target) {
      console.warn(`[tessera] skipping malformed data-tsr-on entry: "${entry}"`);
      continue;
    }
    out.set(event, { action, target });
  }
  return out;
}

function looksLikeElement(node) {
  return node !== null && typeof node === "object" && typeof node.getAttribute === "function";
}

/**
 * Find the element whose `data-tsr-on` carries an entry for this event type.
 * `event.target` wins after shadow retargeting; otherwise scan the composed
 * path outward for the first contract-registered element carrying a mapping.
 */
function findBinding(event, knownTags) {
  const candidates = [event.target, ...(event.composedPath?.() ?? [])];
  for (const node of candidates) {
    if (!looksLikeElement(node)) continue;
    const raw = node.getAttribute("data-tsr-on");
    if (!raw) continue;
    const isDirectTarget = node === event.target;
    // A re-dispatched event can bubble from a nested element inside the host;
    // only honour hosts whose tag belongs to a registered contract, so an
    // arbitrary ancestor with a stale mapping can never hijack the event.
    if (!isDirectTarget && !knownTags.has(node.localName)) continue;
    const binding = parseTsrOn(raw).get(event.type);
    if (binding) return binding;
  }
  return null;
}

function makeListener(bridge) {
  return (event) => {
    const binding = findBinding(event, bridge.tags);
    if (!binding) return; // no mapping ⇒ no-op, never an error
    const hologram = globalThis.Hologram;
    if (!hologram || typeof hologram.dispatchAction !== "function") return; // plain-HTML / React case
    const params = snakeKeysDeep(event.detail ?? {});
    hologram.dispatchAction(binding.action, binding.target, params);
  };
}

/**
 * Get (or lazily create) the bridge singleton. Safe to call from any number
 * of module copies: state is keyed off the global symbol, so every copy sees
 * the same listener map, tag set and behaviors registry.
 */
export function getBridge() {
  if (globalThis[BRIDGE_KEY]) return globalThis[BRIDGE_KEY];
  const bridge = {
    /** @type {Map<string, EventListener>} event name → document listener */
    listeners: new Map(),
    /** @type {Set<string>} contract tags seen via registerEvents */
    tags: new Set(),
    /** @type {Map<string, Set<Function>>} tag → behavior fns (behaviors.mjs) */
    behaviors: new Map(),
    /**
     * @type {Map<string, Array<{mixin: Function, depth: number, priority: number, module: string, seq: number}>}}
     * tag → queued tag-takeover mixins (extend.mjs, EXTENSION-CONTRACT.md §5.9),
     * consumed by defineOnce at the tag's first definition. Bridge-held so
     * duplicate module copies share ONE queue.
     */
    extensions: new Map(),
    /** Registration-order counter for the extensions queue (§6.4 onion tie). */
    extendSeq: 0,
    registerEvents,
    parseTsrOn,
  };

  function registerEvents(names, tag) {
    if (tag) bridge.tags.add(tag);
    for (const name of names ?? []) {
      if (typeof name !== "string" || bridge.listeners.has(name)) continue;
      const listener = makeListener(bridge);
      document.addEventListener(name, listener, { capture: true });
      bridge.listeners.set(name, listener);
    }
  }

  globalThis[BRIDGE_KEY] = bridge;
  return bridge;
}

/**
 * Register contract event names with the bridge (one capture-phase document
 * listener per NEW name — idempotent across duplicate module copies).
 * `tag`, when given, marks the contract as known so the composedPath
 * fallback can resolve hosts inside nested/re-dispatched events.
 *
 * @param {string[]} names
 * @param {string} [tag]
 */
export function registerEvents(names, tag) {
  getBridge().registerEvents(names, tag);
}
