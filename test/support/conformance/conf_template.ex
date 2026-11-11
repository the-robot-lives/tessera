defmodule Tessera.TestFixtures.Conformance.Template do
  @moduledoc """
  `<tsr-conf-template>` — conformance fixture for the Tier-1 template DSL
  (brief 4b case-fill; feature landed via D-T1).

  Exercises attribute expressions, `.value` property bindings, `{%if%}` /
  `{%else%}` conditionals, `{%for%}` list rendering, and nested template
  composition (a `{%for%}` body with nested child elements + interpolation).
  The `toggle_flag` action flips a boolean so the conditional re-renders.

  Cases: T-02 (attribute expression), T-04 (`.value` property expression),
  T-07 (conditional branches), T-08 (list rendering), T-09 (nested templates).

  Note: nested BLOCK directives (if-in-if, for-in-if) are rejected by the
  develop Hologram lexer, so nesting is exercised as nested elements within a
  loop body — the expressible subset.
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-template", js: "conf_template.mjs"

  attr(:label, :string, default: "hello")

  state(:flag, :boolean, default: false)
  state(:items, :list, default: ["alpha", "beta", "gamma"])

  cy("conf-template-root")

  template ~TSR"""
  <div data-cy="conf-template-root" title="{@label}">
    <input data-cy="conf-template-input" .value="{@label}">
    <span data-cy="conf-template-flag">{%if @flag}ON{%else}OFF{/if}</span>
    <button type="button" data-cy="conf-template-toggle" $click={:toggle_flag}>flag</button>
    <ul data-cy="conf-template-list">{%for item <- @items}<li class="item">{item}</li>{/for}</ul>
    <div data-cy="conf-template-nested">{%for item <- @items}<span class="nest"><b>{item}</b></span>{/for}</div>
  </div>
  """

  action :toggle_flag, fn state, _params ->
    %{state | flag: not state.flag}
  end
end