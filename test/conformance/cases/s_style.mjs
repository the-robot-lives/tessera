// Family S — Styles (lit-parity §4.1, S-01…S-06).
// The styles DSL landed with brief 1b (composed static styles + theming
// contract). These cases run against the compiled-DSL "styles" fixture
// (Tier 1; brief 4b case-fill), asserting the RENDERED CSS via computed styles.

import {defineCase} from "../support/case.mjs";

export const cases = [
  defineCase({
    id: "S-01",
    family: "S",
    fast: true,
    title: ":host style applies to the host",
    async run(mount, expect) {
      const h = await mount({fixture: "styles"});
      const cs = h.win.getComputedStyle(h.el);
      expect(cs.display).to.equal("block");
      // Author :host padding (base styles declare none) — proves the author
      // block, not just the base boilerplate, reached the host.
      expect(cs.paddingTop).to.equal("8px");
    },
  }),

  defineCase({
    id: "S-02",
    family: "S",
    fast: true,
    title: ":host([attr]) conditional style",
    async run(mount, expect) {
      const h = await mount({fixture: "styles"});
      // tone defaults to "light" — the [tone="dark"] rule must NOT match yet.
      expect(h.win.getComputedStyle(h.el).backgroundColor).to.not.equal("rgb(17, 17, 17)");
      h.el.setAttribute("tone", "dark");
      await h.waitFor(() => h.win.getComputedStyle(h.el).backgroundColor === "rgb(17, 17, 17)");
      expect(h.win.getComputedStyle(h.el).backgroundColor).to.equal("rgb(17, 17, 17)");
    },
  }),

  defineCase({
    id: "S-03",
    family: "S",
    fast: true,
    title: "::slotted() styles slotted children",
    async run(mount, expect) {
      const h = await mount({fixture: "styles"});
      const p = h.win.document.createElement("p");
      p.textContent = "slotted";
      h.el.appendChild(p);
      await h.waitFor(() => h.shadowRoot.querySelector("slot").assignedElements().length > 0);
      // ::slotted(p) { margin: 0; color: var(--tsr-…-slotted, #c0c); }
      expect(h.win.getComputedStyle(p).color).to.equal("rgb(204, 0, 204)");
      expect(h.win.getComputedStyle(p).marginTop).to.equal("0px");
    },
  }),

  defineCase({
    id: "S-04",
    family: "S",
    fast: true,
    title: "CSS custom property resolves from the parent",
    async run(mount, expect) {
      const h = await mount({fixture: "styles"});
      const accent = h.shadowRoot.querySelector("[data-cy=conf-styles-accent]");
      // Fallback applies when the parent sets nothing.
      expect(h.win.getComputedStyle(accent).color).to.equal("rgb(102, 204, 255)");
      // A parent-scoped custom property pierces the shadow boundary.
      const wrapper = h.win.document.createElement("div");
      wrapper.style.setProperty("--tsr-tsr-conf-styles-accent", "rgb(255, 0, 0)");
      h.el.parentNode.insertBefore(wrapper, h.el);
      wrapper.appendChild(h.el);
      await h.waitFor(() => h.win.getComputedStyle(accent).color === "rgb(255, 0, 0)");
      expect(h.win.getComputedStyle(accent).color).to.equal("rgb(255, 0, 0)");
    },
  }),

  defineCase({
    id: "S-05",
    family: "S",
    fast: false,
    title: "shared CSSResult module applies",
    async run(mount, expect) {
      const h = await mount({fixture: "styles"});
      // {:shared, "./shared_styles.mjs"} exports a CSSResult styling .shared-marker.
      const shared = h.shadowRoot.querySelector("[data-cy=conf-styles-shared]");
      expect(h.win.getComputedStyle(shared).color).to.equal("rgb(0, 128, 0)");
    },
  }),

  defineCase({
    id: "S-06",
    family: "S",
    fast: false,
    title: "static styles array composes all entries",
    async run(mount, expect) {
      const h = await mount({fixture: "styles"});
      const accent = h.shadowRoot.querySelector("[data-cy=conf-styles-accent]");
      // First author block sets .accent #000; the second sets
      // var(--tsr-…-accent, #6cf). Later array entry wins the cascade ⇒ #6cf.
      expect(h.win.getComputedStyle(accent).color).to.equal("rgb(102, 204, 255)");
    },
  }),
];