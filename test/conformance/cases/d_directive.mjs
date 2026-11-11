// Family D — Built-in directives (lit-parity §4.1, D-01…D-07).
// classMap/styleMap/ifDefined landed with brief 1d and run against the compiled
// "directives" fixture (real generated Lit elements). when/choose compile from
// the template DSL; repeat/ref are accepted-with-hatch (4a ballot).

import {defineCase, pendingCase} from "../support/case.mjs";
import {clickCy} from "../support/dom.mjs";

export const cases = [
  defineCase({
    id: "D-01",
    family: "D",
    fast: true,
    title: "classMap applies a dynamic class map",
    async run(mount, expect) {
      const h = await mount({fixture: "directives"});
      const node = h.shadowRoot.querySelector("[data-cy=conf-dir-class]");
      // Both flags start false ⇒ neither class is present.
      expect(node.classList.contains("active")).to.equal(false);
      expect(node.classList.contains("highlight")).to.equal(false);
      // Toggle active ⇒ the class appears (and only it).
      clickCy(h, "conf-dir-toggle-active");
      await h.waitFor(() => node.classList.contains("active"));
      expect(node.classList.contains("active")).to.equal(true);
      expect(node.classList.contains("highlight")).to.equal(false);
      // Toggle highlight ⇒ both classes compose.
      clickCy(h, "conf-dir-toggle-highlight");
      await h.waitFor(() => node.classList.contains("highlight"));
      expect(node.classList.contains("active")).to.equal(true);
      expect(node.classList.contains("highlight")).to.equal(true);
      // Toggle active off ⇒ classMap removes just that class.
      clickCy(h, "conf-dir-toggle-active");
      await h.waitFor(() => !node.classList.contains("active"));
      expect(node.classList.contains("active")).to.equal(false);
      expect(node.classList.contains("highlight")).to.equal(true);
    },
  }),

  defineCase({
    id: "D-02",
    family: "D",
    fast: true,
    title: "styleMap applies a dynamic style map",
    async run(mount, expect) {
      const h = await mount({fixture: "directives", attrs: {bg: "red", accent: "blue"}});
      const node = h.shadowRoot.querySelector("[data-cy=conf-dir-style]");
      // camelCase key ⇒ inline style; string key ⇒ CSS custom property.
      expect(node.style.backgroundColor).to.equal("red");
      expect(node.style.getPropertyValue("--tsr-conf-directives-accent").trim()).to.equal("blue");
      // Changing the bound attr re-renders the inline style.
      h.el.setAttribute("bg", "green");
      await h.waitFor(() => node.style.backgroundColor === "green");
      expect(node.style.backgroundColor).to.equal("green");
    },
  }),

  pendingCase({id: "D-03", family: "D", fast: true, title: "when directive selects the correct template", reason: "compiled-element template fixture owed (1d/3c)"}),
  pendingCase({id: "D-04", family: "D", fast: false, title: "choose directive selects the matching case", reason: "compiled-element template fixture owed (1d/3c)"}),
  pendingCase({id: "D-05", family: "D", fast: false, title: "repeat with keys reorders DOM nodes", reason: "repeat directive is accepted-with-hatch (4a); host-side keyed rendering is the alternative", disposition: "accepted-with-hatch"}),

  defineCase({
    id: "D-06",
    family: "D",
    fast: true,
    title: "ifDefined omits the attribute when undefined",
    async run(mount, expect) {
      const h = await mount({fixture: "directives"});
      const node = h.shadowRoot.querySelector("[data-cy=conf-dir-defined]");
      // title_text unset ⇒ undefined ⇒ ifDefined removes the attribute.
      expect(node.hasAttribute("title")).to.equal(false);
      // A defined value ⇒ the attribute is set.
      h.el.setAttribute("title-text", "hello");
      await h.waitFor(() => node.getAttribute("title") === "hello");
      expect(node.getAttribute("title")).to.equal("hello");
      // Removing the attr ⇒ undefined again ⇒ the attribute is removed.
      h.el.removeAttribute("title-text");
      await h.waitFor(() => !node.hasAttribute("title"));
      expect(node.hasAttribute("title")).to.equal(false);
    },
  }),

  pendingCase({id: "D-07", family: "D", fast: false, title: "ref directive exposes the rendered element", reason: "ref directive is accepted-with-hatch (4a); host-side query is the alternative", disposition: "accepted-with-hatch"}),
];