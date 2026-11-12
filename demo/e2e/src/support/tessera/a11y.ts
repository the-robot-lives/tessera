// tessera-a11y - axe-core + accessibility-tree helpers for the a11y lane
// (TESSER-015). axe-core is a devDependency of demo/e2e only; it is injected
// into the page under test from node_modules, never shipped by the library.

/// <reference types="cypress" />

type AxeNode = { target: unknown[]; html: string };
type AxeViolation = { id: string; impact?: string | null; help: string; nodes: AxeNode[] };
type AxeResults = { violations: AxeViolation[] };
type WinWithAxe = Window & {
  eval: (src: string) => unknown;
  axe?: { run: (ctx: Document, opts: object) => Promise<AxeResults> };
};

// WCAG 2.x A/AA rule tags (axe also pierces open shadow roots natively).
const AXE_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

export type AxNode = {
  role?: { value?: string };
  name?: { value?: string };
  ignored?: boolean;
  properties?: Array<{ name: string; value: { value: unknown } }>;
};

function format(violations: AxeViolation[]): string {
  return violations
    .map((v) => `${v.id} (${v.impact}): ${v.help} -> ${v.nodes.map((n) => JSON.stringify(n.target)).join(" ")}`)
    .join("\n");
}

export const tesseraA11y = {
  /**
   * Inject axe-core into the page under test and assert zero violations.
   *
   * `known` lists rule ids with a documented, ticketed defect: they are
   * excluded from the zero-violation assertion BUT must still reproduce, so
   * the test goes red the moment the defect is fixed and forces the entry out
   * (no silent permanent allowlist).
   */
  expectNoAxeViolations(known: string[] = []): void {
    cy.readFile("node_modules/axe-core/axe.min.js", "utf8", { log: false }).then((src) => {
      cy.window({ log: false }).then(async (win) => {
        const w = win as unknown as WinWithAxe;
        w.eval(src as string);
        const results = await w.axe!.run(w.document, { runOnly: { type: "tag", values: AXE_TAGS } });
        const unexpected = results.violations.filter((v) => !known.includes(v.id));
        expect(unexpected, `axe violations:\n${format(unexpected)}`).to.have.length(0);
        const seen = results.violations.map((v) => v.id);
        known.forEach((id) =>
          expect(seen, `known violation "${id}" no longer reproduces: fixed? remove it from the allowlist`).to.include(id),
        );
      });
    });
  },

  /**
   * Full accessibility tree of the page under test (non-ignored nodes) via CDP.
   * The AUT lives in an iframe of the Cypress runner, so resolve its frame id
   * first; a bare getFullAXTree would only describe the runner UI.
   */
  axTree(): Cypress.Chainable<AxNode[]> {
    const cdp = (command: string, params?: object) =>
      Cypress.automation("remote:debugger:protocol", { command, params });
    return cy
      .location("href", { log: false })
      .then((href) => cdp("Page.getFrameTree").then((t) => ({ href, t })))
      .then(({ href, t }) => {
        type Frame = { id: string; url: string };
        type FT = { frame: Frame; childFrames?: FT[] };
        const walk = (n: FT): Frame[] => [n.frame, ...(n.childFrames ?? []).flatMap(walk)];
        const aut = walk((t as { frameTree: FT }).frameTree).find((f) => f.url === href);
        expect(aut, `AUT frame for ${href}`).to.not.eq(undefined);
        return cdp("Accessibility.getFullAXTree", { frameId: aut!.id });
      })
      .then((res) => ((res as { nodes: AxNode[] }).nodes ?? []).filter((n) => !n.ignored));
  },

  prop(node: AxNode | undefined, name: string): unknown {
    return node?.properties?.find((p) => p.name === name)?.value?.value;
  },
};
