/**
 * Idempotent, SSR-safe custom-element registration (ported from tobor-kit
 * `web/src/define.ts`). Hologram bundles every `js_import`'d module into each
 * page's esbuild bundle, so an element's definition can execute several times
 * per session (once per bundle that references it). A plain
 * `customElements.define` throws `NotSupportedError` on the second copy and
 * the whole import rejects; `defineOnce` keeps the first definition and warns
 * at most once per tag per document (state shared on `globalThis`, so
 * duplicate module copies don't double-warn) that a duplicate copy was skipped.
 *
 * CONTRACT.md §4: if the tag is taken, warn once and return the existing
 * constructor; otherwise define and return the constructor.
 */

// Which `<tag>` duplicates have already warned lives on globalThis (its own
// symbol, not the bridge — defineOnce must work with no bridge around), so
// the warn-once guarantee holds ACROSS duplicate module copies: Hologram
// bundles each js_import into every page bundle, so two copies of this file
// routinely evaluate on one page, and "at most once per tag" has to mean per
// document, not per module instance.
const WARNED_KEY = Symbol.for("tessera.define.warned");

function warnedTags() {
  let set = globalThis[WARNED_KEY];
  if (!(set instanceof Set)) {
    set = new Set();
    globalThis[WARNED_KEY] = set;
  }
  return set;
}

/**
 * Register `ctor` as `tag` unless the tag is taken (or there is no registry,
 * e.g. SSR / workers — then this is a no-op).
 *
 * @param {string} tag
 * @param {CustomElementConstructor} ctor
 * @returns {CustomElementConstructor | undefined} the constructor that now
 *   owns the tag: `ctor` when freshly defined, the pre-existing one when the
 *   tag was already taken, `undefined` when no `customElements` global exists.
 */
export function defineOnce(tag, ctor) {
  const registry = (globalThis ?? {}).customElements;
  if (!registry) return undefined;
  const existing = registry.get(tag);
  if (existing) {
    // Another copy of the module got here first; its class keeps the tag.
    // Say so once per tag PER DOCUMENT (the warn set is shared via
    // globalThis, so duplicate module copies don't double-warn), because
    // this copy's fixes will not run for <tag>.
    const warned = warnedTags();
    if (existing !== ctor && !warned.has(tag)) {
      warned.add(tag);
      console.warn(`[tessera] <${tag}> is already defined; keeping the existing definition and skipping this copy.`);
    }
    return existing;
  }
  registry.define(tag, ctor);
  return ctor;
}
