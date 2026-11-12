# tessera

[![hex.pm](https://img.shields.io/hexpm/v/noizu_tessera)](https://hex.pm/packages/noizu_tessera)
[![Docs](https://img.shields.io/badge/hex.pm%20docs-noizu__tessera-blue)](https://hexdocs.pm/noizu_tessera)

Framework-agnostic web components with first-class [Hologram](https://hologram.page) integration, shipped as hex packages.

- **Hex package:** [`noizu_tessera`](https://hex.pm/packages/noizu_tessera) (bare `tessera` is taken on hex.pm, and that package owns the root module `Tessera`)
- **HexDocs:** <https://hexdocs.pm/noizu_tessera>
- **Elixir namespace:** `Noizu.Tessera.*`
- **JS core:** `@noizu/tessera-core` (private registry `npm.noizu.com`)

## Goal

Write a component once as a custom element. Ship it in a hex package. A Hologram app adds the dependency, runs `mix tessera.install` and drops the component into `~HOLO`. Component events reach Hologram actions with no hand-written JS glue. The same element works in plain HTML, React, or any other framework.

## Status: **0.2.0 — Lit-parity milestone** (pre-1.0; the API may still change)

- **Two engines, one contract.** Tier 1 compiles an Elixir subset (`state` / `~TSR` template / `action`, plus a styles DSL, property options, lifecycle hooks and directives) to a real `LitElement`. Tier 2 hosts a full Hologram component inside a custom element.
- **Extension contract** on both tiers: `use Vendor.Element` derivation, same-tag takeover as layered extension (`tag: :inherit`, `priority:`), open actions, `el.state` / `dispatchAction` / `onAction`, `extendElement`, pinned `behaviors.add`. See `docs/EXTENSION-CONTRACT.md`.
- **Tooling:** interactive component gallery (`mix tessera.gen.gallery`, CEM via `mix tessera.cem`) and a Lit→tessera converter (`mix tessera.from_lit`).
- **Conformance suite** runs one shared test set on both tiers.
- **Exactly what's covered, and what isn't:** `docs/notes/lit-parity.md` (parity declaration + matrix) and `docs/notes/gap-acceptance.md` (accepted gaps). Full Tier-2 Lit parity is not claimed. Tier-2 SSR as Declarative Shadow DOM is on `develop` (unreleased): `Noizu.Tessera.Hologram.Render.element/4` renders on the server and the runtime hydrates in place. Components must define `init/3` (see the module docs). So far it is browser-proven on the HoloKit Counter only.

## Quick start — consuming (Hologram app)

Add the hex package and run the installer:

```elixir
# mix.exs
{:noizu_tessera, "~> 0.2.0"},
{:your_kit, path: "..." }   # or any hex package with `use Noizu.Tessera.Package` components
```

```sh
mix deps.get
mix tessera.install   # wires @noizu/tessera-core + lit into assets/package.json, npm install
```

```elixir
defmodule MyPage do
  use Hologram.Page
  alias PersonaKit.PersonaCard   # any tessera component module

  def template do
    ~HOLO"""
    <PersonaCard display_name="Ada" on_persona_select={:chose} />
    """
  end

  def action(:chose, params, page), do: put_state(page, params)
end
```

Nothing else to wire: the bridge is a document-level capture listener installed
by the generated adapter; events arrive as regular actions with snake-cased
detail keys. Details and binding forms (page / layout / `cid` targets):
**docs/CONSUMING.md**. The `demo/hologram_app` app is a complete DB-free host.

## Quick start — authoring a component package

```sh
mix tessera.gen.component my_widget    # spec module + .mjs skeleton + tests
```

Write the contract in the spec module (`attr`, `prop json`, `event`, `slot`,
`cy`), implement the element in the colocated `.mjs` over
`TesseraElement(LitElement, contract)`, run `mix compile` — the wire-contract
module is regenerated next to the `.mjs`. Full walkthrough: **docs/AUTHORING.md**;
package shape and `Noizu.Tessera.Package`: **docs/EXTENDING.md** (and
`examples/persona_kit` as the reference package).

## The wire contract

Everything cross-language (naming rules, `tsr-props` JSON, `data-tsr-on`
grammar `event:action@target`, re-emit pattern, byte-exact round trips):
**docs/CONTRACT.md**.

## Demos

```sh
# Hologram host — pages for stateless/cid/picker/behaviors scenarios + Link nav
# HOLOGRAM_START=1 must gate the WHOLE chain (boot hazard, see below)
cd demo/hologram_app && export HOLOGRAM_START=1 && mix deps.get && mix tessera.install && mix holo
# → http://localhost:5586  (+ /second)

# Plain HTML host — vanilla addEventListener, zero framework
cd demo/plain_html && npm install && npm run build && npm run serve
# → http://localhost:5587

# Component gallery — CEM-driven live demos + typed attr/prop/slot/CSS editors
# + event log, generated from the package (mix tessera.gen.gallery)
cd examples/persona_kit && mix compile && mix tessera.gen.gallery
npm install                          # package root: lit + @noizu/tessera-core
cd gallery && npm install && npm run build && npm run serve
# → http://localhost:5588

# Cypress e2e for all three (servers must be running)
cd demo/e2e && npm ci && npx cypress run --spec "src/e2e/*.cy.ts"
```

> **Boot hazard — export `HOLOGRAM_START=1` for the whole boot chain.** In a
> fresh Linux environment the canonical `mix deps.get && mix tessera.install
> && mix holo` chain can **hang indefinitely**: `mix deps.get` compiles path
> deps immediately, and if that compile runs *without* `HOLOGRAM_START=1`, the
> later `mix holo` (which sets it) finds the Hologram compiler already
> registered and loops forever on `Hologram: compiler already running,
> waiting...` — hologram 0.10.1 never times out. Observed twice in an
> elixir:1.18-otp-27 container, never on macOS. Exporting `HOLOGRAM_START=1`
> before `mix deps.get` (as CI does) avoids it. Details:
> `docs/CONSUMING.md` §2 and `docs/notes/e2e-linux-ci.md`.

## Docs

| Doc | |
|---|---|
| `docs/CONTRACT.md` | normative wire contract (v1) |
| `docs/AUTHORING.md` | authoring components + packages |
| `docs/CONSUMING.md` | consuming from Hologram / plain HTML |
| `docs/EXTENDING.md` | behaviors registry, bus seam, packages |
| `CHANGELOG.md` | work log |

All of the above ship on [HexDocs](https://hexdocs.pm/noizu_tessera) with every release.
