// Family FM — Forms (lit-parity §2.10 rows #144-#149, brief 3e owns this
// case set — the provisional scaffold placeholders are retired here).
//
// Tier-2 fixture: tsr-holo-form-probe (HoloKit.Components.FormProbe) — the
// component manifest declares formAssociated (brief 3e fixture hook
// __tsr_form_associated__; brief 3f moves it to the spec), so defineElement
// sets `static formAssociated = true` and the constructor attaches an
// ElementInternals (§6.7: internals NEVER attach otherwise — FM-01 pins the
// negative on the undeclared counter fixture). The host glue mounts the
// module through a recording subclass implementing the DOCUMENTED pattern
// the cases pin: every render pushes state.value through setFormValue
// (#147), formResetCallback (#148) dispatches the component's reset_value,
// formDisabledCallback (#149) records transitions into
// el.tesseraFormSignals; setValidity (#146) is driven straight on internals.
//
// Tier 1: no fixture yet (formAssociated emission is brief 2f) — FM stays
// adapter-pending on the WTR adapter, skipped, never green.

import {defineCase} from "../support/case.mjs";

// Move a freshly-mounted fixture element into a live <form> (pure DOM — the
// harness appends elements to document.body, so the case creates the form
// and reparents; ElementInternals.form follows the new owner).
function attachForm(h, name) {
  const form = h.win.document.createElement("form");
  h.win.document.body.appendChild(form);
  h.el.setAttribute("name", name);
  form.appendChild(h.el);
  return form;
}

export const cases = [
  defineCase({
    id: "FM-01",
    family: "FM",
    fast: true,
    title: "declared formAssociated participates; undeclared never gets internals",
    async run(mount, expect) {
      const h = await mount({fixture: "form"});
      // #144 static + #145 internals — the DECLARED side.
      expect(h.el.constructor.formAssociated).to.equal(true);
      expect(h.el.internals).to.not.equal(null);
      // The negative half of §6.7's MUST NOT: an undeclared tag NEVER gets
      // an ElementInternals attached (internals reads as null, not throws).
      const c = await mount({fixture: "counter"});
      expect(c.el.internals).to.equal(null);
    },
  }),

  defineCase({
    id: "FM-02",
    family: "FM",
    fast: true,
    title: "state drives the form value through internals.setFormValue",
    async run(mount, expect) {
      const h = await mount({fixture: "form"});
      const form = attachForm(h, "hp");
      await h.settle(); // first render pushed the initial value

      const res = await h.el.dispatchAction("set_value", {value: "hello"});
      expect(res.ok).to.equal(true);
      // settle(): render + form-data entry append are observable after the
      // macrotask flush (same sync point FM-03 uses — Tier 2 commits the
      // patch synchronously, but the form's custom-element entry refresh is
      // not guaranteed inside the same microtask).
      await h.settle();
      // #147 — the submission surface: FormData carries the name/value the
      // internals seam pushed, and the internals stay bound to the owning
      // form. (internals.value is the author-managed API value — NOT a
      // mirror of setFormValue — so the platform-guaranteed surfaces are
      // what gets pinned here: submission data + form association.)
      expect(new h.win.FormData(form).get("hp")).to.equal("hello");
      expect(h.el.internals.form).to.equal(form);
      // state projection rides along (DOM evidence of the transition):
      await h.waitFor(() =>
        h.shadowRoot.querySelector('[data-cy="conf-form-value"]').textContent.trim() === "hello");
    },
  }),

  defineCase({
    id: "FM-03",
    family: "FM",
    fast: false,
    title: "form reset / disabled reach the element; setValidity surfaces",
    async run(mount, expect) {
      const h = await mount({fixture: "form"});
      const form = attachForm(h, "hp2");
      await h.el.dispatchAction("set_value", {value: "dirty"});
      await h.settle();
      expect(new h.win.FormData(form).get("hp2")).to.equal("dirty");

      // #148 formResetCallback — reset reaches the element, the subclass
      // dispatches reset_value, and the re-render re-pushes the initial
      // value through the internals.
      form.reset();
      await h.waitFor(() => (h.el.tesseraFormSignals || []).includes("reset"));
      await h.settle();
      expect(new h.win.FormData(form).get("hp2")).to.equal("initial");

      // #149 formDisabledCallback — the disabled attribute flip reaches the
      // element in BOTH directions (FA custom elements observe it).
      h.el.setAttribute("disabled", "");
      await h.waitFor(() => (h.el.tesseraFormSignals || []).includes("disabled"));
      h.el.removeAttribute("disabled");
      await h.waitFor(() => (h.el.tesseraFormSignals || []).includes("enabled"));

      // #146 setValidity — custom validation state + message surface through
      // the internals, and the invalid element fails the owning form.
      const anchor = h.shadowRoot.querySelector('[data-cy="conf-form-value"]');
      h.el.internals.setValidity({valueMissing: true}, "pick a value", anchor);
      expect(h.el.internals.validity.valueMissing).to.equal(true);
      expect(h.el.internals.validationMessage).to.equal("pick a value");
      expect(form.checkValidity()).to.equal(false);
      h.el.internals.setValidity({});
      expect(h.el.internals.validity.valueMissing).to.equal(false);
      expect(form.checkValidity()).to.equal(true);
    },
  }),
];
