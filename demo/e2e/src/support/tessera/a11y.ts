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

/**
 * Serialise an axe violation node target chain (axe pierces shadow roots with
 * nested arrays) into one comparable string of segments.
 */
export function axeTargetChain(target: unknown[]): string {
  const flat: string[] = [];
  const walk = (seg: unknown): void => {
    if (typeof seg === "string") flat.push(seg);
    else if (Array.isArray(seg)) seg.forEach(walk);
  };
  walk(target);
  return flat.join(" ");
}

/** A pin tolerates EXACTLY `count` violating nodes whose FULL axe target
 * chain equals `target` (segments joined by spaces — copy it from the failure
 * message) for its rule id — never a rule-wide count, which let a NEW
 * violation of the same rule replace a fixed one one-for-one
 * (robot-review 4547688688 / TESSER-032). A leaf/suffix match is NOT enough:
 * another component's same-tagged node would still match the pin. */
export type KnownNodePin = { target: string; count: number };

function matchesPinTarget(chain: string, pinTarget: string): boolean {
  return chain === pinTarget;
}

/**
 * Pure core of the known-violation gate, split out so the guard can be proven
 * to bite without a browser (TESSER-032): returns one message per failure —
 * empty means pass.
 *
 *  1. every id in `known` must still REPRODUCE (fixed? remove the entry —
 *     no silent permanent allowlist);
 *  2. if a rule has pins, every violating node of that rule must match a
 *     pinned target (a NEW node at an unpinned target goes red — the
 *     one-for-one replacement hole is closed);
 *  3. each pinned target must see EXACTLY `count` nodes (a FIXED node —
 *     stale suppression — goes red too).
 *
 * A known rule WITHOUT pins keeps the legacy rule-wide behaviour (reproduce
 * check only).
 */
export function checkKnownViolations(
  violations: AxeViolation[],
  known: string[],
  pins?: Record<string, KnownNodePin[]>,
): string[] {
  const failures: string[] = [];
  const seen = violations.map((v) => v.id);
  known.forEach((id) => {
    if (!seen.includes(id))
      failures.push(`known violation "${id}" no longer reproduces: fixed? remove it from the allowlist`);
  });
  Object.entries(pins ?? {}).forEach(([id, rulePins]) => {
    const v = violations.find((x) => x.id === id);
    const nodes = v?.nodes ?? [];
    const chains = nodes.map((n) => axeTargetChain(n.target));
    rulePins.forEach((pin) => {
      const found = chains.filter((c) => matchesPinTarget(c, pin.target)).length;
      if (found !== pin.count)
        failures.push(
          `known violation "${id}" pinned selector "${pin.target}" node count changed` +
            ` (${pin.count} pinned, ticketed scope only${found === 0 ? " — no longer reproduces: fixed? remove the pin" : ""})`,
        );
    });
    if (rulePins.length > 0) {
      const uncovered = new Set<string>();
      chains.forEach((chain) => {
        if (!rulePins.some((pin) => matchesPinTarget(chain, pin.target)))
          uncovered.add(`known violation "${id}" node at "${chain}" is not covered by any pinned selector (ticketed scope only)`);
      });
      failures.push(...uncovered);
    }
  });
  return failures;
}

export const tesseraA11y = {
  /**
   * Inject axe-core into the page under test and assert zero violations.
   *
   * `known` lists rule ids with a documented, ticketed defect: they are
   * excluded from the zero-violation assertion BUT must still reproduce, so
   * the test goes red the moment the defect is fixed and forces the entry out
   * (no silent permanent allowlist).
   *
   * `knownPins` optionally scopes that tolerance to SPECIFIC nodes per known
   * rule id: `{ [ruleId]: [{ target, count }] }` (TESSER-032, robot-review
   * 4547688688). `target` must equal the node's FULL axe target chain
   * (shadow-piercing segments flattened, joined by spaces — copy it from the
   * failure message); `count` is exact. A new node under a different target
   * fails, and a fixed node (stale pin) fails too. The old rule-wide
   * `knownCounts` pin had a one-for-one replacement hole and is gone — pin by
   * target.
   */
  expectNoAxeViolations(known: string[] = [], knownPins?: Record<string, KnownNodePin[]>): void {
    cy.readFile("node_modules/axe-core/axe.min.js", "utf8", { log: false }).then((src) => {
      cy.window({ log: false }).then(async (win) => {
        const w = win as unknown as WinWithAxe;
        // Inject once per AUT window (PR #42 review): re-evaluating axe on every
        // call costs CI time and can leave a half-replaced global.
        // A failed or CSP-blocked injection (eval throws) or a partial/foreign
        // global is a clear assertion failure, never a TypeError (#68 review).
        let injectError: unknown = null;
        if (typeof w.axe?.run !== "function") {
          try {
            w.eval(src as string);
          } catch (e) {
            injectError = e;
          }
        }
        expect(
          typeof w.axe?.run,
          `axe-core injected into the AUT window${injectError ? ` (eval threw: ${String(injectError)})` : ""}`,
        ).to.eq("function");
        const results = await w.axe!.run(w.document, { runOnly: { type: "tag", values: AXE_TAGS } });
        const unexpected = results.violations.filter((v) => !known.includes(v.id));
        expect(unexpected, `axe violations:\n${format(unexpected)}`).to.have.length(0);
        const failures = checkKnownViolations(results.violations, known, knownPins);
        expect(failures, failures.join("\n")).to.have.length(0);
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
        // Compare normalised URLs (PR #42 review): Cypress and CDP can disagree on
        // a trailing slash or hash for the same document.
        const norm = (u: string) => u.split("#")[0].replace(/\/+$/, "");
        const matches = walk((t as { frameTree: FT }).frameTree).filter((f) => norm(f.url) === norm(href));
        // Exactly one frame must match; ambiguity would aim the AX query at the wrong document (#68 review).
        expect(matches.length, `exactly one AUT frame for ${href}`).to.eq(1);
        const aut = matches[0];
        return cdp("Accessibility.getFullAXTree", { frameId: aut!.id });
      })
      .then((res) => ((res as { nodes: AxNode[] }).nodes ?? []).filter((n) => !n.ignored));
  },

  prop(node: AxNode | undefined, name: string): unknown {
    return node?.properties?.find((p) => p.name === name)?.value?.value;
  },
};
