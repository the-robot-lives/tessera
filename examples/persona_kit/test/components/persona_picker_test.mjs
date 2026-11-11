// persona-picker element tests (PersonaKit.PersonaPicker): registration,
// json personas prop → shadow cards, and the CONTRACT.md §4 nested-shadow
// pattern — the child card's persona-select stays private while the picker
// RE-EMITS persona-picked from ITSELF.
import { expect, aTimeout } from "@open-wc/testing";
import { register as registerCard } from "../../lib/persona_kit/persona_card.mjs";
import { register } from "../../lib/persona_kit/persona_picker.mjs";

const PERSONAS = [
  { id: "ada", name: "Ada Lovelace", tags: ["logic", "math"] },
  { id: "grace", name: "Grace Hopper", tags: ["compilers"] },
  { id: "alan", name: "Alan Turing", tags: ["machines"] },
];

describe("<persona-picker>", () => {
  before(() => {
    // The picker composes persona-card children — both modules must have
    // evaluated (on a Hologram page both are bundled; here we mirror that).
    registerCard();
    register();
  });

  function make(attrs = {}, tsrProps) {
    const el = document.createElement("persona-picker");
    for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, value);
    if (tsrProps !== undefined) el.setAttribute("tsr-props", JSON.stringify(tsrProps));
    document.body.appendChild(el);
    return el;
  }

  it("defines the custom element exactly once", () => {
    const ctor = register();
    expect(customElements.get("persona-picker")).to.equal(ctor);
  });

  it("renders one persona-card per personas entry inside its shadow DOM", async () => {
    const el = make({ title: "Pick a persona" }, { personas: PERSONAS });
    await aTimeout(50); // tsr-props → requestUpdate → Lit render

    const cards = el.shadowRoot.querySelectorAll("persona-card");
    expect(cards.length).to.equal(3);
    expect(cards[0].getAttribute("display-name")).to.equal("Ada Lovelace");
    expect(el.shadowRoot.querySelector("[data-cy=persona-picker-selected]").textContent).to.include(
      "picked: none",
    );
  });

  it("keeps the child persona-select private and re-emits persona-picked from itself", async () => {
    const el = make({ title: "Pick" }, { personas: PERSONAS });
    await aTimeout(50);

    const directSelect = [];
    const picked = [];
    const onSelect = (event) => directSelect.push(event);
    const onPicked = (event) => picked.push(event);
    document.addEventListener("persona-select", onSelect);
    document.addEventListener("persona-picked", onPicked);
    try {
      // Click INSIDE the nested card's shadow DOM (two shadow roots deep).
      const card = el.shadowRoot.querySelector("persona-card");
      card.shadowRoot.querySelector("[data-cy=persona-card-btn]").click();
      await aTimeout(0);
    } finally {
      document.removeEventListener("persona-select", onSelect);
      document.removeEventListener("persona-picked", onPicked);
    }

    // The child's event never escapes the picker (stopPropagation), but the
    // re-emitted event does — FROM THE PICKER (event.target is the picker).
    expect(directSelect).to.have.lengthOf(0);
    expect(picked).to.have.lengthOf(1);
    expect(picked[0].target).to.equal(el);
    expect(picked[0].detail).to.eql({ personaId: "Ada Lovelace" });
    expect(el.shadowRoot.querySelector("[data-cy=persona-picker-selected]").textContent).to.include(
      "picked: Ada Lovelace",
    );
  });
});
