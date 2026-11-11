defmodule Tessera.TestFixtures.Conformance.Pipeline do
  @moduledoc """
  `<tsr-conf-pipeline>` — conformance fixture for the extension action
  pipeline + state snapshot (EXTENSION-CONTRACT.md §6; brief 2a).

  Three state keys exercise the §6.2 snapshot surface: `count` (round-trips
  to itself), `selected_id` (snake → camel alias) and `meta` (nested value —
  shared by reference, NEVER deep-frozen). Actions: `bump` (reads
  `params.step` — the X-08 override path), `select_item` (changes TWO keys in
  one transition — the X-06 one-event rule; reads `params.item_name` — the
  X-20 end-to-end case normalization), and `seed_cache` (`internal: true` —
  open dispatch still works, interception warns-once, D2/§10).

  Cases: X-05…X-11, X-20 (Tier-1). ExUnit pins the compile-side half of
  X-20 (non-round-tripping state key fails compilation) in component_test.
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-pipeline", js: "conf_pipeline.mjs"

  state(:count, :integer, default: 0)
  state(:selected_id, :string, default: "none")
  state(:meta, :map, default: %{depth: 1})

  event("conf-pipeline-ping", detail: %{count: :integer})

  cy("conf-pipeline-root")

  template(~TSR"""
  <div data-cy="conf-pipeline-root">
    <button type="button" data-cy="conf-pipeline-inc" $click={:bump}>+</button>
    <span data-cy="conf-pipeline-count">{@count}</span>
    <span data-cy="conf-pipeline-selected">{@selected_id}</span>
  </div>
  """)

  action(:bump, fn state, params ->
    %{
      state
      | count:
          state.count +
            if params.step do
              params.step
            else
              1
            end
    }
  end)

  action(:select_item, fn state, params ->
    %{state | selected_id: params.item_name, count: state.count + 1}
  end)

  action(
    :seed_cache,
    fn state, _params ->
      emit("conf-pipeline-ping", %{count: state.count})
      state
    end,
    internal: true
  )
end
