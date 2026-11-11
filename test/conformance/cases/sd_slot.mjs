// Family SD — Shadow DOM slots (lit-parity §4.1, SD-01…SD-03).
// Slot rendering is exercised by compiled-element / Hologram fixtures; the
// Tier-2 slot + forms brief (3e) owns the parity. Pending in the scaffold.

import {pendingCase} from "../support/case.mjs";

export const cases = [
  pendingCase({id: "SD-01", family: "SD", fast: true, title: "default slot accepts a light-DOM child", reason: "slot fixture owed (3e Tier 2 / compiled-element Tier 1)"}),
  pendingCase({id: "SD-02", family: "SD", fast: true, title: "named slot routes slot=\"x\" children", reason: "slot fixture owed (3e)"}),
  pendingCase({id: "SD-03", family: "SD", fast: true, title: "slot fallback renders when no child is slotted", reason: "slot fixture owed (3e)"}),
];