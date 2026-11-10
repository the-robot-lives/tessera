/**
 * Demo extension module (docs/EXTENDING.md §2 — behaviors.add).
 *
 * `installDemoBehaviors()` registers a behavior for `<persona-card>` that
 * marks every connected instance with `data-tessera-enriched="true"` and
 * toggles a `tsr-demo-clicked` class on click. Called from
 * `EnrichedPanel.action(:install_behaviors)` (client-side JS interop), so
 * cards mounted AFTER the install are enriched on connect — the demo mounts
 * one dynamically to prove exactly that.
 */

import { behaviors } from "@noizu/tessera-core";

function enrich(el) {
  el.dataset.tesseraEnriched = "true";

  const onClick = () => {
    el.classList.add("tsr-demo-clicked");
  };

  el.addEventListener("click", onClick);

  return () => {
    el.removeEventListener("click", onClick);
  };
}

export function installDemoBehaviors() {
  behaviors.add("persona-card", enrich);
}
