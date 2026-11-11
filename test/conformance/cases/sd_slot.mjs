// Family SD — Shadow DOM slots (lit-parity §4.1, SD-01…SD-03).
// Slot rendering landed via D-T1; fallback content via brief 1c's slot
// pre-pass (Hologram treats <slot> as void, so 1c renames it through a reserved
// placeholder). The compiled "slots" fixture renders <slot> / <slot name="…">
// (with fallback) into the shadow root and light-DOM children assign (Tier 1;
// brief 4b case-fill).

import {defineCase} from "../support/case.mjs";

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

  defineCase({
    id: "SD-03",
    family: "SD",
    fast: true,
    title: "slot fallback renders when no child is slotted",
    async run(mount, expect) {
      const h = await mount({fixture: "slots"});
      const fb = h.shadowRoot.querySelector("[data-cy=conf-slots-fallback] slot");
      // No child slotted ⇒ the slot's fallback content is what renders
      // (assignedNodes flatten:true yields the fallback when nothing assigns).
      expect(fb.assignedElements().length).to.equal(0);
      expect(fb.assignedNodes({flatten: true}).map((n) => n.textContent).join("")).to.equal("fallback-content");
      // Slot a child ⇒ the fallback is replaced by the slotted node.
      const child = h.win.document.createElement("span");
      child.setAttribute("slot", "fb");
      child.textContent = "slotted-fb";
      h.el.appendChild(child);
      await h.waitFor(() => fb.assignedElements().includes(child));
      expect(fb.assignedElements()).to.include(child);
      expect(fb.assignedNodes({flatten: true}).map((n) => n.textContent).join("")).to.equal("slotted-fb");
    },
  }),
];