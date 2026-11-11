defmodule SpikeKit do
  @moduledoc """
  SpikeKit — SPIKE component package (`spike/elixir-to-lit`).

  Both components are defined **fully in Elixir** — `state` + `template
  ~TSR` + `action` — and compiled at `mix compile` time into real Lit
  custom elements (`*.element.generated.mjs`) plus their contract modules
  and `:js` entry wrappers. No hand-written JS anywhere in this package.

  Hosts depend on this package and run `mix tessera.install` once (same
  flow as PersonaKit); the elements also load directly as ESM or UMD in
  plain-HTML / React hosts (see demo/packaging).

  docs/notes/spike-elixir-to-lit.md is the spike write-up.
  """

  use Noizu.Tessera.Package,
    components: [SpikeKit.Counter, SpikeKit.ToggleChip]
end
