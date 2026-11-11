defmodule Tessera.TestFixtures.BareThing do
  @moduledoc false
  # Minimal fixture: a string attr only — no json props, no events, no slots,
  # no cy. Used to assert the adapter omits tsr-props / data-tsr-on when there
  # is nothing to bind.
  use Noizu.Tessera.Component, tag: "bare-thing", js: "bare_thing.mjs"

  attr :label, :string, required: true
end
