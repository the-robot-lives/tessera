defmodule HoloKit do
  @moduledoc """
  Tier 2 spike example package (`holo_kit`).

  Components here are **ordinary Hologram components** (`use
  Hologram.Component`, `init/2`, `action/3`, `~HOLO` templates, `put_state`,
  full transpilable Elixir). The tessera compile task
  (`mix tessera.compile_component`) drives Hologram's own compiler to emit
  standalone per-component bundles that `tessera-runtime` mounts inside a
  custom element's shadow root on any host (plain HTML, React, Hologram).

  The only tessera-specific surface is `HoloKit.Emit` — a two-function
  helper that gives components an `emit` path (an idiomatic `put_action/2`
  whose synthetic target the runtime intercepts and turns into a composed
  DOM `CustomEvent`).
  """

  def hologram_version, do: "0.10.1"
end
