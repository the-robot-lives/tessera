// Conformance registry — aggregates every family's cases into one ordered
// list and validates the scaffold's structural invariants (unique ids, known
// families, implemented cases carry a run function, pending cases carry a
// reason). Imported by BOTH tier adapters; the adapters own which cases they
// can currently execute (their SUPPORTED set) and report the rest as pending.

import {FAMILIES} from "./case.mjs";
import {cases as c} from "../cases/c_component.mjs";
import {cases as t} from "../cases/t_template.mjs";
import {cases as d} from "../cases/d_directive.mjs";
import {cases as s} from "../cases/s_style.mjs";
import {cases as sd} from "../cases/sd_slot.mjs";
import {cases as e} from "../cases/e_event.mjs";
import {cases as ct} from "../cases/ct_context.mjs";
import {cases as lc} from "../cases/lc_lifecycle.mjs";
import {cases as fm} from "../cases/fm_form.mjs";
import {cases as rc} from "../cases/rc_controller.mjs";
import {cases as ssr} from "../cases/ssr_dsd.mjs";
import {cases as x} from "../cases/x_extension.mjs";

export const CASES = [...c, ...t, ...d, ...s, ...sd, ...e, ...ct, ...lc, ...fm, ...rc, ...ssr, ...x];

// Structural validation — throws at import time if the scaffold is malformed.
const seen = new Set();
for (const k of CASES) {
  if (seen.has(k.id)) throw new Error(`conformance: duplicate case id "${k.id}"`);
  seen.add(k.id);
  if (!FAMILIES.includes(k.family)) throw new Error(`conformance: unknown family "${k.family}"`);
  if (k.status === "implemented" && typeof k.run !== "function") {
    throw new Error(`conformance: implemented case "${k.id}" has no run function`);
  }
  if (k.status === "pending" && (typeof k.reason !== "string" || k.run !== null)) {
    throw new Error(`conformance: pending case "${k.id}" must carry a reason and no run function`);
  }
}

/** Behavior-defining core subset (the @fast lane). */
export const FAST_CASES = CASES.filter((k) => k.fast);

/** Cases for one family prefix. */
export function byFamily(family) {
  return CASES.filter((k) => k.family === family);
}

/** Honest accounting: implemented vs pending, and pending dispositions. */
export function tally() {
  const implemented = CASES.filter((k) => k.status === "implemented").length;
  const pending = CASES.length - implemented;
  const dispositions = {};
  for (const k of CASES) {
    if (k.status !== "pending") continue;
    dispositions[k.disposition] = (dispositions[k.disposition] ?? 0) + 1;
  }
  return {total: CASES.length, implemented, pending, dispositions};
}