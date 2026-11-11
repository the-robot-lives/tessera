defmodule Tessera.TestFixtures.Conformance.TakeoverExtAaa do
  @moduledoc """
  Depth-1 tag-takeover layer over `Takeover` (brief 2e, §5.9; X-19).

  Overrides `bump` with a PASS-THROUGH layer: fires its marker event
  `conf-ext-aaa` and down-calls the vendor via `base_action/3` (real ES
  `super` in the lowered JS). Adds no state keys — X-05's snapshot pin must
  survive the takeover. Lives in its own directory: `:inherit` in the base's
  own directory is the §5.8 clobber guard.
  """

  use Tessera.TestFixtures.Conformance.Takeover, tag: :inherit

  event("conf-ext-aaa", detail: %{layer: :string})

  action :bump, fn state, params ->
    emit("conf-ext-aaa", %{layer: "aaa"})
    base_action(:bump, state, params)
  end
end
