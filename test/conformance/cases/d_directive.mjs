// Family D — Built-in directives (lit-parity §4.1, D-01…D-07).
// classMap/styleMap/ifDefined are brief 1d; when/choose compile from the
// template DSL; repeat/ref are accepted-with-hatch (4a ballot). All need
// compiled-element fixtures, so the whole family is pending in the scaffold.

import {pendingCase} from "../support/case.mjs";

export const cases = [
  pendingCase({id: "D-01", family: "D", fast: true, title: "classMap applies a dynamic class map", reason: "brief 1d classMap + compiled-element fixture owed"}),
  pendingCase({id: "D-02", family: "D", fast: true, title: "styleMap applies a dynamic style map", reason: "brief 1d styleMap + compiled-element fixture owed"}),
  pendingCase({id: "D-03", family: "D", fast: true, title: "when directive selects the correct template", reason: "compiled-element template fixture owed (1d/3c)"}),
  pendingCase({id: "D-04", family: "D", fast: false, title: "choose directive selects the matching case", reason: "compiled-element template fixture owed (1d/3c)"}),
  pendingCase({id: "D-05", family: "D", fast: false, title: "repeat with keys reorders DOM nodes", reason: "repeat directive is accepted-with-hatch (4a); host-side keyed rendering is the alternative", disposition: "accepted-with-hatch"}),
  pendingCase({id: "D-06", family: "D", fast: true, title: "ifDefined omits the attribute when undefined", reason: "brief 1d ifDefined + compiled-element fixture owed"}),
  pendingCase({id: "D-07", family: "D", fast: false, title: "ref directive exposes the rendered element", reason: "ref directive is accepted-with-hatch (4a); host-side query is the alternative", disposition: "accepted-with-hatch"}),
];