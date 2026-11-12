// Tier 2 spike — Hologram components compiled by Hologram's own compiler,
// running as standalone custom elements in THREE hosts:
//   * Hologram page (host runtime coexistence + data-tsr-on bridge),
//   * plain HTML (extension item B + same-tag layering),
//   * React 18 UMD (ref/setProps + interception).
// Covers spike items 4, 5, A (incl. same-tag variant), B.

/// <reference types="cypress" />
import {tesseraAsserts as asserts} from "../support/tessera/asserts";

const HOLO = "http://localhost:5586";
const STATIC = "http://localhost:5589";

// item-saved payload the fancy_list element dispatches on save (camelCase —
// asserted by the "item-saved payload detail is camelCase" spec).
type Tier2SavedDetail = {itemId: number; name: string; index: number};

declare global {
  namespace Cypress {
    // Cypress's AUT-window extension seam (cypress.d.ts: `interface
    // ApplicationWindow {}` — merged into AUTWindow = Window & typeof
    // globalThis & ApplicationWindow). Lets specs read/write __tier2Saved
    // without a cast.
    interface ApplicationWindow {
      // OPTIONAL: until a spec assigns it, a read sees runtime `undefined` —
      // the type must not claim otherwise. The camelCase spec initializes it
      // (null) before registering its listener and reads it back through
      // cy.window().its("__tier2Saved"), where an uninitialized read fails
      // the deep.eq assertion instead of hiding behind the type.
      __tier2Saved?: Tier2SavedDetail | null;
    }
  }
  // Maps the element's custom DOM event name onto its payload type so the
  // addEventListener callback receives a CustomEvent<Tier2SavedDetail> —
  // the real event type, not an Event + cast.
  interface WindowEventMap {
    "item-saved": CustomEvent<Tier2SavedDetail>;
  }
}

type ListHost = {
  get: (selector: string) => Cypress.Chainable<any>;
};

// visit + scope a shadow-DOM list element, waiting for the tessera mount
// (elements upgrade asynchronously — glue/dynamic imports load the bundles).
//
// NOTE: every accessor builds a FRESH cy.get chain — Cypress subjects are
// immutable snapshots, and reusing a stored chainable across a .type() inside
// the shadow DOM leaves it stale (its re-query then misses the shadow root
// even though the element is live and mounted — verified via failure
// post-mortems).
function list(url: string, elementSelector: string): ListHost {
  cy.visit(url);
  cy
    .get(elementSelector)
    .should("exist")
    .should((node) => {
      expect(node[0].shadowRoot, `${elementSelector} mounted`).to.not.be.null;
    });
  return {
    get: (sel) => cy.get(elementSelector).shadow().find(`[data-cy="${sel}"]`),
  };
}

// shared list flows (work identically in every host/element instance)
function editFirstTo(listHost: ListHost, filter: string, newName: string) {
  // type the filter, then GATE on it having taken effect: .type() resolves
  // when key events dispatch, not when the (async) Hologram interpreter has
  // applied the draft_changed state — keyboard nav fired too early selects
  // the wrong row otherwise.
  listHost.get("holo-list-filter").clear().type(filter);
  listHost.get("holo-list-item").should("have.length", 1);
  listHost.get("holo-list-items").click().focus().type("{downarrow}{enter}", {force: true});
  listHost.get("holo-list-draft").clear().type(newName);
  listHost.get("holo-list-save").click();
}

describe("tier 2 — Hologram host (coexistence + bridge)", () => {
  beforeEach(() => {
    cy.visit(`${HOLO}/holo_runtime`);
    cy.get('[data-cy="hr-title"]', {timeout: 15000}).should("contain", "holo runtime");
    cy.get('[data-cy="panel-hr-counter"] tsr-holo-counter', {timeout: 15000})
      .shadow()
      .find('[data-cy="holo-counter-root"]')
      .should("exist");
  });

  it("counter element increments and emits over the bridge to a page action", () => {
    cy.get('[data-cy="panel-hr-counter"] tsr-holo-counter')
      .shadow()
      .find('[data-cy="holo-counter-inc"]')
      .click()
      .click()
      .click();

    cy.get('[data-cy="hr-count-value"]').should("have.text", "3");
    asserts.noConsoleErrors();
  });

  it("host client navigation keeps working with elements mounted", () => {
    cy.get('[data-cy="nav-main"] a').click();
    cy.get('[data-cy="main-title"]').should("exist");
    cy.get('[data-cy="nav-holo-runtime"] a').click();
    cy.get('[data-cy="hr-title"]').should("contain", "holo runtime");
    cy.get('[data-cy="panel-hr-counter"] tsr-holo-counter')
      .shadow()
      .find('[data-cy="holo-counter-root"]')
      .should("exist");
    asserts.noConsoleErrors();
  });

  it("vendor list: filter, keyboard nav, inline edit, validation, save via bridge", () => {
    const vendor = list(`${HOLO}/holo_runtime`, '[data-cy="panel-hr-list"] plain-list');

    // filter narrows the list and the derived count
    vendor.get("holo-list-filter").clear().type("mar");
    vendor.get("holo-list-count").should("have.text", "1");
    vendor.get("holo-list-item").should("have.length", 1).and("contain", "Mars");

    // keyboard nav selects the row, Enter opens the editor
    vendor.get("holo-list-items").click().focus().type("{downarrow}");
    vendor.get("holo-list-item").first().should("have.class", "is-selected");
    vendor.get("holo-list-items").type("{enter}");
    vendor.get("holo-list-draft").should("be.visible");

    // validation: blank rejected, duplicate rejected
    vendor.get("holo-list-draft").clear();
    vendor.get("holo-list-save").click();
    vendor.get("holo-list-error").should("contain", "blank");
    vendor.get("holo-list-draft").clear().type("Venus");
    vendor.get("holo-list-save").click();
    vendor.get("holo-list-error").should("contain", "already exists");

    // save with a rename reaches the page action through data-tsr-on
    vendor.get("holo-list-draft").clear().type("Mars II");
    vendor.get("holo-list-save").click();
    vendor.get("holo-list-item").first().should("contain", "Mars II");
    cy.get('[data-cy="hr-saved-name"]').should("have.text", "Mars II");
    cy.get('[data-cy="hr-saved-index"]').should("have.text", "3");

    // Esc cancels back out of the editor
    vendor.get("holo-list-items").click().focus().type("{downarrow}{enter}");
    vendor.get("holo-list-draft").type("{esc}");
    vendor.get("holo-list-draft").should("not.exist");
    asserts.noConsoleErrors();
  });

  it("same-tag takeover list: vendor save pipeline runs under the layer", () => {
    const tidy = list(`${HOLO}/holo_runtime`, '[data-cy="panel-hr-tidy"] tsr-holo-editable-list');

    // rename to something that does NOT case-insensitively equal the row's
    // current name — the vendor validation (rightly) rejects self-duplicates
    editFirstTo(tidy, "earth", "TERRA");

    // the layer downcases; the vendor rename/emit still ran underneath
    // ("terra" no longer matches the "earth" filter — clear it to see the row)
    tidy.get("holo-list-filter").clear();
    tidy.get("holo-list-item").eq(2).should("contain", "terra");
    cy.get('[data-cy="hr-saved-name"]').should("have.text", "terra");
    asserts.noConsoleErrors();
  });

  it("fancy list (custom tag): upcased rows + trimmed save", () => {
    const fancy = list(`${HOLO}/holo_runtime`, '[data-cy="panel-hr-fancy"] fancy-list');

    fancy.get("holo-list-item").first().should("contain", "MERCURY");

    editFirstTo(fancy, "venus", "  venus two  ");

    fancy.get("holo-list-item").first().should("contain", "VENUS TWO");
    cy.get('[data-cy="hr-saved-name"]').should("have.text", "venus two");
    asserts.noConsoleErrors();
  });
});

describe("tier 2 — plain HTML host (item B + same-tag layering)", () => {
  beforeEach(() => {
    cy.visit(`${STATIC}/plain/`);
    cy.get('[data-cy="vendor-list"]', {timeout: 15000})
      .shadow()
      .find('[data-cy="holo-list-root"]')
      .should("exist");
  });

  it("counter works with attribute props and document listeners", () => {
    cy.get('[data-cy="plain-counter"]')
      .shadow()
      .find('[data-cy="holo-counter-inc"]')
      .click();

    cy.get('[data-cy="plain-count-value"]').should("have.text", "2");
    cy.get('[data-cy="plain-count-delta"]').should("have.text", "2");
    asserts.noConsoleErrors();
  });

  it("same tag, two modules: markup element stays vendor, later element is layered", () => {
    // vendor (upgraded at define time) keeps original casing
    cy.get('[data-cy="vendor-list"]')
      .shadow()
      .find('[data-cy="holo-list-item"]')
      .first()
      .should("contain", "Mercury");

    // layered element (connected after the takeover) downcases on save
    cy.get('[data-cy="layered-list"]')
      .shadow()
      .find('[data-cy="holo-list-filter"]')
      .clear()
      .type("ven");
    cy.get('[data-cy="layered-list"]')
      .shadow()
      .find('[data-cy="holo-list-item"]')
      .should("have.length", 1);
    cy.get('[data-cy="layered-list"]')
      .shadow()
      .find('[data-cy="holo-list-items"]')
      .click()
      .focus()
      .type("{downarrow}{enter}", {force: true});
    cy.get('[data-cy="layered-list"]').shadow().find('[data-cy="holo-list-draft"]').clear().type("VENUS II");
    cy.get('[data-cy="layered-list"]').shadow().find('[data-cy="holo-list-save"]').click();
    cy.get('[data-cy="layered-list"]')
      .shadow()
      .find('[data-cy="holo-list-item"]')
      .first()
      .should("contain", "venus ii");
    asserts.noConsoleErrors();
  });

  it("composed onAction hooks run in registration order", () => {
    cy.get('[data-cy="vendor-list"]')
      .shadow()
      .find('[data-cy="holo-list-filter"]')
      .clear()
      .type("mars");
    cy.get('[data-cy="vendor-list"]')
      .shadow()
      .find('[data-cy="holo-list-items"]')
      .click()
      .focus()
      .type("{downarrow}{enter}", {force: true});

    // hook 1 strips "!", hook 2 collapses "--" — composed per keystroke
    cy.get('[data-cy="vendor-list"]').shadow().find('[data-cy="holo-list-draft"]').clear().type("Ma--rs!!");
    cy.get('[data-cy="vendor-list"]')
      .shadow()
      .find('[data-cy="holo-list-draft"]')
      .should("have.value", "Ma-rs");

    cy.get('[data-cy="vendor-list"]').shadow().find('[data-cy="holo-list-save"]').click();

    // "Ma-rs" no longer matches the active "mars" filter — clear it, then the
    // renamed row is back at its original position (index 3)
    cy.get('[data-cy="vendor-list"]').shadow().find('[data-cy="holo-list-filter"]').clear();
    cy.get('[data-cy="vendor-list"]')
      .shadow()
      .find('[data-cy="holo-list-item"]')
      .eq(3)
      .should("contain", "Ma-rs");
    asserts.noConsoleErrors();
  });

  it("dispatchAction + state snapshot (camelCase + snake alias)", () => {
    cy.get('[data-cy="select-via-dispatch"]').click();

    cy.get('[data-cy="state-camel"]').should("have.text", "3");
    cy.get('[data-cy="state-snake"]').should("have.text", "3");
    // and the selection is actually applied to the instance
    cy.get('[data-cy="vendor-list"]')
      .shadow()
      .find('[data-cy="holo-list-item"]')
      .eq(2)
      .should("have.class", "is-selected");
    asserts.noConsoleErrors();
  });

  it("fancy list: archive dispatched from host JS, upcased row reflects it", () => {
    cy.get('[data-cy="fancy-archive-btn"]').click();

    cy.get('[data-cy="fancy-archived-value"]').should("have.text", "2");
    cy.get('[data-cy="fancy-list"]')
      .shadow()
      .find('[data-cy="holo-list-item"]')
      .eq(1)
      .should("contain", "VENUS [ARCHIVED]");
    asserts.noConsoleErrors();
  });

  it("subclass overriding the documented transformProps hook", () => {
    cy.get('[data-cy="observed-list"]')
      .shadow()
      .find('[data-cy="holo-list-title"]')
      .should("contain", "Watched (observed)");
    asserts.noConsoleErrors();
  });

  it("item-saved payload detail is camelCase", () => {
    cy.window().then((win) => {
      win.__tier2Saved = null;
      win.addEventListener("item-saved", (event) => {
        win.__tier2Saved = event.detail;
      });
    });

    const vendorSelector = '[data-cy="vendor-list"]';
    cy.get(vendorSelector).shadow().find('[data-cy="holo-list-filter"]').clear().type("mars");
    cy.get(vendorSelector)
      .shadow()
      .find('[data-cy="holo-list-item"]')
      .should("have.length", 1);
    cy.get(vendorSelector)
      .shadow()
      .find('[data-cy="holo-list-items"]')
      .click()
      .focus()
      .type("{downarrow}{enter}", {force: true});
    cy.get(vendorSelector).shadow().find('[data-cy="holo-list-draft"]').clear().type("Mars X");
    cy.get(vendorSelector).shadow().find('[data-cy="holo-list-save"]').click();

    cy.window().its("__tier2Saved").should("deep.eq", {
      itemId: 4,
      name: "Mars X",
      index: 3,
    });
    asserts.noConsoleErrors();
  });
});

describe("tier 2 — React host", () => {
  beforeEach(() => {
    cy.visit(`${STATIC}/react/`);
    cy.get('[data-cy="react-tsr-holo-editable-list"]', {timeout: 15000})
      .shadow()
      .find('[data-cy="holo-list-root"]')
      .should("exist");
  });

  it("counter + list work under React with ref-based props", () => {
    cy.get('[data-cy="react-counter"]')
      .shadow()
      .find('[data-cy="holo-counter-inc"]')
      .click();

    cy.get('[data-cy="react-count-value"]').should("have.text", "1");

    const vendor = cy.get('[data-cy="react-tsr-holo-editable-list"]');
    vendor.shadow().find('[data-cy="holo-list-item"]').should("have.length", 4);
    asserts.noConsoleErrors();
  });

  it("save emits into a React listener with camelCase detail", () => {
    const listSel = '[data-cy="react-tsr-holo-editable-list"]';
    cy.get(listSel).shadow().find('[data-cy="holo-list-filter"]').clear().type("merc");
    cy.get(listSel).shadow().find('[data-cy="holo-list-item"]').should("have.length", 1);
    cy.get(listSel)
      .shadow()
      .find('[data-cy="holo-list-items"]')
      .click()
      .focus()
      .type("{downarrow}{enter}", {force: true});
    cy.get(listSel).shadow().find('[data-cy="holo-list-draft"]').clear().type("Mercury Prime");
    cy.get(listSel).shadow().find('[data-cy="holo-list-save"]').click();

    cy.get('[data-cy="react-saved"]').should("have.text", "Mercury Prime@1");
    asserts.noConsoleErrors();
  });

  it("onAction rewrites dispatched params before the interpreter runs", () => {
    cy.get('[data-cy="react-dispatch"]').click();

    // React dispatched id 4; the hook forced id 1 — both spellings agree
    cy.get('[data-cy="react-state"]').should("have.text", "1/1");
    cy.get('[data-cy="react-tsr-holo-editable-list"]')
      .shadow()
      .find('[data-cy="holo-list-item"]')
      .first()
      .should("have.class", "is-selected");
    asserts.noConsoleErrors();
  });

  it("dispatchAction(archive) from React mutates fancy rows", () => {
    cy.get('[data-cy="react-archive"]').click();

    cy.get('[data-cy="react-fancy-list"]')
      .shadow()
      .find('[data-cy="holo-list-item"]')
      .first()
      .should("contain", "MERCURY [ARCHIVED]");
    asserts.noConsoleErrors();
  });
});
