// Family T — Templates (lit-parity §4.1, T-01…T-09).
//
// T-01 (child expression) runs against the shared "counter" fixture on both
// tiers. T-02/T-04/T-05/T-07/T-08/T-09 run against the compiled-DSL "template"
// fixture (Tier 1; brief 4b case-fill — the template DSL landed via D-T1).
// T-06 (nothing) runs against the compiled "directives" fixture (brief 1d).
// T-03 (?attr) remains pending on brief 1c/3c's case-fill.

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

  defineCase({
    id: "T-02",
    family: "T",
    fast: true,
    title: "attribute expression sets an attribute",
    async run(mount, expect) {
      const h = await mount({fixture: "template", attrs: {label: "hello"}});
      const root = h.shadowRoot.querySelector("[data-cy=conf-template-root]");
      expect(root.getAttribute("title")).to.equal("hello");
      // Changing the bound attr re-renders the attribute expression.
      h.el.setAttribute("label", "world");
      await h.waitFor(() => root.getAttribute("title") === "world");
      expect(root.getAttribute("title")).to.equal("world");
    },
  }),

  pendingCase({id: "T-03", family: "T", fast: true, title: "boolean attribute expression (?hidden) presence/absence", reason: "?attr lexer + emission land with brief 1c/3c"}),

  defineCase({
    id: "T-04",
    family: "T",
    fast: true,
    title: "property expression (.value) sets a DOM property",
    async run(mount, expect) {
      const h = await mount({fixture: "template", attrs: {label: "hello"}});
      const input = h.shadowRoot.querySelector("[data-cy=conf-template-input]");
      // .value is a PROPERTY binding: it sets input.value, not the attribute.
      expect(input.value).to.equal("hello");
      expect(input.getAttribute("value")).to.equal(null);
      h.el.setAttribute("label", "world");
      await h.waitFor(() => input.value === "world");
      expect(input.value).to.equal("world");
    },
  }),

  defineCase({
    id: "T-05",
    family: "T",
    fast: true,
    title: "event listener expression (@click) invokes the handler",
    async run(mount, expect) {
      const h = await mount({fixture: "template"});
      expect(textCy(h, "conf-template-flag")).to.equal("OFF");
      // The $click={:toggle_flag} binding must route the DOM click to the
      // action; the state flip proves the handler ran.
      clickCy(h, "conf-template-toggle");
      await h.waitFor(() => textCy(h, "conf-template-flag") === "ON");
      expect(textCy(h, "conf-template-flag")).to.equal("ON");
    },
  }),

  defineCase({
    id: "T-06",
    family: "T",
    fast: true,
    title: "nothing sentinel renders no nodes",
    async run(mount, expect) {
      const h = await mount({fixture: "directives"});
      // Child position: ${nothing} renders no content nodes — no text, no
      // elements. lit-html keeps a comment marker for the child part itself
      // (scaffolding present for ANY child expression), so assert on rendered
      // content, not the raw childNodes count.
      const child = h.shadowRoot.querySelector("[data-cy=conf-dir-nothing-child]");
      expect(child.textContent).to.equal("");
      expect(child.children.length).to.equal(0);
      expect([...child.childNodes].every((n) => n.nodeType === 8)).to.equal(true);
      // Attribute position: title={nothing} removes the attribute.
      const attr = h.shadowRoot.querySelector("[data-cy=conf-dir-nothing-attr]");
      expect(attr.hasAttribute("title")).to.equal(false);
    },
  }),

  defineCase({
    id: "T-07",
    family: "T",
    fast: true,
    title: "conditional rendering toggles branches",
    async run(mount, expect) {
      const h = await mount({fixture: "template"});
      // {%else%} branch first.
      expect(textCy(h, "conf-template-flag")).to.equal("OFF");
      clickCy(h, "conf-template-toggle");
      await h.waitFor(() => textCy(h, "conf-template-flag") === "ON");
      // {%if%} branch, then back to {%else%}.
      clickCy(h, "conf-template-toggle");
      await h.waitFor(() => textCy(h, "conf-template-flag") === "OFF");
      expect(textCy(h, "conf-template-flag")).to.equal("OFF");
    },
  }),

  defineCase({
    id: "T-08",
    family: "T",
    fast: true,
    title: "list rendering maps an array to child nodes",
    async run(mount, expect) {
      const h = await mount({fixture: "template"});
      const items = [...h.shadowRoot.querySelectorAll("[data-cy=conf-template-list] li.item")];
      expect(items.map((n) => n.textContent.trim())).to.deep.equal(["alpha", "beta", "gamma"]);
    },
  }),

  defineCase({
    id: "T-09",
    family: "T",
    fast: false,
    title: "nested templates compose",
    async run(mount, expect) {
      // A {%for%} body with nested child elements (span > b > interpolation):
      // the loop-body template must compose the nested nodes, not flatten them.
      const h = await mount({fixture: "template"});
      const nests = [...h.shadowRoot.querySelectorAll("[data-cy=conf-template-nested] span.nest")];
      expect(nests.length).to.equal(3);
      for (const n of nests) {
        expect(n.querySelector("b"), "nested <b> child composed").to.not.equal(null);
      }
      expect(nests.map((n) => n.querySelector("b").textContent.trim())).to.deep.equal(["alpha", "beta", "gamma"]);
    },
  }),
];