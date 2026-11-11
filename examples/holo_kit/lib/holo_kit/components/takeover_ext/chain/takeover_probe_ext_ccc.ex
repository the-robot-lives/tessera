defmodule HoloKit.Components.TakeoverProbeExtCcc do
  @moduledoc """
  Depth-2 tag-takeover layer — `use TakeoverProbeExtBbb, tag: :inherit`
  (brief 3f, §5.9; X-19 — the canonical-macro mirror of `TakeoverExtCcc`).

  An extension derived from another extension sits OUTSIDE everything it
  extends (dependency order beats priority), so this is the OUTERMOST layer
  of the chain even though Aaa/Bbb have "lower" names. Overrides `bump`
  again with a pass-through + marker event `conf-ext-ccc`: dispatching
  `bump` traces `["ccc", "aaa"]` through the `base_action/3` chain into the
  vendor — outermost runs first, every layer down-calls, the vendor still
  runs last (Bbb never overrides `bump`).
  """

  use HoloKit.Components.TakeoverProbeExtBbb, tag: :inherit

  def action(:bump, params, component) do
    component = HoloKit.Emit.emit(component, :conf_ext_ccc, %{layer: "ccc"})
    base_action(:bump, params, component)
  end
end
