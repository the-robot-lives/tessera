defmodule Tessera.TestFixtures.Conformance.Takeover do
  @moduledoc """
  `<tsr-conf-takeover>` — base fixture for the D1 tag-takeover chain (brief 2e,
  EXTENSION-CONTRACT.md §5.9; case X-19).

  A structural MIRROR of `Pipeline`: same three state keys, same action
  semantics, same `internal:` annotation, and deliberately the SAME `data-cy`
  names. X-19's gate is "the base tag's conformance suite MUST still pass on
  the taken-over element", which it proves by replaying the pipeline case
  bodies VERBATIM against a mount pinned to this fixture.

  Three `tag: :inherit` layers take it over (in `takeover_ext/`):

    * `TakeoverExtAaa` — depth 1, overrides `bump` with a pass-through + marker
      event `conf-ext-aaa`;
    * `TakeoverExtBbb` — depth 1 but `priority: 10` (sits OUTSIDE Aaa),
      overrides `select_item` (+ `conf-ext-bbb`);
    * `TakeoverExtCcc` — depth 2 (`use TakeoverExtBbb, tag: :inherit`),
      overrides `bump` again (+ `conf-ext-ccc`).

  Chain (innermost → outermost): base, Aaa (d1 p0), Bbb (d1 p10), Ccc (d2).
  Layers add NO state keys, so the snapshot pinned by X-05 survives replay.
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-takeover", js: "conf_takeover.mjs"

  state(:count, :integer, default: 0)
  state(:selected_id, :string, default: "none")
  state(:meta, :map, default: %{depth: 1})

  event("conf-takeover-ping", detail: %{count: :integer})

  cy("conf-pipeline-root")

  template ~TSR"""
  <div data-cy="conf-pipeline-root">
    <button type="button" data-cy="conf-pipeline-inc" $click={:bump}>+</button>
    <span data-cy="conf-pipeline-count">{@count}</span>
    <span data-cy="conf-pipeline-selected">{@selected_id}</span>
  </div>
  """

  action :bump, fn state, params ->
    %{state | count: state.count + (if params.step do params.step else 1 end)}
  end

  action :select_item, fn state, params ->
    %{state | selected_id: params.item_name, count: state.count + 1}
  end

  action :seed_cache, fn state, _params ->
    emit("conf-takeover-ping", %{count: state.count})
    state
  end, internal: true
end
