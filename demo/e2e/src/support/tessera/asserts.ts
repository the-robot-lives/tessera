// tessera-asserts — namespaced assertions for the tessera demo suites
// (tobor-kit CONVENTIONS §7.2: mount proof + absence-of-error + behavior).

/// <reference types="cypress" />

type WinWithBucket = Window & { __tesseraConsoleErrors?: string[] };

export const tesseraAsserts = {
  /** Mount proof — element exists, is upgraded, and has its contract hook. */
  mounted(tag: string): void {
    cy.get(tag).should("exist");
    cy.window({ log: false }).then((win) => {
      expect(
        (win as WinWithBucket & { customElements: CustomElementRegistry }).customElements.get(tag),
        `${tag} upgraded`,
      ).to.not.eq(null);
    });
  },

  /** Absence-of-error (CONVENTIONS §7 requirement 2): console.error bucket empty. */
  noConsoleErrors(): void {
    cy.window({ log: false }).then((win) => {
      expect(
        (win as WinWithBucket).__tesseraConsoleErrors ?? [],
        "no console.error on page",
      ).to.deep.eq([]);
    });
  },

  // — panel (a): stateless card → page state ——

  mainSelected(value: string): void {
    cy.get('[data-cy="main-selected"]').should("contain", value);
  },

  mainClickCount(value: string): void {
    cy.get('[data-cy="main-click-count"]').should("contain", value);
  },

  // — panel (b): cid-targeted card ——

  mainCidConfirmed(value: string): void {
    cy.get('[data-cy="main-cid-confirmed"]').should("contain", value);
  },

  // — panel (c): picker re-emit ——

  mainPicked(value: string): void {
    cy.get('[data-cy="main-picked"]').should("contain", value);
  },

  pickerSelected(value: string): void {
    cy.get("persona-picker")
      .shadow()
      .find('[data-cy="persona-picker-selected"]')
      .should("contain", value);
  },

  // — panel (d): behaviors extension ——

  behaviorsStatus(value: string): void {
    cy.get('[data-cy="behaviors-status"]').should("contain", value);
  },

  freshCardEnriched(): void {
    cy.get('[data-cy="panel-d-card-mount"] persona-card').should(
      "have.attr",
      "data-tessera-enriched",
      "true",
    );
  },

  freshCardClickedClass(): void {
    cy.get('[data-cy="panel-d-card-mount"] persona-card').should(
      "have.class",
      "tsr-demo-clicked",
    );
  },

  // — shadow internals (re-render survival) ——

  cardInternalText(scope: string, expected: string): void {
    cy.get(`${scope} persona-card`)
      .shadow()
      .find('[data-cy="persona-card-internal"]')
      .should("contain", expected);
  },

  // — plain-HTML demo ——

  plainLogLine(index: number, expected: string): void {
    cy.get('[data-cy="plain-log-line"]')
      .eq(index)
      .should("contain", expected);
  },

  // — component gallery (mix tessera.gen.gallery) ——

  /** The gallery lists `tag` with a live, upgraded demo element. */
  galleryLists(tag: string): void {
    cy.get(`[data-cy="gallery-component"][data-tag="${tag}"]`).within(() => {
      cy.get('[data-cy="gallery-component-tag"]').should("contain", `<${tag}>`);
      cy.get(`[data-cy="gallery-demo"] ${tag}`).should("exist");
    });
    cy.window({ log: false }).then((win) => {
      expect(
        (win as WinWithBucket & { customElements: CustomElementRegistry }).customElements.get(tag),
        `${tag} upgraded`,
      ).to.not.eq(null);
    });
  },

  /** A line in `tag`'s gallery event log (name + camelCase detail JSON). */
  galleryLogLine(tag: string, index: number, expected: string): void {
    cy.get(`[data-cy="gallery-component"][data-tag="${tag}"] [data-cy="gallery-log-line"]`)
      .eq(index)
      .should("contain", expected);
  },
};
