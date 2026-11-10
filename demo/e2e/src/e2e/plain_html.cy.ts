// Plain-HTML demo: vanilla addEventListener consumes tessera events
// (event detail assertions), no framework involved.

/// <reference types="cypress" />
import { tesseraSteps as steps } from "../support/tessera/steps";
import { tesseraAsserts as asserts } from "../support/tessera/asserts";

describe("tessera plain-HTML demo", () => {
  beforeEach(() => {
    // Given the static page serves the bundled components
    steps.visitPlain();
    steps.waitDefined("persona-card");
    steps.waitDefined("persona-picker");
    asserts.mounted("persona-card");
    asserts.mounted("persona-picker");
  });

  it("card persona-select detail reaches a vanilla document listener", () => {
    // When the visitor clicks the first card's select button twice
    cy.get('[data-cy="plain-cards"] persona-card')
      .first()
      .shadow()
      .find('[data-cy="persona-card-btn"]')
      .click()
      .click();

    // Then the vanilla listener logged the composed event details
    asserts.plainLogLine(0, "persona-select");
    asserts.plainLogLine(0, '"personaId":"Ada Lovelace"');
    asserts.plainLogLine(0, '"clickCount":1');
    asserts.plainLogLine(1, '"clickCount":2');
    // and the internal counter incremented across both clicks
    asserts.cardInternalText('[data-cy="plain-cards"]', "internal:2");

    asserts.noConsoleErrors();
  });

  it("picker persona-picked detail reaches a vanilla document listener", () => {
    // When the visitor picks the first card inside the picker's shadow DOM
    steps.clickPickerCardButton(0);

    // Then the re-emitted detail arrived: { personaId: "Ada Lovelace" }
    asserts.plainLogLine(0, "persona-picked");
    asserts.plainLogLine(0, '"personaId":"Ada Lovelace"');
    asserts.pickerSelected("picked: Ada Lovelace");
    // child persona-select stayed private: no persona-select line logged
    cy.get('[data-cy="plain-log-line"]').should("have.length", 1);

    asserts.noConsoleErrors();
  });
});
