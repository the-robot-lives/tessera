// tessera-steps — namespaced step functions for the tessera demo suites
// (tobor-kit CONVENTIONS §7.1: no describe/it here, only actions).

/// <reference types="cypress" />

// Base URLs are env-overridable (--env tsrHoloUrl=… / tsrPlainUrl=…) so the
// suite can run against demos in containers / other hosts (CI, dockerized
// browser against a host server) without touching the specs.
const HOLOGRAM: string = Cypress.env("tsrHoloUrl") ?? "http://localhost:5586";
const PLAIN: string = Cypress.env("tsrPlainUrl") ?? "http://localhost:5587";
const GALLERY: string = Cypress.env("tsrGalleryUrl") ?? "http://localhost:5588";

export const tesseraSteps = {
  visitHologramMain(): void {
    cy.visit(`${HOLOGRAM}/`);
  },

  visitHologramSecond(): void {
    cy.visit(`${HOLOGRAM}/second`);
  },

  visitPlain(): void {
    cy.visit(`${PLAIN}/`);
  },

  visitGallery(): void {
    cy.visit(`${GALLERY}/`);
  },

  /**
   * Set a gallery JSON editor's value and fire `input` — for brace-heavy
   * payloads where Cypress `.type` would parse `{}` as special sequences.
   */
  setGalleryJson(selector: string, value: string): void {
    cy.get(selector).then(($el) => {
      const node = $el[0] as HTMLTextAreaElement | HTMLInputElement;
      node.value = value;
      node.dispatchEvent(new Event("input", { bubbles: true }));
    });
  },

  /** Mount proof (CONVENTIONS §7 requirement 1): the custom element is DEFINED. */
  waitDefined(tag: string, timeout = 15_000): void {
    cy.window({ log: false }).then((win) => {
      return (win as Window & { customElements: CustomElementRegistry }).customElements.whenDefined(
        tag,
      );
    });
  },

  /** Navigate via the layout's <Link> (client-side Hologram navigation). */
  clickNavLink(cyHook: string): void {
    cy.get(`[data-cy="${cyHook}"]`).children().first().click();
  },

  clickPanelACardButton(): void {
    cy.get('[data-cy="panel-a"] persona-card')
      .shadow()
      .find('[data-cy="persona-card-btn"]')
      .click();
  },

  clickPanelBCardButton(): void {
    cy.get('[data-cy="panel-b-inner"] persona-card')
      .shadow()
      .find('[data-cy="persona-card-btn"]')
      .click();
  },

  /** The picker composes persona-cards INSIDE its shadow DOM — two shadows deep. */
  clickPickerCardButton(index: number): void {
    cy.get("persona-picker")
      .shadow()
      .find("persona-card")
      .eq(index)
      .shadow()
      .find('[data-cy="persona-card-btn"]')
      .click();
  },

  clickInstallBehaviors(): void {
    cy.get('[data-cy="install-behaviors"]').click();
  },

  clickMountCard(): void {
    cy.get('[data-cy="mount-card"]').click();
  },

  clickFreshCardButton(): void {
    cy.get('[data-cy="panel-d-card-mount"] persona-card')
      .shadow()
      .find('[data-cy="persona-card-btn"]')
      .click();
  },
};
