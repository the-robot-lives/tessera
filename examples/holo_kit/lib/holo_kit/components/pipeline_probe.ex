defmodule HoloKit.Components.PipelineProbe do
  @moduledoc """
  `<tsr-holo-pipeline-probe>` — Tier-2 conformance fixture for the extension
  contract's action pipeline + state snapshot (EXTENSION-CONTRACT §6, brief
  reconcile; the Hologram-component mirror of the Tier-1 compiled-DSL
  `tsr-conf-pipeline` fixture — `test/support/conformance/conf_pipeline.ex`).

  IDENTICAL logical surface, so the ONE shared tier-agnostic body set
  (X-05…X-11, X-20) passes on both engines (§9 runtime equivalence):

    * state `count` (round-trips to itself), `selected_id` (snake → camel
      alias), `meta` (nested value — shared by reference, never deep-frozen,
      X-05) and NOTHING else, so snapshot key sets compare exactly.
    * `bump` reads `params.step` (default 1) — the X-08 override path.
    * `select_item` sets `selected_id` from `params.item_name` AND increments
      `count` — the X-06 two-keys-one-event transition; the X-20 end-to-end
      case normalization.
    * `seed_cache` is `internal: true` (advisory, D2/§10): it emits
      `conf_pipeline_ping` (`conf-pipeline-ping` on the wire) and returns the
      state UNCHANGED — the zero-change commit that still fires exactly one
      `tsr-state-change` with `keys: []` (X-06).

  The `__tsr_actions__/0` + `__tsr_internal_actions__/0` exports feed the
  standalone bundle manifest (`component_manifest` in
  `lib/noizu/tessera/hologram/standalone.ex`), giving Tier 2 the §6.1
  `tesseraActions` static and the §6.4 internal-registration warn-once —
  the same descriptor the Tier-1 codegen passes to `TesseraElement`.

  NO catch-all `action/3` clause: dispatching an unknown name raises
  Hologram's boxed `%FunctionClauseError{}` for `action/3`, which the Tier-2
  shim classifies into the §6.3 `unknown-action` result (X-07).
  """

  use Hologram.Component

  def init(props, component) do
    component
    |> HoloKit.Emit.mount(props)
    |> Hologram.Component.put_state(count: 0, selected_id: "none", meta: %{depth: 1})
  end

  # Mirrors conf_pipeline's `bump`: `params.step` (either casing — the shim
  # normalizes) defaulting to 1.
  def action(:bump, params, component) do
    step = Map.get(params, :step) || 1
    count = Map.get(component.state, :count, 0) + step

    Hologram.Component.put_state(component, count: count)
  end

  # TWO keys in ONE transition (X-06) + the snake param key `item_name`
  # (X-20). Mirrors `%{state | selected_id: params.item_name, count: state.count + 1}`.
  def action(:select_item, params, component) do
    Hologram.Component.put_state(component,
      selected_id: Map.get(params, :item_name),
      count: Map.get(component.state, :count, 0) + 1
    )
  end

  # internal: true — open dispatch still works, interception warns-once, and
  # the unchanged-state return is the zero-change commit (keys: [] event).
  def action(:seed_cache, _params, component) do
    HoloKit.Emit.emit(component, :conf_pipeline_ping, %{count: Map.get(component.state, :count, 0)})
  end

  @doc "Every declared action, snake atoms, declaration order (§6.1 OPEN surface)."
  def __tsr_actions__, do: [:bump, :select_item, :seed_cache]

  @doc "The `internal: true` subset — advisory warn-once only (D2/§10)."
  def __tsr_internal_actions__, do: [:seed_cache]

  def template do
    ~HOLO"""
    <div class="tsr-pipeline-probe" data-cy="conf-pipeline-root">
      <button type="button" data-cy="conf-pipeline-inc" $click={:bump}>+</button>
      <span class="tsr-pipeline-probe-count" data-cy="conf-pipeline-count">{@count}</span>
      <span class="tsr-pipeline-probe-selected" data-cy="conf-pipeline-selected">{@selected_id}</span>
    </div>
    """
  end
end
