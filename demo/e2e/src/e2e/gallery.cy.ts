// Component gallery (mix tessera.gen.gallery) over the persona_kit example
// package: the CEM-driven gallery lists every component, renders it live,
// applies typed attr/prop/slot/CSS edits to the real element, and logs the
// events it emits (name + camelCase detail). Framework-agnostic — the page
// is static HTML + the package's own bundles, no framework involved.

/// <reference types="cypress" />
import { tesseraSteps as steps } from "../support/tessera/steps";
import { tesseraAsserts as asserts } from "../support/tessera/asserts";

const CARD = '[data-cy="gallery-component"][data-tag="persona-card"]';
const PICKER = '[data-cy="gallery-component"][data-tag="persona-picker"]';
const cardDemo = `${CARD} [data-cy="gallery-demo"] persona-card`;
const pickerDemo = `${PICKER} [data-cy="gallery-demo"] persona-picker`;

// @fast: gallery acceptance (CEM-driven live demos + editors + event log) —
// quick (3s) and core to the gallery claim, so it gates the fast lane.
describe("tessera component gallery (persona_kit)", { tags: "@fast" }, () => {
  beforeEach(() => {
    // Given the generated gallery serves the package's CEM + bundles
    steps.visitGallery();
    steps.waitDefined("persona-card");
    steps.waitDefined("persona-picker");
  });

  it("lists every package component with a live, upgraded demo", () => {
    cy.get('[data-cy="gallery-title"]').should("contain", "PersonaKit");
    cy.get('[data-cy="gallery-component"]').should("have.length", 2);
    asserts.galleryLists("persona-card");
    asserts.galleryLists("persona-picker");
    asserts.noConsoleErrors();
  });

  it("attribute edits update the live element (string + boolean presence)", () => {
    // When the visitor edits the display-name attr and toggles disabled
    cy.get(`${CARD} [data-cy="gallery-attr-persona-card-display-name"]`)
      .clear()
      .type("Ada Lovelace");
    cy.get(`${CARD} [data-cy="gallery-attr-persona-card-disabled"]`).check();

    // Then the live card reflects both: the name renders, the button disables
    cy.get(cardDemo).shadow().find('[data-cy="persona-card-name"]').should("contain", "Ada Lovelace");
    cy.get(cardDemo).shadow().find('[data-cy="persona-card-btn"]').should("be.disabled");
    cy.get(cardDemo).should("have.attr", "disabled");

    // And unchecking removes the boolean attribute (presence semantics)
    cy.get(`${CARD} [data-cy="gallery-attr-persona-card-disabled"]`).uncheck();
    cy.get(cardDemo).should("not.have.attr", "disabled");
    cy.get(cardDemo).shadow().find('[data-cy="persona-card-btn"]').should("not.be.disabled");
    asserts.noConsoleErrors();
  });

  it("json property edits update the live element", () => {
    // When the visitor edits the tagList json prop
    cy.get(`${CARD} [data-cy="gallery-prop-persona-card-tagList"]`)
      .clear()
      .type('["compiler", "navy"]');

    // Then the card renders one chip per tag
    cy.get(cardDemo).shadow().find('[data-cy="persona-card-chip"]').should("have.length", 2);
    cy.get(cardDemo).shadow().find('[data-cy="persona-card-chip"]').first().should("contain", "compiler");
    asserts.noConsoleErrors();
  });

  it("slot-content editing reaches the shadow DOM slot", () => {
    // When the visitor types footer slot content
    cy.get(`${CARD} [data-cy="gallery-slot-persona-card-footer"]`).clear().type("footer text");

    // Then the light-DOM node is slotted into the shadow footer slot
    cy.get(cardDemo).then(($el) => {
      const slot = $el[0].shadowRoot?.querySelector('footer slot[name="footer"]');
      const assigned = (slot as HTMLSlotElement).assignedNodes().map((n) => n.textContent ?? "");
      expect(assigned.join("")).to.contain("footer text");
    });
    asserts.noConsoleErrors();
  });

  it("CSS custom-property edits theme the live element", () => {
    // When the visitor sets --persona-card-accent (a CEM cssProperties entry)
    cy.get(`${CARD} [data-cy="gallery-css-persona-card-persona-card-accent"]`)
      .clear()
      .type("rgb(220, 38, 38)");

    // Then the element's border (which reads the custom property) recolors
    cy.get(cardDemo).should(($el) => {
      expect(getComputedStyle($el[0]).borderTopColor).to.eq("rgb(220, 38, 38)");
    });
    asserts.noConsoleErrors();
  });

  it("emitted events appear in the log with camelCase detail", () => {
    // Given a named card
    cy.get(`${CARD} [data-cy="gallery-attr-persona-card-display-name"]`)
      .clear()
      .type("Ada Lovelace");

    // When the visitor clicks select twice
    cy.get(cardDemo).shadow().find('[data-cy="persona-card-btn"]').click().click();

    // Then the gallery logged persona-select with { personaId, clickCount }
    asserts.galleryLogLine("persona-card", 0, "persona-select");
    asserts.galleryLogLine("persona-card", 0, '"personaId":"Ada Lovelace"');
    asserts.galleryLogLine("persona-card", 0, '"clickCount":1');
    asserts.galleryLogLine("persona-card", 1, '"clickCount":2');
    asserts.noConsoleErrors();
  });

  it("picker: json prop renders cards and the re-emitted event logs", () => {
    // When the visitor supplies personas through the picker's json prop
    const personas = [
      { id: "ada", name: "Ada Lovelace", tags: ["logic"] },
      { id: "grace", name: "Grace Hopper", tags: ["navy"] },
    ];
    steps.setGalleryJson(`${PICKER} [data-cy="gallery-prop-persona-picker-personas"]`, JSON.stringify(personas));

    // Then the picker renders a card per persona
    cy.get(pickerDemo).shadow().find("persona-card").should("have.length", 2);

    // When the visitor picks the first inner card
    cy.get(pickerDemo).shadow().find("persona-card").eq(0)
      .shadow().find('[data-cy="persona-card-btn"]').click();

    // Then the picker's own persona-picked event logged with camelCase detail
    asserts.galleryLogLine("persona-picker", 0, "persona-picked");
    asserts.galleryLogLine("persona-picker", 0, '"personaId":"Ada Lovelace"');
    // and the child's persona-select stayed private (not logged on the picker)
    cy.get(`${PICKER} [data-cy="gallery-log-line"]`).should("have.length", 1);
    asserts.noConsoleErrors();
  });
});