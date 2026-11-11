defmodule Tessera.TestFixtures.Conformance.TakeoverExtBbb do
  @moduledoc """
  Depth-1 tag-takeover layer over `Takeover` with `priority: 10` (brief 2e,
  §5.9; X-19).

  Same depth as `TakeoverExtAaa` but HIGHER priority ⇒ it sits OUTSIDE Aaa in
  the chain (§5.9 tie order: depth → priority → module name). It overrides
  `select_item` only — so `bump` never touches this layer, proving per-action
  chain routing rather than whole-class replacement. Pass-through + marker
  event `conf-ext-bbb`; no state keys added.
  """

  use Tessera.TestFixtures.Conformance.Takeover, tag: :inherit, priority: 10

  event("conf-ext-bbb", detail: %{layer: :string})

  action :select_item, fn state, params ->
    emit("conf-ext-bbb", %{layer: "bbb"})
    base_action(:select_item, state, params)
  end
end
