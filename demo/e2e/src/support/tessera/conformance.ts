// Tier-2 conformance harness — Hologram-in-element (Cypress).
//
// lit-parity §4.2 / EXTENSION-CONTRACT §9: Tier 2 runs the SAME tier-agnostic
// cases as Tier 1, mounted as standalone Hologram custom elements with an init
// wait. The host is the demo Hologram app's /holo_runtime page, whose glue
// registers `tsr-holo-counter` (HoloKit.Components.Counter) via the
// priv/tessera_holo runtime.
//
// Mount handle contract (identical to Tier 1 — see test/conformance/README.md):
//   { el, tag, shadowRoot, win, waitFor(fn, timeout?), nextEvent(name, node?, timeout?) }
//
// Case bodies are pure DOM + awaited plain promises (no cy commands inside a
// case), so the shared Tier-1 bodies run here unchanged. The window is captured
// ONCE in visitTier2Host(); mount() then creates a fresh element and polls for
// its shadow mount (the runtime mounts asynchronously — the init wait). Every
// accessor uses the live element, never a stale Cypress subject snapshot.

/// <reference types="cypress" />

const HOLO: string = Cypress.env("tsrHoloUrl") ?? "http://localhost:5586";

export type ConformanceHandle = {
  el: HTMLElement;
  tag: string;
  shadowRoot: ShadowRoot;
  win: Window;
  waitFor: (fn: () => boolean, timeout?: number) => Promise<void>;
  nextEvent: (name: string, node?: EventTarget, timeout?: number) => Promise<any>;
};

// Tier-2 fixture tags. The shared counter (C/T/E family) + the state probe
// (extension-contract X family — HoloKit.Components.StateProbe, behaviorally
// the Hologram mirror of the Tier-1 `tsr-conf-state` fixture). Cases outside
// these fixtures are adapter-pending on Tier 2 (their fixtures land with the
// remaining feature briefs).
const FIXTURES: Record<string, string> = {
  counter: "tsr-holo-counter",
  state: "tsr-holo-state-probe",
};

let ctx: {win: Window} | null = null;
const mounted: HTMLElement[] = [];

/** Visit the Hologram-in-element host and capture the AUT window (init wait). */
export function visitTier2Host(): void {
  cy.visit(`${HOLO}/holo_runtime`);
  cy.get('[data-cy="hr-title"]', {timeout: 15_000}).should("contain", "holo runtime");
  cy.window({log: false}).then((win) => {
    ctx = {win: win as unknown as Window};
  });
  // Prove the runtime registered + mounted a counter before any case runs.
  cy.get('[data-cy="panel-hr-counter"] tsr-holo-counter', {timeout: 15_000})
    .shadow()
    .find('[data-cy="holo-counter-root"]')
    .should("exist");
}

function makeWaitFor(win: Window) {
  return (fn: () => boolean, timeout = 5_000): Promise<void> =>
    new Promise((resolve, reject) => {
      const start = Date.now();
      const tick = () => {
        let ok = false;
        try {
          ok = fn();
        } catch {
          ok = false;
        }
        if (ok) return resolve();
        if (Date.now() - start > timeout) return reject(new Error("conformance: waitFor timed out"));
        win.setTimeout(tick, 25);
      };
      tick();
    });
}

function makeNextEvent(win: Window) {
  return (name: string, node: EventTarget = win.document, timeout = 5_000): Promise<any> =>
    new Promise((resolve, reject) => {
      const timer = win.setTimeout(() => {
        node.removeEventListener(name, handler);
        reject(new Error(`conformance: nextEvent("${name}") timed out`));
      }, timeout);
      function handler(event: Event) {
        win.clearTimeout(timer);
        node.removeEventListener(name, handler);
        resolve((event as CustomEvent).detail);
      }
      node.addEventListener(name, handler);
    });
}

/**
 * mount(spec) — create a fresh fixture element on the host page, apply attrs,
 * connect it, and wait for the runtime to mount its shadow root (init wait).
 */
export function mount(spec: {fixture: string; attrs?: Record<string, string>}): Promise<ConformanceHandle> {
  const tag = FIXTURES[spec.fixture];
  if (!tag) return Promise.reject(new Error(`conformance: unknown Tier-2 fixture "${spec.fixture}"`));
  if (!ctx) return Promise.reject(new Error("conformance: visitTier2Host() must run before mount()"));
  const win = ctx.win;
  return new Promise((resolve, reject) => {
    const el = win.document.createElement(tag);
    for (const [name, value] of Object.entries(spec.attrs ?? {})) el.setAttribute(name, value);
    win.document.body.appendChild(el);
    mounted.push(el);
    const start = Date.now();
    const wait = () => {
      const sr = el.shadowRoot;
      if (sr) {
        resolve({el, tag, shadowRoot: sr, win, waitFor: makeWaitFor(win), nextEvent: makeNextEvent(win)});
      } else if (Date.now() - start > 15_000) {
        reject(new Error(`conformance: <${tag}> never mounted a shadow root`));
      } else {
        win.setTimeout(wait, 25);
      }
    };
    wait();
  });
}

/** afterEach cleanup — remove mounted elements (pure DOM, no cy command). */
export function cleanup(): void {
  if (!ctx) return;
  while (mounted.length) {
    const el = mounted.pop();
    el?.remove();
  }
}