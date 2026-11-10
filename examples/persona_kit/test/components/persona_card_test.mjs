// persona-card element tests (PersonaKit.PersonaCard): registration,
// attribute → typed property application, json prop via tsr-props, and the
// composed persona-select CustomEvent with camelCase detail keys.
import { expect, aTimeout } from "@open-wc/testing";
import { register } from "../../lib/persona_kit/persona_card.mjs";

describe("<persona-card>", () => {
  before(() => {
    register();
  });

  function make(attrs = {}, tsrProps) {
    const el = document.createElement("persona-card");
    for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, value);
    if (tsrProps !== undefined) el.setAttribute("tsr-props", JSON.stringify(tsrProps));
    document.body.appendChild(el);
    return el;
  }

  it("defines the custom element exactly once", () => {
    const ctor = register();
    expect(customElements.get("persona-card")).to.equal(ctor);
  });

  it("coerces attrs to typed camelCase properties", async () => {
    const el = make({ "display-name": "Ada", tagline: "analytical engine", disabled: "" });
    await aTimeout(0); // let attributeChangedCallback settle

    expect(el.displayName).to.equal("Ada");
    expect(el.tagline).to.equal("analytical engine");
    expect(el.disabled).to.equal(true); // boolean by presence
  });

  it("absent boolean attr means false", async () => {
    const el = make({ "display-name": "Ada" });
    await aTimeout(0);
    expect(el.disabled).to.equal(false);
  });

  it("applies the json tagList prop from tsr-props", async () => {
    const el = make({ "display-name": "Ada" }, { tagList: ["logic", "math"] });
    await aTimeout(50); // tsr-props → requestUpdate → Lit render

    const chips = el.shadowRoot.querySelectorAll("[data-cy=persona-card-chip]");
    expect([...chips].map((chip) => chip.textContent)).to.eql(["logic", "math"]);
  });

  it("emits a composed, bubbling persona-select with camelCase detail", async () => {
    const el = make({ "display-name": "Grace" });
    await aTimeout(0);

    const received = [];
    const listener = (event) => received.push(event);
    document.addEventListener("persona-select", listener);
    try {
      el.shadowRoot.querySelector("[data-cy=persona-card-btn]").click();
      await aTimeout(0);
    } finally {
      document.removeEventListener("persona-select", listener);
    }

    expect(received).to.have.lengthOf(1);
    const event = received[0];
    expect(event.bubbles).to.equal(true);
    expect(event.composed).to.equal(true);
    expect(event.detail).to.eql({ personaId: "Grace", clickCount: 1 });
  });

  it("keeps the internal click counter across re-application of attrs", async () => {
    const el = make({ "display-name": "Grace" });
    await aTimeout(0);
    const btn = () => el.shadowRoot.querySelector("[data-cy=persona-card-btn]");
    const counter = () => el.shadowRoot.querySelector("[data-cy=persona-card-internal]");

    btn().click();
    btn().click();
    await aTimeout(0);
    // Simulate a host re-render touching the attribute again.
    el.setAttribute("display-name", "Grace Hopper");
    await aTimeout(0);

    expect(counter().textContent).to.include("internal:2");
    expect(el.shadowRoot.querySelector("[data-cy=persona-card-name]").textContent).to.equal(
      "Grace Hopper",
    );
  });
});
