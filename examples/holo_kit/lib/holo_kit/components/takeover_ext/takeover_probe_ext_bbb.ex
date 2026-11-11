defmodule HoloKit.Components.TakeoverProbeExtBbb do
  @moduledoc """
  Depth-1 tag-takeover layer over `TakeoverProbe` with `priority: 10`
  (brief 3f, §5.9; X-19 — the canonical-macro mirror of `TakeoverExtBbb`).

  Same depth as `TakeoverProbeExtAaa` but HIGHER priority ⇒ it sits OUTSIDE
  Aaa in the chain (§5.9 tie order: depth → priority → module name). It
  overrides `select_item` only — so `bump` never touches this layer, proving
  per-action chain routing rather than whole-class replacement. Pass-through
  + marker event `conf-ext-bbb`; no state keys added.
  """

  use HoloKit.Components.TakeoverProbe, tag: :inherit, priority: 10

  def action(:select_item, params, component) do
    component = HoloKit.Emit.emit(component, :conf_ext_bbb, %{layer: "bbb"})
    base_action(:select_item, params, component)
  end
end
