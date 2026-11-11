// Family S — Styles (lit-parity §4.1, S-01…S-06).
// The styles DSL landed with brief 1b (composed static styles + theming
// contract); these cases need compiled-element style fixtures to assert the
// rendered CSS, so they are pending until that fixture wiring lands.

import {pendingCase} from "../support/case.mjs";

export const cases = [
  pendingCase({id: "S-01", family: "S", fast: true, title: ":host style applies to the host", reason: "styles DSL landed (1b); compiled-element style fixture owed"}),
  pendingCase({id: "S-02", family: "S", fast: true, title: ":host([attr]) conditional style", reason: "styles DSL landed (1b); compiled-element style fixture owed"}),
  pendingCase({id: "S-03", family: "S", fast: true, title: "::slotted() styles slotted children", reason: "compiled-element style + slot fixture owed (1b/3e)"}),
  pendingCase({id: "S-04", family: "S", fast: true, title: "CSS custom property resolves from the parent", reason: "theming contract landed (1b); compiled-element fixture owed"}),
  pendingCase({id: "S-05", family: "S", fast: false, title: "shared CSSResult module applies", reason: "shared styles landed (1b); compiled-element fixture owed"}),
  pendingCase({id: "S-06", family: "S", fast: false, title: "static styles array composes all entries", reason: "composed styles landed (1b); compiled-element fixture owed"}),
];