// Family T — Templates (lit-parity §4.1, T-01…T-09).
//
// T-01 (child expression) runs against the shared "counter" fixture on both
// tiers. The remaining template expressions are exercised by compiled-element
// fixtures and land with the template/DSL briefs (1d / 3c); they are pending.

import {defineCase, pendingCase} from "../support/case.mjs";
import {clickCy, textCy} from "../support/dom.mjs";

export const cases = [
  defineCase({
    id: "T-01",
    family: "T",
    fast: true,
    title: "child expression renders state into the DOM",
    async run(mount, expect) {
      const h = await mount({fixture: "counter", attrs: {step: "1"}});
      clickCy(h, "holo-counter-inc");
      await h.waitFor(() => textCy(h, "holo-counter-count") === "1");
      expect(textCy(h, "holo-counter-count")).to.equal("1");
    },
  }),

  pendingCase({id: "T-02", family: "T", fast: true, title: "attribute expression sets an attribute", reason: "compiled-element template fixture owed (1d/3c)"}),
  pendingCase({id: "T-03", family: "T", fast: true, title: "boolean attribute expression (?hidden) presence/absence", reason: "?attr lexer + emission land with brief 1c/3c"}),
  pendingCase({id: "T-04", family: "T", fast: true, title: "property expression (.value) sets a DOM property", reason: "compiled-element template fixture owed (1d/3c)"}),
  pendingCase({id: "T-05", family: "T", fast: true, title: "event listener expression (@click) invokes the handler", reason: "compiled-element template fixture owed (1d/3c)"}),
  pendingCase({id: "T-06", family: "T", fast: true, title: "nothing sentinel renders no nodes", reason: "nothing directive lands with brief 1d"}),
  pendingCase({id: "T-07", family: "T", fast: true, title: "conditional rendering toggles branches", reason: "compiled-element template fixture owed (1d/3c)"}),
  pendingCase({id: "T-08", family: "T", fast: true, title: "list rendering maps an array to child nodes", reason: "compiled-element template fixture owed (1d/3c)"}),
  pendingCase({id: "T-09", family: "T", fast: false, title: "nested templates compose", reason: "compiled-element template fixture owed (1d/3c)"}),
];