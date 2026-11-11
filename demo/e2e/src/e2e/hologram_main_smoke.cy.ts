// BLOCKING smoke leg (b) of the main-page scenarios (tessera Phase 1c brief).
// Split out of hologram_main.cy.ts so CI can gate the legs that pass on Linux
// while the component-own-shadow-render legs (a)/(c)/(d) stay non-blocking —
// see docs/notes/e2e-linux-ci.md (`TODO(tessera-e2e-linux)`).
// BDD: each block is a Given/When/Then narrative kept as comments
// (CONVENTIONS §7 — no .feature files).

/// <reference types="cypress" />
import { tesseraSteps as steps } from "../support/tessera/steps";
import { tesseraAsserts as asserts } from "../support/tessera/asserts";

describe("tessera hologram demo — main page (smoke)", () => {
  beforeEach(() => {
    // Given the demo app is served and the tessera elements are defined
    steps.visitHologramMain();
    steps.waitDefined("persona-card");
    steps.waitDefined("persona-picker");
    asserts.mounted("persona-card");
    asserts.mounted("persona-picker");
  });

  it("(b) cid-targeted card → card action, NOT the page action", () => {
    // Given panel a has already routed a click to the page
    steps.clickPanelACardButton();
    asserts.mainSelected("Ada Lovelace");
    asserts.mainClickCount("1");

    // When the visitor clicks the STATEFUL card (cid="p1") in panel b
    steps.clickPanelBCardButton();

    // Then the card's own action ran (proof: the chained :cid_confirmed
    // action targeted at the page arrived) …
    asserts.mainCidConfirmed("Grace Hopper");
    // … but the PAGE :chose handler did NOT fire (targeting worked — no
    // bleed into panel a's state).
    asserts.mainSelected("Ada Lovelace");
    asserts.mainClickCount("1");
    asserts.cardInternalText('[data-cy="panel-b-inner"]', "internal:1");

    asserts.noConsoleErrors();
  });
});
