// Family SSR — DSD / hydration (lit-parity §2.12; TESSER SSR-3).
// SSR-01/02 are implemented: Tier 2 runs them against server-rendered DSD from
// Noizu.Tessera.Hologram.Render; Tier 1 reports them adapter-pending (Tier-1
// SSR is unproven). SSR-03 (framework SSR integration) stays pending. NEVER a
// release blocker (plan U8).

import {defineCase, pendingCase} from "../support/case.mjs";

// The "ssr" fixture is a counter rendered on the SERVER as a declarative
// shadow root (label "server pings", step 2). The adapter parses it with the
// HTML parser BEFORE the element upgrades and captures the server-created
// nodes in h.serverNodes ({root, label, count, inc}), then connects it so the
// runtime hydrates. Tier 2 wires it (Noizu.Tessera.Hologram.Render); Tier 1
// reports it adapter-pending.
const q = (h, cy) => h.shadowRoot.querySelector(`[data-cy="${cy}"]`);

export const cases = [
  defineCase({
    id: "SSR-01",
    family: "SSR",
    fast: true,
    title: "declarative shadow DOM renders on the server",
    async run(mount, expect) {
      const h = await mount({fixture: "ssr"});
      // The parser attached the shadow root before any element code ran, with
      // server-rendered content (props from the render call, state from init/3).
      expect(h.serverNodes, "server-created nodes captured pre-upgrade").to.exist;
      expect(h.serverNodes.label.textContent).to.equal("server pings");
      expect(h.serverNodes.count.textContent).to.equal("0");
      expect(h.shadowRoot.querySelectorAll('[data-cy="holo-counter-root"]').length).to.equal(1);
    },
  }),
  defineCase({
    id: "SSR-02",
    family: "SSR",
    fast: true,
    title: "client hydration adopts server-rendered DSD",
    async run(mount, expect) {
      const h = await mount({fixture: "ssr"});
      const server = h.serverNodes;

      h.el.dispatchAction("increment");
      await h.waitFor(() => q(h, "holo-counter-count").textContent === "2");

      // hydrated in place: one subtree, and the live nodes ARE the server's
      expect(h.shadowRoot.querySelectorAll('[data-cy="holo-counter-root"]').length).to.equal(1);
      expect(q(h, "holo-counter-count"), "count node identity").to.equal(server.count);
      expect(q(h, "holo-counter-inc"), "button identity").to.equal(server.inc);
      expect(q(h, "holo-counter-root"), "root identity").to.equal(server.root);
    },
  }),
  pendingCase({id: "SSR-03", family: "SSR", fast: false, title: "framework SSR integration renders the element", reason: "gated by brief 4c; matrix #164 (Tier 2 framework SSR) not exercised", disposition: "proven-or-accepted"}),
];