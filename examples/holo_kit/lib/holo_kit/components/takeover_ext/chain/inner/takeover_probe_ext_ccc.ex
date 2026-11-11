defmodule HoloKit.Components.TakeoverProbeExtCcc do
  @moduledoc """
  Depth-3 tag-takeover layer — `use TakeoverProbeExtBbb, tag: :inherit`
  (brief 3f, §5.9; X-19 — the canonical-macro mirror of `TakeoverExtCcc`).

  An extension derived from another extension sits OUTSIDE everything it
  extends (dependency order beats priority), so this is the OUTERMOST layer
  of the chain. On Tier 2 the wrapper mounts THIS module for the taken-over
  tag: its compiled `base_action/3` spine contains every layer (ccc → bbb →
  aaa → vendor), which is exactly why the Tier-2 fixture chain is linear —
  a sibling outside the spine would never run (no `super` in Hologram's IR).
  Overrides `bump` again with a pass-through + marker event `conf-ext-ccc`
  (synchronous via `Emit.js_emit/2`): dispatching `bump` traces
  `["ccc", "aaa"]` through the spine into the vendor — outermost runs
  first, every layer down-calls, the vendor still runs last (Bbb never
  overrides `bump`).
  """

  use HoloKit.Components.TakeoverProbeExtBbb, tag: :inherit, overrides: [:bump]

  def action(:bump, params, component) do
    HoloKit.Emit.js_emit(:conf_ext_ccc, %{layer: "ccc"})
    base_action(:bump, params, component)
  end
end
