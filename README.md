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

## Status: **Phase 1 MVP**

All three layers are live and integration-tested end to end: the Elixir spec DSL, the `@noizu/tessera-core` JS runtime, and the generated Hologram 0.10.1 adapter — plus example package, demos and a Cypress e2e suite (see `CHANGELOG.md`).

## Quick start — consuming (Hologram app)

Add the hex package and run the installer:

```elixir
# mix.exs
{:noizu_tessera, "~> 0.1.0"},
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
cd demo/hologram_app && mix deps.get && mix tessera.install && mix holo
# → http://localhost:5586  (+ /second)

# Plain HTML host — vanilla addEventListener, zero framework
cd demo/plain_html && npm install && npm run build && npm run serve
# → http://localhost:5587

# Cypress e2e for both (servers must be running)
cd demo/e2e && npm ci && npx cypress run --spec "src/e2e/*.cy.ts"
```

## Docs

| Doc | |
|---|---|
| `docs/CONTRACT.md` | normative wire contract (v1) |
| `docs/AUTHORING.md` | authoring components + packages |
| `docs/CONSUMING.md` | consuming from Hologram / plain HTML |
| `docs/EXTENDING.md` | behaviors registry, bus seam, packages |
| `CHANGELOG.md` | work log |

All of the above ship on [HexDocs](https://hexdocs.pm/noizu_tessera) with every release.
