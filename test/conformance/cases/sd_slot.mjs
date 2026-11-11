// Family SD — Shadow DOM slots (lit-parity §4.1, SD-01…SD-03).
// Slot rendering landed via D-T1: the compiled "slots" fixture renders bare
// <slot> / <slot name="…"> into the shadow root and light-DOM children assign
// (Tier 1; brief 4b case-fill). SD-03 (fallback CONTENT) stays pending: the
// develop Hologram lexer rejects an explicit </slot> close (the styles-panel
// boot bug owned by brief 1c), so `<slot>fallback</slot>` cannot be expressed.

import {defineCase, pendingCase} from "../support/case.mjs";

export const cases = [
  defineCase({
    id: "SD-01",
    family: "SD",
    fast: true,
    title: "default slot accepts a light-DOM child",
    async run(mount, expect) {
      const h = await mount({fixture: "slots"});
      const child = h.win.document.createElement("p");
      child.textContent = "default-child";
      h.el.appendChild(child);
      const slot = h.shadowRoot.querySelector("[data-cy=conf-slots-default] slot");
      await h.waitFor(() => slot.assignedElements().includes(child));
      expect(slot.assignedElements()).to.include(child);
    },
  }),

  defineCase({
    id: "SD-02",
    family: "SD",
    fast: true,
    title: "named slot routes slot=\"x\" children",
    async run(mount, expect) {
      const h = await mount({fixture: "slots"});
      const child = h.win.document.createElement("span");
      child.setAttribute("slot", "header");
      child.textContent = "header-child";
      h.el.appendChild(child);
      const named = h.shadowRoot.querySelector("[data-cy=conf-slots-named] slot");
      const def = h.shadowRoot.querySelector("[data-cy=conf-slots-default] slot");
      await h.waitFor(() => named.assignedElements().includes(child));
      expect(named.assignedElements()).to.include(child);
      // The named child must NOT leak into the default slot.
      expect(def.assignedElements()).to.not.include(child);
    },
  }),

  pendingCase({id: "SD-03", family: "SD", fast: true, title: "slot fallback renders when no child is slotted", reason: "fallback content needs <slot>…</slot>; the develop Hologram lexer rejects </slot> (styles-panel boot bug, brief 1c owns the fix). Bare slots work (SD-01/02)."}),
];