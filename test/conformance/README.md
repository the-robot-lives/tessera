# Tessera conformance suite (Phase 4b scaffold)

The parity gate: **one behavior spec, two engine adapters**. A case is a Lit
component behavior; it passes if the tessera component behaves identically on
**Tier 1** (compiled Lit elements / `@noizu/tessera-core`) and **Tier 2**
(Hologram-in-element standalone runtime). The suite defines the expected
behavior, **not** the test runner — each tier provides its own adapter
(`docs/notes/lit-parity.md` §4.2, `docs/EXTENSION-CONTRACT.md` §9).

> **Status: SCAFFOLD.** The runner, both adapters, the tagging convention, and
> the full family structure are landed. A representative set of cases is
> implemented and green; the rest are **pending** (unimplemented features) or
> **adapter-pending** (a tier's fixture is not wired yet). Feature briefs
> (1b–1d, 2a–2f, 3c–3f) flip cases to implemented as their surface lands.

## Layout

```
test/conformance/
  README.md                  this file
  support/
    case.mjs                 defineCase / pendingCase schema + validation
    registry.mjs             aggregates all families, validates, tally()
    dom.mjs                  tier-agnostic DOM helpers (clickCy / textCy)
  cases/
    c_component.mjs          C-01…C-15   component model
    t_template.mjs           T-01…T-09   templates
    d_directive.mjs          D-01…D-07   built-in directives
    s_style.mjs              S-01…S-06   styles
    sd_slot.mjs              SD-01…SD-03 shadow-DOM slots
    e_event.mjs              E-01…E-03   events
    ct_context.mjs           CT-01…CT-02 context (accepted-with-hatch)
    lc_lifecycle.mjs         LC-01…LC-04 lifecycle hooks (placeholder, 1c/3c)
    fm_form.mjs              FM-01…FM-03 forms (placeholder, 2f/3e; provisional ids)
    rc_controller.mjs        RC-01…RC-03 reactive controllers (accepted-with-hatch)
    ssr_dsd.mjs              SSR-01…SSR-03 DSD/hydration (proven-or-accepted, 4c)
    x_extension.mjs          X-01…X-21   extension contract (EXTENSION-CONTRACT §9)
js/test/
  conformance-tier1-harness.mjs   Tier-1 fixtures + mount handle + runConformance
  conformance.tier1.test.mjs      Tier-1 FULL lane entry (default glob)
  conformance.tier1.fast.mjs      Tier-1 FAST lane entry (fast group only)
demo/e2e/src/
  support/tessera/conformance.ts  Tier-2 mount + init-wait harness
  e2e/conformance_tier2.cy.ts     Tier-2 adapter (@fast / @slow describes)
```

## Case schema

Each case (from `support/case.mjs`) is:

```js
{id, family, fast, title, status, reason, disposition, run(mount, expect)}
```

- `defineCase({id, family, fast, title, run})` — an implemented behavior.
- `pendingCase({id, family, fast, title, reason, disposition?})` — **no `run`
  function**, so it is structurally incapable of passing. `disposition` ∈
  `unimplemented` (default) · `accepted-with-hatch` (4a ballot) ·
  `proven-or-accepted` (4c SSR spike).

`run(mount, expect)` is async and uses **only** the adapter-supplied `mount`
handle and chai-style `expect`. A case never imports a runner, a fixture class,
or a tier runtime. A surface test that cannot pass identically on both tiers is
a **contract bug** — report it, don't fork the test.

### Mount handle contract (both adapters satisfy it)

`mount(spec)` → `Promise<Handle>`, where `spec = {fixture, attrs?}` and:

```
Handle = {
  el,          // the mounted custom element
  tag,         // its tag name
  shadowRoot,  // its (open) shadow root, or null for template-less fixtures
  win,         // the host window (customElements, document, Hologram stub…)
  waitFor(fn, timeout?),              // poll until fn() is truthy
  nextEvent(name, node?, timeout?),   // resolve the next event's detail
  settle(),                           // await the committed re-render
}
```

`settle()` is the tier-agnostic render fence (EXTENSION-CONTRACT §9): the
shared X-family bodies never touch `el.updateComplete` (a Lit affordance) or
Lit class fields directly — Tier 1 awaits `updateComplete`, Tier 2 flushes a
microtask + macrotask (its commit point renders synchronously inside
dispatch). Bodies also avoid snapshot KEY ORDER (§6.2 does not mandate it —
compare sorted) and read state through `el.state`, never element properties.

Fixtures: `counter` (both tiers — Tier-1 `tsr-conf-counter`, Tier-2
`tsr-holo-counter`; identical surface: `holo-counter-inc`/`-count` hooks,
`count-changed` composed+bubbling event with camelCase `{count, delta}` detail),
`props` and `events` (Tier-1 only today). Tier-2 `props`/`events` fixtures land
with the feature briefs.

**Compiled-DSL fixtures (Tier-1 only, brief 4b case-fill):** `state`,
`template`, `styles`, `slots`, `pipeline` — REAL Lit elements generated from the Elixir
element DSL (`test/support/conformance/*.ex` → `LitCodegen`), committed under
`js/test/fixtures/conformance/`. They exercise the landed Tier-1 surface
(reactive state, template expressions, the styles DSL, shadow slots, the §6
action pipeline). `pipeline` ALSO has a Tier-2 mount: `HoloKit.Components.
PipelineProbe` (`<tsr-holo-pipeline-probe>`, examples/holo_kit) is the
behavioral mirror — same state keys, same `bump`/`select_item`/`seed_cache
(internal: true)` semantics — so the shared X-05…X-11/X-20 bodies run on both
engines (§9). The other four stay Tier-1-only until their Tier-2 fixtures land.
Regenerate after a DSL/codegen change, then review the diff:

```bash
MIX_ENV=test mix run test/conformance/support/generate_fixtures.exs          # write
MIX_ENV=test mix run test/conformance/support/generate_fixtures.exs -- --check  # verify current
```

The generator rewrites the `@noizu/tessera-core` import to a relative path into
`priv/js/src` (the `js/` core tests import the source directly) and renames the
contract module `<snake>.contract.mjs` (the repo gitignores
`*.contract.generated.mjs`). Tier-2 reports these cases adapter-pending until
its compiled fixtures land.

## Honesty rule (never green for an unimplemented feature)

Two pending kinds, both reported as **skipped**, never passed:

1. **Registry-pending** — `status: "pending"`: the feature is not implemented
   (or is accepted as a documented gap). No `run` exists.
2. **Adapter-pending** — the case is implemented, but a tier's adapter does not
   yet list it in its `SUPPORTED` set (its fixture is not wired). That tier
   skips it; the other tier may run it.

The runner log prints the tally (`registry: N cases (I implemented, P pending);
tierN-supported: S`). The registry-integrity test asserts unique ids, known
families, and that both implemented and pending counts are non-zero.

## Tagging — `@fast` vs `@slow` (inherits `docs/notes/test-tiering.md`)

- **`fast: true` = behavior-defining core** — one representative per contract
  behavior; runs per-change.
- **`fast: false` = exhaustive matrices / redundant coverage** — full
  cross-products, property sweeps, accepted-gap rows; integration/nightly only.

WTR: the `fast` group runs `conformance.tier1.fast.mjs` (FAST_CASES); the default
glob runs `conformance.tier1.test.mjs` (all cases). The `.fast.mjs` suffix keeps
the full glob from double-running the fast lane.
Cypress: `@fast` / `@slow` describe tags via `@cypress/grep` (`grepFilterSpecs`).

## Running

```bash
# Tier 1 (WTR) — from js/
npm run test:fast          # core + conformance FAST lane (per-change gate)
npm test                   # full suite incl. conformance FULL lane
npm run test:conformance   # conformance FULL lane only

# Tier 2 (Cypress) — from demo/e2e/ (Hologram demo must be serving :5586)
npm run test:fast -- --spec src/e2e/conformance_tier2.cy.ts   # @fast cases
npx cypress run --spec src/e2e/conformance_tier2.cy.ts        # all cases
```

CI boots the Hologram demo on :5586 (`.github/workflows/ci.yml`); the Tier-2
adapter visits `/holo_runtime` and mounts fresh `tsr-holo-counter` instances.

## Current coverage

- **Implemented + Tier-1 green (31):** C-01, C-03, C-04, C-05, C-06, C-07,
  C-10, T-01, T-02, T-04, T-05, T-07, T-08, T-09, S-01…S-06, SD-01, SD-02,
  SD-03, E-01, E-02, E-03, X-01, X-03, X-04, X-14, X-18.
  - JS-core fixtures (`counter`/`props`/`events`): the original 13.
  - Compiled-DSL fixtures (`state`/`template`/`styles`/`slots`, brief 4b
    case-fill): C-07, T-02/T-04/T-05/T-07/T-08/T-09, S-01…S-06, SD-01/02/03,
    X-03, X-14 (18). SD-03 (fallback content) uses brief 1c's slot pre-pass.
- **Implemented + Tier-2 green (counter fixture):** C-01, T-01, E-01, E-02, E-03 (5).
- **Pending (48):** reflection / property options / lifecycle (1c — landed;
  cases owed to a follow-up 4b wave), directives classMap/styleMap/ifDefined/
  nothing + when/choose (1d), the extension surface (2a–2f/3d/3f), and the
  accepted-gap families (CT/RC/SSR). FM/RC/SSR ids are provisional placeholders.

## Owed next (not in this scaffold)

- `lit-parity.md` §4 doc extension (LC/FM/RC/SSR/X tables + §4.2 runner-rule
  text) — plan sub-step 5, routed separately.
- Tier-2 compiled-DSL fixtures (props/events/state/template/styles/slots), so
  the Tier-1-only cases above flip green on the Tier-2 runner too.
- D-CI tag wiring refinement once `epic.fast-ci` conventions settle.