// Accessibility lane (TESSER-015, BoE need #5): axe-core over the static demo
// host plus an aria-live-inside-shadow-root check.
//
// Lane: @fast (about 1s of test time). Needs only the plain-HTML host (:5587,
// already booted by the fast CI lane). NOT covered yet: the Tier-2 static host
// (:5589) - it needs `mix tessera.bundles` output to render, which could not be
// run when this lane landed, so no unverified nightly test was added.
//
// HONESTY: Cypress cannot hear a screen reader. "Announces" is asserted as
// the strongest machine-checkable proxy: the live region is present in
// Chromium's accessibility tree (CDP Accessibility.getFullAXTree) with
// role=status and live=polite, and its text updates on a user action.

/// <reference types="cypress" />
import { tesseraA11y as a11y } from "../support/tessera/a11y";

const PLAIN: string = Cypress.env("tsrPlainUrl") ?? "http://localhost:5587";

describe("tessera a11y: axe over the plain-HTML host", { tags: "@fast" }, () => {
  it("index.html (persona-card / persona-picker, shadow DOM) has no axe violations", () => {
    cy.visit(`${PLAIN}/`);
    cy.get("persona-card").should("exist");
    cy.get("persona-card").first().shadow().find('[data-cy="persona-card-btn"]').should("exist");
    // KNOWN DEFECT (computed by axe: #6366f1 on #ffffff = 4.46:1, needs 4.5:1,
    // 13.6px normal weight): the persona-card `.internal` text in
    // examples/persona_kit. Tracked as a TESSER-015 follow-up for tessera-lit-1;
    // the entry must be deleted when the colour is darkened (it fails once fixed).
    a11y.expectNoAxeViolations(["color-contrast"]);
  });

  it("a11y-live.html fixture has no axe violations", () => {
    cy.visit(`${PLAIN}/a11y-live.html`);
    a11y.expectNoAxeViolations();
  });
});

describe("tessera a11y: aria-live inside a shadow root", { tags: "@fast" }, () => {
  beforeEach(() => {
    cy.visit(`${PLAIN}/a11y-live.html`);
  });

  it("the live region sits in a shadow root, in the accessibility tree, with status/polite", () => {
    // Given the region really is inside the shadow root (not light DOM)
    cy.get('[data-cy="probe"]').then(($host) => {
      expect($host[0].shadowRoot, "open shadow root").to.not.eq(null);
    });
    cy.get('[data-cy="probe"]').find('[data-cy="probe-live"]').should("not.exist");
    cy.get('[data-cy="probe"]').shadow().find('[data-cy="probe-live"]').as("live");
    cy.get("@live").should("have.attr", "aria-live", "polite").and("have.attr", "role", "status");

    // Then the browser exposes it in the accessibility tree
    a11y.axTree().then((nodes) => {
      const status = nodes.find((n) => n.role?.value === "status");
      expect(status, "status node in AX tree").to.not.eq(undefined);
      expect(a11y.prop(status, "live"), "AX live").to.eq("polite");
      expect(a11y.prop(status, "atomic"), "AX atomic").to.eq(true);
    });
  });

  it("its text updates on an action and the AX tree reflects the new text", () => {
    cy.get('[data-cy="probe"]').shadow().find('[data-cy="probe-live"]').as("live");
    cy.get("@live").should("have.text", "No items yet");

    cy.get('[data-cy="probe"]').shadow().find('[data-cy="probe-btn"]').click();
    cy.get("@live").should("have.text", "1 item added");
    cy.get('[data-cy="probe"]').shadow().find('[data-cy="probe-btn"]').click();
    cy.get("@live").should("have.text", "2 items added");

    a11y.axTree().then((nodes) => {
      const status = nodes.find((n) => n.role?.value === "status");
      expect(status, "status node in AX tree").to.not.eq(undefined);
      const text = nodes
        .filter((n) => n.role?.value === "StaticText" || n.role?.value === "text")
        .map((n) => n.name?.value);
      expect(text, "AX text nodes").to.include("2 items added");
    });
  });
});
