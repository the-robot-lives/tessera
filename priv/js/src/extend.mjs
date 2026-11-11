/**
 * Tag-takeover extension registry (EXTENSION-CONTRACT.md §5.9 / §6.4, brief 2e).
 *
 * A `customElements` tag CANNOT be redefined, so a JS extender layers onto the
 * DEFINITION, not after it: `extendElement(tag, mixin)` queues a class-mixin
 * beside `defineOnce`; when the tag is first defined, `defineOnce` composes
 * every queued mixin into the SINGLE class it defines. The queue is consumed
 * at that first definition — duplicate bundle copies never double-wrap (and
 * generated takeover layers additionally dedupe by module identity, so two
 * copies of the same `tag: :inherit` module queue the layer once).
 *
 * Ordering is the §5.9 chain, innermost → outermost: dependency `depth` first
 * (lower sits closer to the vendor base), then `priority:` (higher sits
 * further out), then the module name ascending (alphabetically-first closer to
 * the base). A perfect tie falls back to the §6.4 onion rule — FIRST-
 * REGISTERED OUTERMOST. The outermost layer runs first and wins conflicts;
 * inner layers stay silent until the dispatch goes down-chain (real ES
 * `super`), which is exactly why mixins re-wrap: `mixin(Base)` produces
 * `class extends Base { … super.__action_x() … }`, so a layer that never
 * calls down leaves everything below it un-executed.
 *
 * Registering for an ALREADY-DEFINED tag cannot layer onto the class anymore;
 * that is the dev-mode warn, pointing at the sanctioned post-define paths —
 * behaviors (§6.5) and `onAction` interceptors (§6.4).
 *
 * The queue lives on the bridge singleton (the same globalThis trick
 * defineOnce's warn set uses): duplicate module copies share ONE registry.
 */

import {getBridge} from "./bridge.mjs";

// Which `<tag>` post-define registrations have already warned (per document,
// on globalThis — duplicate module copies don't double-warn).
const WARNED_KEY = Symbol.for("tessera.extend.warned");

function warnedTags() {
  let set = globalThis[WARNED_KEY];
  if (!(set instanceof Set)) {
    set = new Set();
    globalThis[WARNED_KEY] = set;
  }
  return set;
}

// Registration order fallback (§6.4): first-registered ends up OUTERMOST, so
// a later registration sorts closer to the base. Monotonic per document via
// the bridge (duplicate copies share it).
function nextSeq(bridge) {
  bridge.extendSeq = (bridge.extendSeq ?? 0) + 1;
  return bridge.extendSeq;
}

/**
 * §5.9 chain comparator, innermost first. Mirror of
 * `Noizu.Tessera.Component.Extension.chain_order/1` on the Elixir side.
 */
function compareLayers(a, b) {
  if (a.depth !== b.depth) return a.depth - b.depth;
  if (a.priority !== b.priority) return a.priority - b.priority;
  if (a.module !== b.module) return a.module < b.module ? -1 : 1;
  // Perfect tie (unlabelled hand-written mixins): first-registered outermost
  // ⇒ later registrations sort closer to the base.
  return b.seq - a.seq;
}

/**
 * Queue `mixin` as a layer of `tag`'s takeover chain. `mixin` maps the next
 * inner constructor to the new outer one — `(Base) => class extends Base {…}`
 * — and MUST NOT call `customElements.define` itself.
 *
 * @param {string} tag
 * @param {(base: CustomElementConstructor) => CustomElementConstructor} mixin
 * @param {{depth?: number, priority?: number, module?: string}} [opts]
 *   chain coordinates (§5.9): `depth` = layers above the vendor base
 *   (codegen sets this from the Elixir `derived_from` spine), `priority` =
 *   the `use …, priority: n` option, `module` = declaring module string
 *   (also the duplicate-copy dedupe key).
 * @returns {boolean} `true` when the layer is queued (or deduped) and will
 *   compose at the tag's (first) definition; `false` when the tag is already
 *   defined — the class can no longer be layered (warned once; layer via
 *   `behaviors()` / `onAction` instead).
 */
export function extendElement(tag, mixin, opts = {}) {
  if (typeof mixin !== "function") {
    throw new TypeError(`[tessera] extendElement("${tag}") requires a mixin function (Base) => class`);
  }
  const bridge = getBridge();
  if ((globalThis ?? {}).customElements?.get(tag)) {
    const warned = warnedTags();
    if (!warned.has(tag)) {
      warned.add(tag);
      console.warn(
        `[tessera] <${tag}> is already defined; extendElement cannot layer onto an existing class — ` +
          `use behaviors() for per-connection behaviour (§6.5) or onAction for pipeline wrapping (§6.4).`,
      );
    }
    return false;
  }
  const queue = bridge.extensions.get(tag) ?? [];
  const module = typeof opts.module === "string" ? opts.module : "";
  // Duplicate bundle copies of one generated layer re-register the SAME module
  // string: keep the first queueing, drop the second (defineOnce's
  // same-ctor-silently-dedupes analogue for registry entries).
  if (module !== "" && queue.some((entry) => entry.module === module)) return true;
  queue.push({
    mixin,
    depth: Number.isInteger(opts.depth) ? opts.depth : 0,
    priority: Number.isInteger(opts.priority) ? opts.priority : 0,
    module,
    seq: nextSeq(bridge),
  });
  bridge.extensions.set(tag, queue);
  return true;
}

/**
 * Take + clear `tag`'s queued mixins, ordered innermost → outermost.
 * Called by `defineOnce` ONLY at the tag's first definition; consumed
 * entries never re-wrap a later duplicate copy (defineOnce returns early
 * once the tag exists).
 *
 * @param {string} tag
 * @returns {Array<(base: CustomElementConstructor) => CustomElementConstructor>}
 */
export function takeExtensionMixins(tag) {
  const bridge = getBridge();
  const queue = bridge.extensions.get(tag);
  if (!queue || queue.length === 0) return [];
  bridge.extensions.delete(tag);
  return queue.slice().sort(compareLayers).map((entry) => entry.mixin);
}
