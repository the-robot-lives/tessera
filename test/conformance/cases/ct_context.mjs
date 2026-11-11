// Family CT — Context (lit-parity §4.1, CT-01…CT-02).
// @lit/context provide/consume is accepted-with-hatch (4a ballot, rows
// #166-172): tessera chooses built-in reactivity + host-side state over a
// context protocol. Kept as pending/accepted, never forced green.

import {pendingCase} from "../support/case.mjs";

export const cases = [
  pendingCase({id: "CT-01", family: "CT", fast: false, title: "context provide/consume within the shadow tree", reason: "@lit/context accepted-with-hatch (4a); host-side state / behaviors are the alternative", disposition: "accepted-with-hatch"}),
  pendingCase({id: "CT-02", family: "CT", fast: false, title: "context subscription re-renders on change", reason: "@lit/context accepted-with-hatch (4a); built-in reactivity is the alternative", disposition: "accepted-with-hatch"}),
];