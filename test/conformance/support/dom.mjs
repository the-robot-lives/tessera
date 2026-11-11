// Tier-agnostic DOM helpers for conformance case bodies. These use ONLY the
// adapter-supplied mount handle (handle.shadowRoot) — no runner, no tier
// runtime — so a case body runs identically on Tier 1 (WTR) and Tier 2
// (Cypress Hologram-in-element). See README.md for the mount handle contract.

/** Click a shadow-DOM node by its data-cy hook (native click event). */
export function clickCy(handle, hook) {
  const node = handle.shadowRoot.querySelector(`[data-cy="${hook}"]`);
  if (!node) throw new Error(`conformance: no [data-cy="${hook}"] in <${handle.tag}> shadow root`);
  node.click();
  return node;
}

/** Trimmed textContent of a shadow-DOM node by data-cy hook ("" if absent). */
export function textCy(handle, hook) {
  const node = handle.shadowRoot.querySelector(`[data-cy="${hook}"]`);
  return node ? node.textContent.trim() : "";
}