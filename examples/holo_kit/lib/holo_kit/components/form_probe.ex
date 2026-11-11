defmodule HoloKit.Components.FormProbe do
  @moduledoc """
  `<tsr-holo-form-probe>` — Tier-2 conformance fixture for the forms family
  (lit-parity §2.10 rows #144-#149, brief 3e; FM-01…FM-03 mount it on the
  Tier-2 Cypress adapter).

  Declares `__tsr_form_associated__/0` ⇒ the compiled manifest carries
  `"formAssociated" => true` ⇒ the runtime emits `static formAssociated`
  before `customElements.define` and the constructor attaches an
  `ElementInternals` (EXTENSION-CONTRACT §6.7). State `value` is what the
  form sees: the host glue mounts this module through a recording subclass
  (holo_runtime_glue.js) that pushes `state.value` through
  `internals.setFormValue` (#147) on every render and dispatches
  `:reset_value` from `formResetCallback` (#148), logging signals to
  `el.tesseraFormSignals`. `setValidity` (#146) is a plain internals API the
  cases drive directly; `formDisabledCallback` (#149) records enabled/
  disabled transitions.

  NO unknown-name dispatch concern here: FM dispatches only declared names
  and the component keeps its catch-all `action/3` (the unknown-action path
  is pinned by the X family on PipelineProbe, which deliberately has none).
  """

  use Hologram.Component

  @initial "initial"

  def init(props, component) do
    component
    |> HoloKit.Emit.mount(props)
    |> Hologram.Component.put_state(value: @initial, touched: false)
  end

  def action(:set_value, params, component) do
    value = Map.get(params, :value) || Map.get(params, :newValue) || @initial

    Hologram.Component.put_state(component, value: value, touched: true)
  end

  def action(:reset_value, _params, component) do
    Hologram.Component.put_state(component, value: @initial, touched: false)
  end

  def action(_other, _params, component), do: component

  def template do
    ~HOLO"""
    <div class="tsr-form-probe" data-cy="conf-form-root">
      <button type="button" data-cy="conf-form-set" $click={:set_value, value: "clicked"}>set</button>
      <span class="tsr-form-probe-value" data-cy="conf-form-value">{@value}</span>
    </div>
    """
  end

  # §6.7 form participation + §6.1 statics (open-surface list, declaration
  # order). Brief 3f drives both from __tessera_spec__; this is the fixture
  # opt-in shape the manifest already understands (standalone.ex
  # component_manifest/1).
  def __tsr_form_associated__, do: true

  def __tsr_actions__, do: [:set_value, :reset_value]
end
