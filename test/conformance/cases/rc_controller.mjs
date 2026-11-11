// Family RC — Reactive controllers (placeholder; lit-parity §4 extension, 4b).
// addController / hostUpdate / hostUpdated are accepted-with-hatch (4a ballot,
// rows #126-135): tessera's behaviors.add + onAction interceptor pipeline are
// the sanctioned alternative to Lit reactive controllers. Marked accordingly
// — never forced green. IDs are provisional scaffold placeholders.

import {pendingCase} from "../support/case.mjs";

export const cases = [
  pendingCase({id: "RC-01", family: "RC", fast: false, title: "addController runs hostConnected/hostDisconnected", reason: "reactive controllers accepted-with-hatch (4a); behaviors.add is the alternative", disposition: "accepted-with-hatch"}),
  pendingCase({id: "RC-02", family: "RC", fast: false, title: "hostUpdate runs before the host updates", reason: "reactive controllers accepted-with-hatch (4a); onAction interceptors are the alternative", disposition: "accepted-with-hatch"}),
  pendingCase({id: "RC-03", family: "RC", fast: false, title: "hostUpdated runs after the host updates", reason: "reactive controllers accepted-with-hatch (4a); onAction interceptors are the alternative", disposition: "accepted-with-hatch"}),
];