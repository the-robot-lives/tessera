// Main-page integration scenarios (a), (c), (d) of the tessera Phase 1c brief.
// Leg (b) lives in hologram_main_smoke.cy.ts (CI BLOCKING smoke job); these
// three legs are the known-red-on-Linux component-own-shadow-render cases and
// run in the NON-BLOCKING e2e-full job — see docs/notes/e2e-linux-ci.md
// (`TODO(tessera-e2e-linux)`).
// BDD: each block is a Given/When/Then narrative kept as comments
// (CONVENTIONS §7 — no .feature files).

/// <reference types="cypress" />
import { tesseraSteps as steps } from "../support/tessera/steps";
import { tesseraAsserts as asserts } from "../support/tessera/asserts";

// @slow: known-red-on-Linux component-own-shadow legs (a)/(c)/(d) — nightly /
// full lane only (continue-on-error until TODO(tessera-e2e-linux) is fixed).
describe("tessera hologram demo — main page", { tags: "@slow" }, () => {
  beforeEach(() => {
    // Given the demo app is served and the tessera elements are defined
    steps.visitHologramMain();
    steps.waitDefined("persona-card");
    steps.waitDefined("persona-picker");
    asserts.mounted("persona-card");
    asserts.mounted("persona-picker");
  });

  it("(a) stateless card click → page action → page state + internals survive", () => {
    // When the visitor clicks the panel-a card's select button twice
    steps.clickPanelACardButton();
    asserts.mainSelected("Ada Lovelace");
    asserts.mainClickCount("1");
    asserts.cardInternalText('[data-cy="panel-a"]', "internal:1");

    steps.clickPanelACardButton();
    // Then the page state reflects the SECOND detail (clickCount 2) …
    asserts.mainSelected("Ada Lovelace");
    asserts.mainClickCount("2");
    // … and the card's shadow internals (private counter) survived the
    // Hologram page re-render in between.
    asserts.cardInternalText('[data-cy="panel-a"]', "internal:2");

    asserts.noConsoleErrors();
  });

  it("(c) picker re-emits persona-picked; child persona-select stays private", () => {
    // Given the page bound only the picker's own event (on_persona_picked)
    // When the visitor picks the first card INSIDE the picker's shadow DOM
    steps.clickPickerCardButton(0);

    // Then the re-emitted persona-picked reached the page action …
    asserts.mainPicked("Ada Lovelace");
    asserts.pickerSelected("picked: Ada Lovelace");
    // … and the CHILD persona-select stayed private to the picker: the
    // page's :chose handler did not fire (panel a state untouched).
    asserts.mainSelected("");
    asserts.mainClickCount("0");

    asserts.noConsoleErrors();
  });

  it("(d) behaviors.add extension enriches a card mounted AFTER install", () => {
    // Given the behaviors extension is not installed yet
    asserts.behaviorsStatus("off");

    // When the visitor installs the behaviors, then mounts a FRESH card
    steps.clickInstallBehaviors();
    asserts.behaviorsStatus("installed");
    steps.clickMountCard();

    // Then the fresh card's connectedCallback ran the behavior …
    asserts.freshCardEnriched();
    // … and it is a live tessera element (emits + increments) whose click
    // is also enriched client-side.
    steps.clickFreshCardButton();
    asserts.freshCardClickedClass();
    asserts.cardInternalText('[data-cy="panel-d-card-mount"]', "internal:1");
    // No on_persona_select binding on this card: the page action must not fire.
    asserts.mainSelected("");

    asserts.noConsoleErrors();
  });
});
