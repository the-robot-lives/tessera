defmodule SpikeKit do
  @moduledoc """
  SpikeKit — SPIKE component package (`spike/elixir-to-lit`).

  All components are defined **fully in Elixir** — `state` + `template
  ~TSR` + `action` (and `styles` for the styles-DSL fixture) — and compiled
  at `mix compile` time into real Lit custom elements
  (`*.element.generated.mjs`) plus their contract modules and `:js` entry
  wrappers. No hand-written JS anywhere in this package (the shared style
  module `shared_styles.mjs` is the one deliberate exception — it is the
  Lit shared-styles pattern the DSL imports).

  Hosts depend on this package and run `mix tessera.install` once (same
  flow as PersonaKit); the elements also load directly as ESM or UMD in
  plain-HTML / React hosts (see demo/packaging).

  docs/notes/spike-elixir-to-lit.md is the spike write-up.
  """

  use Noizu.Tessera.Package,
    components: [SpikeKit.Counter, SpikeKit.ToggleChip, SpikeKit.StylesPanel, SpikeKit.PropsPanel]
end
