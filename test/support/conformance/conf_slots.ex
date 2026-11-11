defmodule Tessera.TestFixtures.Conformance.Slots do
  @moduledoc """
  `<tsr-conf-slots>` — conformance fixture for Tier-1 shadow-DOM slots
  (brief 4b case-fill; slot rendering landed via D-T1, fallback content via
  brief 1c's slot pre-pass).

  A default slot, a named `header` slot, and a named `fb` slot with fallback
  content, each in its own wrapper so a case can assert which light-DOM
  children land where and when fallback renders.

  Cases: SD-01 (default slot accepts a light-DOM child), SD-02 (named slot
  routes `slot="header"` children), SD-03 (slot fallback renders when no child
  is slotted, and is replaced when one is).
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-slots", js: "conf_slots.mjs"

  attr(:label, :string, default: "slots")

  slot("header")
  slot("fb")

  cy("conf-slots-root")

  template ~TSR"""
  <div data-cy="conf-slots-root">
    <span data-cy="conf-slots-label">{@label}</span>
    <div data-cy="conf-slots-default"><slot></slot></div>
    <div data-cy="conf-slots-named"><slot name="header"></slot></div>
    <div data-cy="conf-slots-fallback"><slot name="fb">fallback-content</slot></div>
  </div>
  """
end