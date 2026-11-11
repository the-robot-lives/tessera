defmodule Tessera.TestFixtures.Conformance.TakeoverExtCcc do
  @moduledoc """
  Depth-2 tag-takeover layer — `use TakeoverExtBbb, tag: :inherit` (brief 2e,
  §5.9; X-19).

  An extension derived from another extension sits OUTSIDE everything it
  extends (dependency order beats priority), so this is the OUTERMOST layer of
  the chain even though Aaa/Bbb have "lower" names. Overrides `bump` again
  with a pass-through + marker event `conf-ext-ccc`: dispatching `bump` traces
  `["ccc", "aaa"]` through the ES `super` chain into the vendor — outermost
  runs first, every layer down-calls, the vendor still runs last.

  Lives one directory deeper than Bbb (its base) for the same §5.8 clobber
  reason as the other layers.
  """

  use Tessera.TestFixtures.Conformance.TakeoverExtBbb, tag: :inherit

  event("conf-ext-ccc", detail: %{layer: :string})

  action(:bump, fn state, params ->
    emit("conf-ext-ccc", %{layer: "ccc"})
    base_action(:bump, state, params)
  end)
end
