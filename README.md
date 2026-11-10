# tessera

Framework-agnostic web components with first-class [Hologram](https://hologram.page) integration, shipped as hex packages.

- **Hex package:** `noizu_tessera` (bare `tessera` is taken on hex.pm, and that package owns the root module `Tessera`)
- **Elixir namespace:** `Noizu.Tessera.*`
- **JS core:** `@noizu/tessera-core` (private registry `npm.noizu.com`)

## Goal

Write a component once as a custom element. Ship it in a hex package. A Hologram app adds the dependency, runs `mix tessera.install` and drops the component into `~HOLO`. Component events reach Hologram actions with no hand-written JS glue. The same element works in plain HTML, React, or any other framework.

## Architecture (planned)

| Layer | Role |
|---|---|
| JS core `@noizu/tessera-core` | `TesseraElement` mixin, `defineOnce`, `emit`, JSON-props, document-level event bridge (CustomEvent → `Hologram.dispatchAction`), `BusClient` seam, behaviors registry |
| Elixir spec `use Noizu.Tessera.Component` | Single source of truth: attrs, props, events, slots, cy hooks. Generates the Custom Elements Manifest, JS contract, TS types and the Hologram adapter |
| Hologram adapter | Generated Hologram component that renders the tag, maps props and events, and `js_import`s the element |

Status: **phase 0 (bridge spike)**. See `CHANGELOG.md`.
