defmodule HoloKit.Components.TakeoverProbe do
  @moduledoc """
  `<tsr-holo-takeover-probe>` — Tier-2 conformance fixture for the §5.9
  tag-takeover chain (brief 3f, case X-19; the canonical-macro mirror of the
  Tier-1 compiled-DSL `tsr-conf-takeover` fixture —
  `test/support/conformance/conf_takeover.ex`).

  A structural mirror of `PipelineProbe`: same three state keys, same action
  semantics, same `internal:` annotation on `seed_cache`, and deliberately
  the SAME `data-cy` names. X-19's gate is "the base tag's conformance suite
  MUST still pass on the taken-over element", which it proves by replaying
  the pipeline case bodies VERBATIM against a mount pinned to this fixture.

  Three `tag: :inherit` layers take it over (in `takeover_ext/` (the §5.8 clobber guard keeps layers out of the vendor's own directory)). TIER-2 SHAPE: Hologram's IR has no `super` — a layer's compiled `base_action/3` chain is its `derived_from` spine — so the chain is LINEAR (each layer extends the previous); the Tier-1 fixture composes sibling layers through real ES `super`, the wrapper-side counterpart of the same §5.9 order.

    * `TakeoverProbeExtAaa` — depth 1, overrides `bump` with a pass-through +
      marker event `conf-ext-aaa`;
    * `TakeoverProbeExtBbb` — depth 2 (`use TakeoverProbeExtAaa, tag: :inherit`,
      `priority: 10` declared — depth decides on a linear spine), overrides
      `select_item` (+ `conf-ext-bbb`);
    * `TakeoverProbeExtCcc` — depth 3 (`use TakeoverProbeExtBbb, tag: :inherit`),
      overrides `bump` again (+ `conf-ext-ccc`). The WRAPPER mounts Ccc for the
      taken-over tag: its spine contains every layer.

  Chain (innermost → outermost): base, Aaa (d1), Bbb (d2 p10), Ccc (d3).
  Layers add NO state keys, so the snapshot pinned by X-05 survives replay.
  Layer markers fire synchronously via `HoloKit.Emit.js_emit/2` —
  `put_action/2` holds a single `next_action`, so one dispatch's multiple
  markers would overwrite each other through the bridge.

  NO catch-all `action/3` clause: an unknown name raises the boxed
  `%FunctionClauseError{}` the Tier-2 shim classifies into the §6.3
  `unknown-action` result (X-07) — through every layer of the chain.
  """

  use Hologram.Component

  use Noizu.Tessera.Component.Extension,
    tag: "tsr-holo-takeover-probe",
    actions: [:bump, :select_item, :seed_cache],
    internal_actions: [:seed_cache],
    template: """
    <div class="tsr-takeover-probe" data-cy="conf-pipeline-root">
      <button type="button" data-cy="conf-pipeline-inc" $click={:bump}>+</button>
      <span class="tsr-takeover-probe-count" data-cy="conf-pipeline-count">{@count}</span>
      <span class="tsr-takeover-probe-selected" data-cy="conf-pipeline-selected">{@selected_id}</span>
    </div>
    """

  def init(props, component) do
    component
    |> HoloKit.Emit.mount(props)
    |> Hologram.Component.put_state(count: 0, selected_id: "none", meta: %{depth: 1})
  end

  def __tessera_init__(props, component), do: init(props, component)

  def __tessera_init__(props, component, _server), do: init(props, component)

  def action(:bump, params, component) do
    step = Map.get(params, :step) || 1
    count = Map.get(component.state, :count, 0) + step

    Hologram.Component.put_state(component, count: count)
  end

  def action(:select_item, params, component) do
    Hologram.Component.put_state(component,
      selected_id: Map.get(params, :item_name),
      count: Map.get(component.state, :count, 0) + 1
    )
  end

  # internal: true (D2/§10, via `internal_actions:`) — open dispatch works,
  # interception warns-once, unchanged state = zero-change commit (keys: []).
  def action(:seed_cache, _params, component) do
    HoloKit.Emit.emit(component, :conf_takeover_ping, %{
      count: Map.get(component.state, :count, 0)
    })
  end
end
