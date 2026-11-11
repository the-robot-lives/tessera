defmodule Tessera.TestFixtures.Conformance.Directives do
  @moduledoc """
  `<tsr-conf-directives>` — conformance fixture for the Tier-1 high-value Lit
  directives (brief 1d): `class_map` / `style_map` / `if_defined` / `nothing`,
  lowered to `classMap` / `styleMap` / `ifDefined` / `nothing` with the matching
  `lit` / `lit/directives/*` imports.

  Two boolean state flags drive a `class_map`; two string attrs drive a
  `style_map` (incl. a `--tsr-<tag>-*` custom property); a nullable string attr
  drives `if_defined`; `nothing` appears in both child and attribute position.

  Cases: D-01 (classMap toggles classes), D-02 (styleMap sets inline styles incl.
  a custom property), D-06 (ifDefined removes the attribute when undefined),
  T-06 (nothing renders no nodes in child position / removes the attribute).
  """

  use Noizu.Tessera.Component, tag: "tsr-conf-directives", js: "conf_directives.mjs"

  state(:active, :boolean, default: false)
  state(:highlight, :boolean, default: false)

  attr(:bg, :string, default: "red")
  attr(:accent, :string, default: "blue")
  attr(:title_text, :string)

  cy("conf-dir-root")

  template(~TSR"""
  <div data-cy="conf-dir-root">
    <div data-cy="conf-dir-class" class={class_map(%{active: @active, highlight: @highlight})}>classes</div>
    <div data-cy="conf-dir-style" style={style_map(%{backgroundColor: @bg, "--tsr-conf-directives-accent": @accent})}>styled</div>
    <div data-cy="conf-dir-defined" title={if_defined(@title_text)}>defined</div>
    <div data-cy="conf-dir-nothing-attr" title={nothing}>nothing-attr</div>
    <div data-cy="conf-dir-nothing-child">{nothing}</div>
    <button type="button" data-cy="conf-dir-toggle-active" $click={:toggle_active}>active</button>
    <button type="button" data-cy="conf-dir-toggle-highlight" $click={:toggle_highlight}>highlight</button>
  </div>
  """)

  action(:toggle_active, fn state, _params ->
    %{state | active: not state.active}
  end)

  action(:toggle_highlight, fn state, _params ->
    %{state | highlight: not state.highlight}
  end)
end
