defmodule Tessera.TestFixtures.Conformance.Slots do
  @moduledoc """
  `<tsr-conf-slots>` — conformance fixture for Tier-1 shadow-DOM slots
  (brief 4b case-fill; slot rendering landed via D-T1).

  A default slot and a named `header` slot, each in its own wrapper so a case
  can assert which light-DOM children land where. Slots are written in the
  bare `<slot>` / `<slot name="…">` form: the develop Hologram lexer rejects an
  explicit `</slot>` close (the styles-panel boot bug owned by brief 1c), so
  fallback CONTENT (SD-03) cannot be expressed yet and stays pending.

  Cases: SD-01 (default slot accepts a light-DOM child), SD-02 (named slot
  routes `slot="header"` children).
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-slots", js: "conf_slots.mjs"

  attr(:label, :string, default: "slots")

  slot("header")

  cy("conf-slots-root")

  template ~TSR"""
  <div data-cy="conf-slots-root">
    <span data-cy="conf-slots-label">{@label}</span>
    <div data-cy="conf-slots-default"><slot></div>
    <div data-cy="conf-slots-named"><slot name="header"></div>
  </div>
  """
end