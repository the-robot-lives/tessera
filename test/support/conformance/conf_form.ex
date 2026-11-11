defmodule Tessera.TestFixtures.Conformance.Form do
  @moduledoc """
  `<tsr-conf-form>` — conformance fixture for the Tier-1 forms family
  (lit-parity §2.10 rows #144-#149, brief 2f; FM-01…FM-03 mount it on the WTR
  adapter). Behavioral mirror of the Tier-2 `HoloKit.Components.FormProbe`.

  Declares `form_associated: true` on `use` ⇒ the compiled manifest carries
  `"formAssociated" => true` and the generated element emits
  `static formAssociated = true` ⇒ the TesseraElement constructor attaches an
  `ElementInternals` exposed as `el.internals` (EXTENSION-CONTRACT §6.7; the
  counter fixture stays undeclared and pins the negative). State `value` is
  what the form sees: the harness mounts this module through a recording
  subclass implementing the DOCUMENTED push-per-render pattern — every render
  pushes `state.value` through `internals.setFormValue` (#147),
  `formResetCallback` (#148) dispatches `:reset_value`, and
  `formDisabledCallback` (#149) records enabled/disabled transitions into
  `el.tesseraFormSignals` (the same recording surface the Tier-2 host glue
  provides, so the shared case bodies run unmodified on both engines).
  `setValidity` (#146) is a plain internals API the cases drive directly.
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-form", js: "conf_form.mjs", form_associated: true

  state(:value, :string, default: "initial")

  cy("conf-form-root")

  template(~TSR"""
  <div data-cy="conf-form-root">
    <button type="button" data-cy="conf-form-set" $click={:set_value, value: "clicked"}>set</button>
    <span data-cy="conf-form-value">{@value}</span>
  </div>
  """)

  action(:set_value, fn state, params ->
    %{
      state
      | value:
          if params.value do
            params.value
          else
            state.value
          end
    }
  end)

  action(:reset_value, fn state, _params ->
    %{state | value: "initial"}
  end)
end
