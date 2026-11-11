defmodule HoloKit.Components.TakeoverProbeDerived do
  @moduledoc """
  FRESH-tag derivation over `TakeoverProbe` (brief 3f, case X-16 — the
  Tier-2 analogue of a new-tag `use Base, tag: "…"`: the extender becomes
  its OWN element while the inherited action surface stays reachable through
  the injected `base_action/3` chain).

  Inherits the full §6.1 OPEN surface (bump / select_item / seed_cache) via
  the chain and adds ONE new action `:reset` (count → 0) — proving the
  merged surface (inherited + new) on a second registered tag while the
  base tag's fixture mounts untouched.
  """

  use HoloKit.Components.TakeoverProbe, tag: "tsr-holo-takeover-derived", actions: [:reset]

  def action(:reset, _params, component) do
    Hologram.Component.put_state(component, count: 0)
  end
end
