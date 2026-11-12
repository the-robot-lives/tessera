// Accessibility lane (TESSER-015, BoE need #5): axe-core over the static demo
// host plus an aria-live-inside-shadow-root check.
//
// Lane: @fast (about 1s of test time). Needs only the plain-HTML host (:5587,
// already booted by the fast CI lane).
//
// TESSER-018 extends the same lane to the hosts the fast lane cannot boot,
// tagged @slow so ONLY the nightly e2e-full job runs them (nightly boots every
// host before `npm test`; the fast lane's grepTags=@fast + grepFilterSpecs
// never even loads this file's @slow describes):
//   * the Tier-2 static hosts on :5589 (/plain/, /react/, /ssr/) — UMD
//     bundles from `mix tessera.bundles`, served by demo/holo_element/serve.mjs;
//   * the Hologram demo on :5586 (HOLOGRAM_START=1 mix holo).
//
// HONESTY: Cypress cannot hear a screen reader. "Announces" is asserted as
// the strongest machine-checkable proxy: the live region is present in
// Chromium's accessibility tree (CDP Accessibility.getFullAXTree) with
// role=status and live=polite, and its text updates on a user action.

/// <reference types="cypress" />
import { tesseraA11y as a11y } from "../support/tessera/a11y";

const PLAIN: string = Cypress.env("tsrPlainUrl") ?? "http://localhost:5587";
const TIER2: string = Cypress.env("tsrTier2Url") ?? "http://localhost:5589";
const HOLO: string = Cypress.env("tsrHoloUrl") ?? "http://localhost:5586";

/**
 * Waits until EVERY custom element matching `hostSelector` (not just the
 * first — robot-review 4547531352) has BOTH a shadow root and
 * `shadowSelector` rendered inside it (elements upgrade asynchronously — the
 * UMD glue dynamically imports the module bundle — and axe must never run on
 * a half-mounted page or the assertion itself becomes the flake).
 */
function waitShadowReady(hostSelector: string, shadowSelector: string): void {
  cy.get(hostSelector).should(($el) => {
    expect($el.length, `host matched: ${hostSelector}`).to.be.greaterThan(0);
    $el.each((_i, el) => {
      expect((el as HTMLElement).shadowRoot, `shadow root attached: ${hostSelector}`).to.not.eq(null);
    });
  });
  cy.get(hostSelector).each(($el) => {
    cy.wrap($el).shadow().find(shadowSelector).should("exist");
  });
}

describe("tessera a11y: axe over the plain-HTML host", { tags: "@fast" }, () => {
  it("index.html (persona-card / persona-picker, shadow DOM) has no axe violations", () => {
    cy.visit(`${PLAIN}/`);
    cy.get("persona-card").should("exist");
    cy.get("persona-card").first().shadow().find('[data-cy="persona-card-btn"]').should("exist");
    a11y.expectNoAxeViolations();
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

// — TESSER-018: nightly-only coverage of the Tier-2 static hosts (:5589) ——
// Documented, ticketed defects go in KNOWN with their ticket key (the helper
// still asserts each of them REPRODUCES, so fixing one turns the test red and
// forces the entry out). Real violations found by this lane are NEVER pinned
// without a ticket.
// TESSER-024: the editable-list/fancy-list <ul role="listbox"> used to render
// with no accessible name (axe aria-input-field-name, serious) on every tier-2
// host that mounts it — it was pinned here (4 nodes on /plain/, 2 on /react/)
// until the fix gave the listbox aria-label={@title}; the entry is gone and
// every host below requires zero violations again.

describe("tessera a11y: axe over the Tier-2 static hosts (:5589)", { tags: "@slow" }, () => {
  it("/plain/ (counter + editable/fancy lists, shadow DOM) has no axe violations", () => {
    cy.visit(`${TIER2}/plain/`);
    waitShadowReady('[data-cy="plain-counter"]', '[data-cy="holo-counter-count"]');
    waitShadowReady('[data-cy="vendor-list"]', '[data-cy="holo-list-items"]');
    waitShadowReady('[data-cy="layered-list"]', '[data-cy="holo-list-items"]');
    waitShadowReady('[data-cy="fancy-list"]', '[data-cy="holo-list-items"]');
    waitShadowReady('[data-cy="observed-list"]', '[data-cy="holo-list-items"]');
    // TESSER-024 fixed: the 4 listboxes must be named, not pinned.
    a11y.expectNoAxeViolations();
  });

  it("/react/ (React-rendered counter + lists) has no axe violations", () => {
    cy.visit(`${TIER2}/react/`);
    waitShadowReady('[data-cy="react-counter"]', '[data-cy="holo-counter-count"]');
    waitShadowReady('[data-cy="react-tsr-holo-editable-list"]', '[data-cy="holo-list-items"]');
    waitShadowReady('[data-cy="react-fancy-list"]', '[data-cy="holo-list-items"]');
    // TESSER-024 fixed: the 2 React-host listboxes must be named, not pinned.
    a11y.expectNoAxeViolations();
  });

  it("/ssr/ (declarative shadow DOM counter) has no axe violations", () => {
    cy.visit(`${TIER2}/ssr/`);
    waitShadowReady("#ssr-counter", '[data-cy="holo-counter-count"]');
    a11y.expectNoAxeViolations([]);
  });
});

describe("tessera a11y: axe over the Hologram demo (:5586)", { tags: "@slow" }, () => {
  it("main page (persona-card / persona-picker, shadow DOM) has no axe violations", () => {
    cy.visit(`${HOLO}/`);
    waitShadowReady("persona-card", '[data-cy="persona-card-btn"]');
    waitShadowReady("persona-picker", '[data-cy="persona-picker-panel"]');
    // The Hologram runtime does a ONE-SHOT body takeover shortly after boot
    // (verified locally: a body-appended node is gone within ~1.5s). Settle
    // past it, then RE-ASSERT readiness so axe always scans the FINAL,
    // post-takeover DOM (robot-review 4547531345: no fixed-wait-only scan of
    // a transient DOM; in CI the re-assert is a no-op if no takeover ran).
    cy.wait(1500);
    waitShadowReady("persona-card", '[data-cy="persona-card-btn"]');
    waitShadowReady("persona-picker", '[data-cy="persona-picker-panel"]');
    a11y.expectNoAxeViolations([]);
  });
});
