// Scenario (e): <Link> client-side navigation round trip — elements must
// stay live and no NotSupportedError may appear (console capture +
// uncaught-exception failure).

/// <reference types="cypress" />
import { tesseraSteps as steps } from "../support/tessera/steps";
import { tesseraAsserts as asserts } from "../support/tessera/asserts";

// @fast: core-claim smoke (Link navigation) — runs in the fast per-change lane.
describe("tessera hologram demo — Link navigation round trip", { tags: "@fast" }, () => {
  it("(e) main → second → main keeps tessera elements live", () => {
    // Given the main page with a mounted card
    steps.visitHologramMain();
    steps.waitDefined("persona-card");
    asserts.mounted("persona-card");

    // When the visitor navigates to /second via the layout <Link> …
    steps.clickNavLink("nav-second");
    cy.get('[data-cy="second-title"]').should("be.visible");
    steps.waitDefined("persona-card");
    asserts.mounted("persona-card");
    asserts.cardInternalText("body", "internal:0");

    // … clicks the second page's card (still live after navigation) …
    cy.get("body persona-card")
      .shadow()
      .find('[data-cy="persona-card-btn"]')
      .click();
    asserts.cardInternalText("body", "internal:1");

    // … and navigates back — no NotSupportedError, elements still work.
    steps.clickNavLink("nav-main");
    cy.get('[data-cy="main-title"]').should("be.visible");
    steps.waitDefined("persona-card");
    asserts.mounted("persona-card");
    steps.clickPanelACardButton();
    asserts.mainSelected("Ada Lovelace");
    asserts.mainClickCount("1");

    asserts.noConsoleErrors();
  });
});
