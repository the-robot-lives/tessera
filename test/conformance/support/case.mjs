// Conformance case schema — the single source of behavior truth for the
// tessera parity suite (docs/notes/lit-parity.md §4 + EXTENSION-CONTRACT §9).
//
// A case is a BEHAVIOR definition, not a runner script (§4.2). It exports
// `{id, family, fast, title, status, run(mount, expect)}` and is executed by
// each tier's runner adapter:
//
//   * Tier 1 — js/test/conformance.tier1.test.mjs (Web Test Runner)
//   * Tier 2 — demo/e2e/src/e2e/conformance_tier2.cy.ts (Cypress,
//              Hologram-in-element harness with init wait)
//
// `mount(spec)` and `expect` are SUPPLIED BY THE ADAPTER — a case never imports
// a runner, a fixture class, or a tier runtime. The mount handle contract both
// adapters satisfy is documented in test/conformance/README.md.
//
// HONESTY RULE (brief 4b): a case for an unimplemented feature is `pending`,
// never green. `pendingCase` carries a reason and (optionally) a disposition
// (`unimplemented` | `accepted-with-hatch` | `proven-or-accepted`). Adapters
// report pending cases as skipped; they can never pass. A case whose behavior
// is implemented but whose tier adapter/fixture is not yet wired is reported
// by that adapter as adapter-pending (see the adapter SUPPORTED set) — also
// never green.

/** Known family prefixes. C/T/D/S/SD/E/CT = lit-parity §4.1 (the original 45);
 *  LC/FM/RC/SSR = lifecycle/forms/controllers/SSR placeholders; X = the
 *  extension-contract family (EXTENSION-CONTRACT §9, X-01…X-21). */
export const FAMILIES = ["C", "T", "D", "S", "SD", "E", "CT", "LC", "FM", "RC", "SSR", "X"];

const ID_RE = /^([A-Z]+)-(\d{2})$/;

function validateBase({id, family, fast, title}) {
  const m = ID_RE.exec(id ?? "");
  if (!m) throw new Error(`conformance: bad case id "${id}" (expected FAMILY-NN)`);
  if (m[1] !== family) throw new Error(`conformance: id "${id}" does not match family "${family}"`);
  if (!FAMILIES.includes(family)) throw new Error(`conformance: unknown family "${family}"`);
  if (typeof fast !== "boolean") throw new Error(`conformance: case "${id}" fast must be boolean`);
  if (typeof title !== "string" || title.length === 0) {
    throw new Error(`conformance: case "${id}" needs a title`);
  }
}

/**
 * An implemented, behavior-defining case. `run(mount, expect)` is async and
 * uses only the adapter-supplied mount handle + chai-style `expect`.
 * @param {{id:string, family:string, fast:boolean, title:string, run:Function}} spec
 */
export function defineCase(spec) {
  validateBase(spec);
  if (typeof spec.run !== "function") {
    throw new Error(`conformance: implemented case "${spec.id}" needs a run(mount, expect) function`);
  }
  return {
    id: spec.id,
    family: spec.family,
    fast: spec.fast,
    title: spec.title,
    status: "implemented",
    reason: null,
    disposition: null,
    run: spec.run,
  };
}

/**
 * A case whose feature is not implemented (or not accepted as closed). It is
 * structurally incapable of passing: it carries no run function.
 * @param {{id:string, family:string, fast:boolean, title:string, reason:string, disposition?:string}} spec
 */
export function pendingCase(spec) {
  validateBase(spec);
  if (typeof spec.reason !== "string" || spec.reason.length === 0) {
    throw new Error(`conformance: pending case "${spec.id}" needs a reason`);
  }
  return {
    id: spec.id,
    family: spec.family,
    fast: spec.fast,
    title: spec.title,
    status: "pending",
    reason: spec.reason,
    disposition: spec.disposition ?? "unimplemented",
    run: null,
  };
}