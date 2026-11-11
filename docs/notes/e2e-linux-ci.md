# e2e job red on Linux CI — findings (`TODO(tessera-e2e-linux)`)

Status: **open**. The e2e legs are split across two CI jobs (see
`.github/workflows/ci.yml`): **`e2e-smoke` is BLOCKING** and runs the legs
that are green on Linux (plain_html 2/2, hologram_nav 1/1, hologram_main leg
(b)), while **`e2e-full` is non-blocking** (`continue-on-error: true`) and
runs the three failing hologram_main legs (a)/(c)/(d). The suite fails on
GitHub's ubuntu runners while the identical specs pass locally (macOS,
headless Electron) — and the toolchain was ruled out (see below). A red
`e2e-full` must still be triaged, it just does not block; the ExUnit, js and
e2e-smoke jobs are hard gates and green. Upstream-drift watch: the weekly
`canary` workflow compiles + tests against `noizu-forks/hologram@dev`
(`TESSERA_HOLOGRAM=git`).

## Symptoms

Run 42810142823 (commit de350d6, ubuntu-latest, Elixir 1.18.4 / OTP 27,
Cypress 15.20.0 / Electron 138 headless):

- `hologram_main.cy.ts`: 1/4 — `(b)` passes; `(a)`, `(c)`, `(d)` fail, each
  identically on both retry attempts (persistent, not flaky):
  - `(a)`: page state asserts GREEN (`main-selected` = Ada, `main-click-count`
    = 1 — the action round trip and page patch worked), then the card's own
    shadow text never shows `internal:1` (screenshot: `internal:0`).
  - `(c)`: page `picked: Ada Lovelace` GREEN (the re-emit landed), then the
    picker's own shadow text never shows `picked: Ada Lovelace`
    (screenshot: `picked: none`, all inner cards `internal:0`).
  - `(d)`: the `install-behaviors` click (Hologram action with `JS.call` +
    component `put_state`) never reflects — status stays `behaviors: off`.
- `hologram_nav.cy.ts` 1/1 green, `plain_html.cy.ts` 2/2 green — including the
  plain-page assertion that the card's internal counter reaches `internal:2`
  after two clicks. So **pure Lit `requestUpdate()` re-renders work fine on
  Linux** in the plain host.

The failure signature: the component's own shadow-DOM state (client-side
`requestUpdate()` renders in the same handler that emits — emits demonstrably
ran) never reflects under the Hologram host on Linux, while Hologram page-level
state + patches work. Same code passes on macOS.

## Ruled out

1. **Elixir/OTP toolchain**: booted the demo locally under asdf Elixir
   1.18.4-otp-28 (CI's exact Elixir line) — 4/4 `hologram_main` green.
2. **Linux browser**: ran the specs in the official `cypress/included:15.20.0`
   container (Linux Electron 138, same browser CI resolves) against the
   mac-hosted 1.18 server — diagnostic probes for all three failing
   mechanisms green: the panel-a card host node is NOT replaced by the page
   patch (`data-tsr-probe` survives, counter updates), the picker's own state
   renders, `install-behaviors` flips to `behaviors: installed`, console-error
   bucket empty.
3. **Case-sensitivity / untracked files** (classic mac→Linux CI gaps): all
   spec/component files tracked with matching case; the round-1 404 on
   `*.contract.generated.mjs` was a separate issue, fixed in the js job.
4. **Formatter/toolchain drift** broke exunit in round 1 — fixed
   (03dda6e); **inotify-tools** absence crashed the demo boot in round 1 —
   fixed (03dda6e); **persona_kit node_modules** missing for the plain-demo
   esbuild in round 2 — fixed (de350d6).

## Bundle comparison (mac build vs linux build)

**Not obtained.** The Linux server container never finished booting: `mix holo`
stalled for 20+ minutes repeating
`Hologram: compiler already running, waiting...` — the compile-lock stall
below — so there is no Linux-built bundle to diff and no Linux-server +
Linux-browser cold-run cell. Investigation was timeboxed here.

## Boot-recipe hazard found while reproducing (separate from the assert failures)

The canonical boot chain `mix deps.get && mix tessera.install && mix holo`
can **hang indefinitely** in a fresh Linux environment: `mix deps.get`
compiles path deps immediately, and if that compile runs *without*
`HOLOGRAM_START=1`, a later `mix holo` (which sets it) finds the Hologram
compiler registered and loops forever on
`Hologram: compiler already running, waiting...` (hologram 0.10.1 never
times out). Observed twice in an elixir:1.18-otp-27 container, never on
macOS. The CI `e2e` boot step now exports `HOLOGRAM_START=1` for the whole
chain as a hardening (03dda6e-era workflow, kept in this commit).

Two more installer rough edges surfaced by the same repro:

- `mix tessera.install` dies with a raw `ErlangError :enoent` when `npm`
  is not on PATH (elixir docker images ship no node) — should surface a
  friendly "npm not found" instead.
- The generated `assets/package.json` embeds a **host-absolute** `file:`
  path for `@noizu/tessera-core` when the resolved dep lives outside the
  app tree (Elixir ≥1.20 keeps path deps there; `Path.relative_to/2` falls
  back to the absolute path instead of emitting `../` traversal), making the
  generated tree non-relocatable. Unaffected on CI (dep sits inside `deps/`)
  — fix owed in `tessera_core_relpath`/`Installer.additions`.

## Next hypotheses

- Run the last matrix cell (Linux-built server + Linux browser, cold boot →
  immediate clicks, 2-core-throttled) and diff the served bundles: if the
  Linux-built client bundle differs byte-wise from the mac-built one, inspect
  what the transpiler emitted differently.
- If bundles are byte-identical and the cell still fails, capture the
  in-page console-error bucket + a DOM instance-identity probe on CI itself
  (temporary diagnostic spec behind an env flag) before touching any product
  code.
