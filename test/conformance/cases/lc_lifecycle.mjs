// Family LC — Lifecycle hooks (placeholder; lit-parity §4 extension, brief 4b).
// Defined by brief 1c (Tier 1) / 3c (Tier 2): willUpdate / updated /
// firstUpdated / changedProperties. The hooks are not on develop yet, so every
// case is pending. IDs are the four named in the plan (brief 1c step 5).

import {pendingCase} from "../support/case.mjs";

export const cases = [
  pendingCase({id: "LC-01", family: "LC", fast: true, title: "willUpdate runs before render with changed old-values", reason: "lifecycle hooks land with brief 1c (Tier 1) / 3c (Tier 2)"}),
  pendingCase({id: "LC-02", family: "LC", fast: true, title: "updated runs after each render", reason: "lifecycle hooks land with brief 1c / 3c"}),
  pendingCase({id: "LC-03", family: "LC", fast: true, title: "firstUpdated fires exactly once", reason: "lifecycle hooks land with brief 1c / 3c"}),
  pendingCase({id: "LC-04", family: "LC", fast: true, title: "changedProperties carries old values", reason: "lifecycle hooks land with brief 1c / 3c"}),
];