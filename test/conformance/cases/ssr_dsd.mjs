// Family SSR — DSD / hydration (placeholder; lit-parity §4 extension, brief 4b).
// Gated by brief 4c (proven-or-accepted). If the SSR/DSD spike proves the
// behavior, these cases flip to implemented; if it is accepted as a documented
// gap, they stay pending with disposition proven-or-accepted. NEVER a release
// blocker (plan U8). IDs are provisional scaffold placeholders.

import {pendingCase} from "../support/case.mjs";

export const cases = [
  pendingCase({id: "SSR-01", family: "SSR", fast: false, title: "declarative shadow DOM renders on the server", reason: "gated by brief 4c SSR/DSD spike (proven-or-accepted)", disposition: "proven-or-accepted"}),
  pendingCase({id: "SSR-02", family: "SSR", fast: false, title: "client hydration adopts server-rendered DSD", reason: "gated by brief 4c SSR/DSD spike (proven-or-accepted)", disposition: "proven-or-accepted"}),
  pendingCase({id: "SSR-03", family: "SSR", fast: false, title: "framework SSR integration renders the element", reason: "gated by brief 4c; matrix #164 (Tier 2 framework SSR) not exercised", disposition: "proven-or-accepted"}),
];