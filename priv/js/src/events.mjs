/**
 * Events-up helper and case conversion (CONTRACT.md §1).
 *
 * The JS core emits camelCase detail keys; the bridge converts recursively to
 * snake_case right before `Hologram.dispatchAction`, which boxes plain
 * objects into atom-key maps and does no case conversion of its own.
 */

/**
 * Dispatch a composed, bubbling CustomEvent from `el` — the host app never
 * needs to reach into shadow DOM. Returns `dispatchEvent`'s result.
 *
 * @template T
 * @param {HTMLElement} el
 * @param {string} name
 * @param {T} detail
 * @returns {boolean}
 */
export function emit(el, name, detail) {
  return el.dispatchEvent(new CustomEvent(name, { detail, bubbles: true, composed: true }));
}

const SNAKE_RE = /[A-Z]/g;
const CAMEL_RE = /_([a-zA-Z0-9])/g;

function snakeCase(key) {
  return key.replace(SNAKE_RE, (c) => `_${c.toLowerCase()}`);
}

function camelCase(key) {
  return key.replace(CAMEL_RE, (_, c) => c.toUpperCase());
}

/**
 * True for plain `{}`-style objects only: arrays, Dates, Maps, class
 * instances and DOM nodes must pass through untouched (JSON-safety is the
 * author's job; mangling a non-plain object here would only hide the bug).
 */
function isPlainObject(value) {
  if (value === null || typeof value !== "object") return false;
  const proto = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
}

function convertKeysDeep(value, convert) {
  if (Array.isArray(value)) return value.map((v) => convertKeysDeep(v, convert));
  if (isPlainObject(value)) {
    const out = {};
    for (const [key, val] of Object.entries(value)) {
      out[convert(key)] = convertKeysDeep(val, convert);
    }
    return out;
  }
  return value;
}

/**
 * Recursively convert every object key (and every key inside nested arrays /
 * plain objects) from camelCase to snake_case. Non-plain objects are left
 * as-is.
 *
 * @param {any} value
 * @returns {any}
 */
export function snakeKeysDeep(value) {
  return convertKeysDeep(value, snakeCase);
}

/**
 * Recursively convert every object key from snake_case (and kebab-style
 * separators are NOT touched — the contract only deals in `_`) to camelCase.
 * Non-plain objects are left as-is.
 *
 * @param {any} value
 * @returns {any}
 */
export function camelKeysDeep(value) {
  return convertKeysDeep(value, camelCase);
}
