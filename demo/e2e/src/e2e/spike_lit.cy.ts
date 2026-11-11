// SPIKE (spike/elixir-to-lit) — the generated Lit elements in three hosts:
//
//   1. Hologram host  — /spike page of demo/hologram_app; on_chip_select /
//      on_count_change land in page actions with snake_cased params (the
//      bridge snake-cases the camelCase detail keys back).
//   2. plain HTML     — demo/plain_html/spike.html; UMD bundles only
//      (window.Tessera.<Component>) + vanilla addEventListener.
//   3. React host     — demo/plain_html/react.html; React 18 CDN renders the
//      elements, shared-runtime ESM variant via import map.
//
// BDD: each block is a Given/When/Then narrative kept as comments
// (CONVENTIONS §7 — no .feature files).
//
// @slow: exhaustive per-host spike matrix (Hologram / plain / React) — nightly /
// full lane only, not the fast per-change gate (docs/notes/test-tiering.md).

/// <reference types="cypress" />
import { tesseraSteps as steps } from "../support/tessera/steps";
import { tesseraAsserts as asserts } from "../support/tessera/asserts";

const HOLOGRAM: string = Cypress.env("tsrHoloUrl") ?? "http://localhost:5586";
const PLAIN: string = Cypress.env("tsrPlainUrl") ?? "http://localhost:5587";

function clickInc(scope = "") {
  cy.get(`${scope} spike-counter`).shadow().find('[data-cy="spike-counter-inc"]').click();
}

function clickChipRow(scope: string, index = 0) {
  cy.get(`${scope} spike-toggle-chip`)
    .eq(index)
    .shadow()
    .find('[data-cy="spike-chip-root"]')
    .click();
}

describe("spike/elixir-to-lit — Hologram host (element DSL → generated element)", { tags: "@slow" }, () => {
  beforeEach(() => {
    // Given the /spike page is served and both generated elements are defined
    cy.visit(`${HOLOGRAM}/spike`);
    steps.waitDefined("spike-counter");
    steps.waitDefined("spike-toggle-chip");
    asserts.mounted("spike-counter");
    asserts.mounted("spike-toggle-chip");
  });

  it("counter action → count-change → page action with snake_cased params", () => {
    // When the visitor clicks increment twice (step=1)
    clickInc('[data-cy="spike-counter-panel"]');
    clickInc('[data-cy="spike-counter-panel"]');

    // Then the page action (:counted) received %{count: n} and re-rendered
    cy.get('[data-cy="spike-counted"]').should("contain", "2");
    asserts.noConsoleErrors();
  });

  it("chip toggle → chip-select → page :chose with params.chip_id", () => {
    // When the visitor toggles the first chip then the second
    clickChipRow('[data-cy="spike-chips-panel"]', 0);
    clickChipRow('[data-cy="spike-chips-panel"]', 1);

    // Then the page state shows the LAST chip with snake_cased keys intact
    cy.get('[data-cy="spike-chose"]').should("contain", "holo-7 [on]");
    cy.get('[data-cy="spike-chose-count"]').should("contain", "2");

    // And toggling the same chip off flips the mark (selected: false param)
    clickChipRow('[data-cy="spike-chips-panel"]', 1);
    cy.get('[data-cy="spike-chose"]').should("contain", "holo-7 [off]");
    asserts.noConsoleErrors();
  });

  it("chip local state re-renders its own template branch", () => {
    // When the visitor toggles the first chip (local selected flips)
    clickChipRow('[data-cy="spike-chips-panel"]', 0);

    // Then the element's own shadow DOM switched branch AND bumped clicks
    cy.get('[data-cy="spike-chips-panel"] spike-toggle-chip')
      .eq(0)
      .shadow()
      .find(".dot")
      .should("contain", "*");
    cy.get('[data-cy="spike-chips-panel"] spike-toggle-chip')
      .eq(0)
      .shadow()
      .find('[data-cy="spike-chip-clicks"]')
      .should("contain", "1");
  });
});

describe("spike/elixir-to-lit — plain HTML host (UMD + vanilla listeners)", { tags: "@slow" }, () => {
  beforeEach(() => {
    cy.visit(`${PLAIN}/spike.html`);
    steps.waitDefined("spike-counter");
    steps.waitDefined("spike-toggle-chip");
  });

  it("UMD bundles merge into window.Tessera.<Component>", () => {
    cy.window({ log: false }).then((win) => {
      const tessera = (win as Window & { Tessera?: Record<string, unknown> }).Tessera;
      expect(tessera, "window.Tessera").to.not.eq(undefined);
      const keys = Object.keys(tessera!).sort();
      expect(keys).to.include.members(["Counter", "ToggleChip"]);
      expect(typeof tessera!.Counter, "Counter is the class alias").to.eq("function");
      expect(typeof tessera!.register, "register re-exported").to.eq("function");
    });
  });

  it("counter (step=2 attr) emits count-change to a vanilla listener", () => {
    // When the visitor clicks increment once
    clickInc('[data-cy="spike-counter-panel"]');

    // Then the shadow DOM shows 2 (attr-coerced step) and the vanilla
    // document listener logged the camelCase detail map
    cy.get('[data-cy="spike-counter-panel"] spike-counter')
      .shadow()
      .find('[data-cy="spike-counter-count"]')
      .should("contain", "2");
    asserts.plainLogLine(0, '"count":2');
    asserts.plainLogLine(0, '"delta":2');
    asserts.noConsoleErrors();
  });

  it("chip-select reaches the vanilla listener with camelCase detail", () => {
    clickChipRow('[data-cy="spike-chips-panel"]', 1);

    asserts.plainLogLine(0, '"chipId":"persona-7"');
    asserts.plainLogLine(0, '"selected":true');
    asserts.noConsoleErrors();
  });
});

describe("spike/elixir-to-lit — React host (CDN React + shared-runtime ESM variant)", { tags: "@slow" }, () => {
  beforeEach(() => {
    cy.visit(`${PLAIN}/react.html`);
    steps.waitDefined("spike-counter");
    steps.waitDefined("spike-toggle-chip");
  });

  it("React renders the elements; events drive React state", () => {
    // When the visitor clicks increment then the chip
    clickInc();
    clickChipRow('[data-cy="react-root"]', 0);

    // Then React state updated from the composed events
    cy.get('[data-cy="react-count"]').should("contain", "counter count-change count: 1");
    cy.get('[data-cy="react-last-chip"]').should("contain", "last chip-select: r-1 ✓");

    // And the shared runtime served BOTH elements as one module instance
    cy.window({ log: false }).then((win) => {
      expect((win as Window & { Tessera?: unknown }).Tessera, "no UMD namespace here").to.eq(undefined);
    });
    asserts.noConsoleErrors();
  });
});
