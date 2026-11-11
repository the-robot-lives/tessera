# Test tiering — fast per-change vs integration vs nightly

Owner expedite directive: feature branches squash into epics, skip PR CI gates,
and do not run the slow suites on every change — **without dropping defect
detection**. This note is the convention every suite (including the future
Phase 4b `test/conformance/` acceptance suite) inherits.

The core claim of the library is **shadow-DOM event → `dispatchAction` →
Hologram action → re-render**. The blocking `e2e-smoke` job proves it and stays
in the **fast** lane (and the integration lane). It is never gated away.

## Lanes

| Lane | Trigger | ExUnit | WTR | Cypress | Blocking? |
|---|---|---|---|---|---|
| **FAST** (per-change gate) | push `feature/**`, `epic.**`; PR → `epic.**`/`develop`/`stage`/`main` | `mix test.fast` (lib + persona_kit) | `js` `npm run test:fast` | `npm run test:fast` (`@fast`) | **yes** — incl. `e2e-smoke` |
| **INTEGRATION** | push `develop`/`stage`/`main` (epic→develop regular merge) | full `mix test` | `js` full + persona_kit | `e2e-smoke` (`@fast`) | **yes** |
| **NIGHTLY** | `nightly.yml` schedule (daily) + manual | full `mix test --cover` | — | `npm test` (all hosts, `@slow` red Linux legs) | no (`continue-on-error`) |
| **CANARY** | `canary.yml` weekly (Mon) + manual | full vs `noizu-forks/hologram@dev` | — | — | no |

`ci.yml` carries FAST + INTEGRATION (lane jobs gated by `if:` on event/ref;
`e2e-smoke` has no `if:` so every in-scope push/PR carries the core claim).
`nightly.yml` carries the slow non-blocking coverage. No job uses `needs:`
(skip-propagation house rule). A red nightly is triaged, never a merge gate.

## ExUnit

- Tag genuinely slow tests `@tag :slow` (heavy, >~1s, non-core) or
  `@tag :nightly` (exhaustive matrices / redundant coverage).
- `mix test.fast` (alias in `mix.exs` and `examples/persona_kit/mix.exs`) runs
  `mix test --exclude slow --exclude nightly`. Plain `mix test` runs **everything**.
- **Current state:** the whole ExUnit suite is sub-second (174 lib tests ≈ 0.9s,
  5 persona_kit tests ≈ 0.03s), so **no test carries `:slow`/`:nightly` today**.
  The alias is the convention hook; the exclusion mechanism is verified (a
  `:slow` + `:nightly` probe is excluded by `test.fast`, included by `test`).

## WTR (`js/`, `@noizu/tessera-core`)

- `web-test-runner.config.mjs` defines a `fast` group; the default `files` glob
  is the FULL suite. `npm run test:fast` → `wtr --group fast`; `npm test` →
  `wtr --group default` (full). Both run the `assert-no-lit` packaging guard.
- **FAST group** (behavior-defining core): `bridge`, `element` (plain
  HTMLElement), `events`, `bus` (behaviors), `define` (defineOnce), `index`
  (public surface). 71 tests ≈ 0.9s.
- **FULL-only** (per-host matrix + redundant coverage): `element.lit.test.mjs`
  (TesseraElement over LitElement — the second host), `element.copies.test.mjs`
  and `bridge.copies.test.mjs` (duplicate-module-copy / Hologram-bundle
  singletons). Full = 80 tests ≈ 1.1s.
- The Lit host is **still covered in the fast lane** end to end: the demo
  components extend `TesseraElement(LitElement, …)`, so the blocking `e2e-smoke`
  exercises it. Deferring the Lit *unit matrix* to full drops no fast-lane claim.
- Shared fixtures/helpers live in `js/test/helpers.mjs` (not a `.test.mjs`, so
  WTR never runs it as a suite).

## Cypress (`demo/e2e/`)

- `@cypress/grep` (v7) tags + `grepFilterSpecs` (skip loading non-matching specs).
  Tags are set via `describe(..., { tags: "@fast" | "@slow" }, ...)`.
- `npm run test:fast` → `cypress run --expose grepTags=@fast` (core-claim smoke +
  quick specs). `npm run test:slow` → `grepTags=@slow`. `npm test` → all hosts.
- **`@fast`** (the blocking smoke set, Linux-green): `plain_html.cy.ts` (2),
  `conformance_tier2.cy.ts` fast lane (the wired Tier-2 cases; pending skipped),
  `hologram_nav.cy.ts` (1), `hologram_main_smoke.cy.ts` (leg b, 1).
- **`@slow`** (nightly/full only): `hologram_main.cy.ts` legs a/c/d (3) — the
  known-red-on-Linux component-own-shadow cases, `TODO(tessera-e2e-linux)`,
  `docs/notes/e2e-linux-ci.md` — plus `spike_lit.cy.ts` (the elixir-to-lit spike's
  exhaustive Hologram/plain/React host matrix) and `gallery.cy.ts` (7 — the
  component vitrine is NOT part of the shadow-event core claim, so it moved out
  of the fast gate; the nightly `e2e-full` boots the gallery :5588 and keeps the
  coverage). Non-blocking (`continue-on-error`) until the red legs are fixed.
  The nightly plain-demo boot builds the spike bundles
  (`examples/spike_kit` `npm run build:bundles` → `demo/plain_html/dist`) so the
  spike's UMD/ESM/React hosts resolve; the nightly also boots the tier-2 static
  hosts (:5589, `demo/holo_element`) for the untagged `holo_runtime_element.cy.ts`.
- Untagged specs (`holo_runtime_element.cy.ts`) run only in the FULL suite
  (`grepFilterSpecs` skips them under a tag filter).

### e2e-smoke boot contract (fast gate)

- The Hologram demo serves the Tier-2 standalone bundles from
  `priv/static/tessera` (endpoint `Plug.Static`). They are emitted by
  **`mix tessera.bundles`** (demo alias → `mix tessera.compile_component
  HoloKit.Components.EditableList HoloKit.Components.Counter
  ThirdParty.FancyList ThirdParty.TidyList --out priv/static/tessera`).
  `mix tessera.install` only wires assets/npm — it does NOT emit bundles.
  The emit step MUST run before `mix holo`; without it the `/holo_runtime`
  glue 404s on `tessera-runtime.esm.js` and every spec asserting
  `noConsoleErrors()` fails (the historical e2e-smoke RED bug).
- The two core-claim demos (Hologram :5586, plain-HTML :5587) boot
  **in parallel** (install→build→boot→readiness chains run concurrently;
  wall = max, not sum) and ONE boot is reused for every `@fast` spec.
  The gallery :5588 is not booted in the fast gate.
- CI caches the demo `deps/_build` (incremental mix compile) and the
  persona_kit / plain_html / e2e `node_modules` + Cypress binary
  (`actions/cache`, npm installs skipped on cache hit).

## Local acceptance runner (`scripts/acceptance.sh`)

The local mirror of the FAST lane: ExUnit fast (lib + persona_kit) + WTR fast +
WTR conformance (Tier-1) run concurrently, then e2e-smoke (parallel demo boots,
one boot for all `@fast` specs). Warm-cache target: well under 2 minutes.
Installs are skipped when `node_modules`/`deps` exist; demos are stopped on exit
(`KEEP_DEMOS=1` to debug). Per-component + total wall-clock is printed; any
failing component exits non-zero.

## Acceptance / conformance (Phase 4b `test/conformance/`) — inherited convention

The future conformance suite MUST follow the same split:

- **`@fast` = behavior-defining assertions** — the minimal set that pins each
  contract behavior (one representative per behavior). Runs per-change.
- **`@slow` = exhaustive per-host matrices / redundant coverage** — the full
  cross-product (every host × every DSL entry × every edge), property sweeps,
  and any assertion already implied by a `@fast` behavior test. Nightly only.

Do not put exhaustive matrices in the fast/acceptance path. There is **no slow
redundant coverage in the acceptance path today** (the conformance suite does not
exist yet); the redundant coverage that *did* exist — the WTR Lit-host matrix and
cross-module-copy tests — was moved to the FULL group above.

## Measured (local, Elixir 1.20/OTP 29, node 26 — CI pins 1.18/OTP 27, node 24)

| Suite | Before (full, per change) | After (fast, per change) |
|---|---|---|
| ExUnit (lib) | 174 tests ≈ 0.9s | `test.fast` 174 ≈ 0.9s (none slow yet) |
| WTR core | 80 tests ≈ 1.2s | fast 71 ≈ 1.1s |
| Cypress | smoke 4 + full 3 + spike 3 hosts (double demo boot) | `@fast` 4 (single boot) |

The dominant per-change cost is the **e2e demo boot**, not the unit suites. The
tiering win is structural: feature/epic pushes now get a fast gate (previously no
CI ran on those branches), the red Linux legs + their second demo boot moved to
nightly, and the unit suites have a fast subset ready for the conformance growth.

### Acceptance pass wall-clock (`scripts/acceptance.sh`, warm cache)

Baseline (serial boots, gallery in gate, no bundle emit → RED) ≈ **109s**.
After the bundle-emit fix + parallel boots + gallery prune + caches ≈ **23s**:

| Component | Wall |
|---|---|
| ExUnit fast (lib) | 3s |
| ExUnit fast (persona_kit) | 2s |
| WTR fast | 5s |
| WTR conformance (Tier-1) | 4s |
| — unit phase (the four run concurrently) | **5s** |
| Demo boots :5586 + :5587 (parallel) | 7s |
| Cypress `@fast` (one boot, all specs) | 11s |
| — e2e phase | **18s** |
| **Total** | **23s** |

The core-claim gate stays **non-vacuous**: with the Tier-2 bundle emit removed
(`priv/static/tessera/tessera-runtime.esm.js` deleted) the smoke/conformance
specs fail on the console-error / mount assertions; re-emitting (`mix
tessera.bundles`) restores green. The Tier-2 Cypress adapter gives each case a
fresh host visit and hands the tier-agnostic async case to Cypress via `.then`
(a bare cross-realm returned promise was torn down mid-await), so the shared
case bodies run unchanged and still detect a broken emit.