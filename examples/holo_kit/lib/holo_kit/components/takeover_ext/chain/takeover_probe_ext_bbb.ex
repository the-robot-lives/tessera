defmodule HoloKit.Components.TakeoverProbeExtBbb do
  @moduledoc """
  Depth-2 tag-takeover layer — `use TakeoverProbeExtAaa, tag: :inherit`,
  declared with `priority: 10` (brief 3f, §5.9; X-19 — the canonical-macro
  mirror of `TakeoverExtBbb`).

  TIER-2 SHAPE NOTE: the Tier-1 fixture composes SIBLING depth-1 layers
  (Aaa + priority-10 Bbb) through real ES `super` in one class. Hologram's
  IR has no `super` — a Tier-2 layer's compiled `base_action/3` chain is its
  `derived_from` SPINE — so the Tier-2 mirror linearises: Bbb extends Aaa,
  and the priority option stays declared (exercising option parsing +
  spec capture) while dependency depth decides the order. Overrides
  `select_item` only — so `bump` never touches this layer, proving per-action
  chain routing rather than whole-class replacement. Pass-through + marker
  event `conf-ext-bbb` (synchronous via `Emit.js_emit/2`); no state keys
  added.
  """

  use HoloKit.Components.TakeoverProbeExtAaa, tag: :inherit, priority: 10, overrides: [:select_item]

  def action(:select_item, params, component) do
    HoloKit.Emit.js_emit(:conf_ext_bbb, %{layer: "bbb"})
    base_action(:select_item, params, component)
  end
end
