// Family FM — Forms (placeholder; lit-parity §4 extension, brief 4b).
// Form participation is brief 2f (Tier 1 formAssociated) / 3e (Tier 2 slots +
// forms). IDs here are PROVISIONAL scaffold placeholders — 2f/3e own the final
// case set and may renumber. All pending until those briefs land.

import {pendingCase} from "../support/case.mjs";

export const cases = [
  pendingCase({id: "FM-01", family: "FM", fast: true, title: "formAssociated custom element participates in a form", reason: "formAssociated lands with brief 2f (Tier 1) / 3e (Tier 2); provisional id"}),
  pendingCase({id: "FM-02", family: "FM", fast: true, title: "ElementInternals exposes the element value to the form", reason: "form value participation lands with brief 3e; provisional id"}),
  pendingCase({id: "FM-03", family: "FM", fast: false, title: "form submit/reset reaches the element", reason: "form submit/reset behavior lands with brief 3e; provisional id"}),
];