// Global support: console-error capture (CONVENTIONS §7.2 absence-of-error)
// and uncaught-exception surfacing.
//
// The capture patches console.error in window:before:load — before any app
// script runs — into a bucket on the window. Specs read it via
// tesseraAsserts.noConsoleErrors(). Uncaught exceptions (e.g. the
// NotSupportedError class from <Link> navigation) fail their test natively.

/// <reference types="cypress" />

type WinWithBucket = Window & { __tesseraConsoleErrors?: string[] };

function installConsoleCapture(win: WinWithBucket): void {
  win.__tesseraConsoleErrors = [];
  const original = win.console.error.bind(win.console);
  win.console.error = (...args: unknown[]) => {
    win.__tesseraConsoleErrors?.push(
      args
        .map((a) => (typeof a === "string" ? a : String(a)))
        .join(" "),
    );
    original(...args);
  };
}

before(() => {
  Cypress.on("window:before:load", (win) => installConsoleCapture(win as WinWithBucket));
});
