defmodule SpikeKit.DirectiveDemo do
  @moduledoc """
  `<spike-directive-demo>` — SPIKE component (`spike/elixir-to-lit`).

  Directive-surface demo (brief 1d): `class_map` / `style_map` /
  `if_defined` / `nothing` (child + attribute position), mirroring the
  conformance directives fixture. Its generated element imports
  `lit/directives/{class-map,style-map,if-defined}.js`, which makes it the
  bundle-proof vehicle for the shared-runtime variant: the runtime bundle
  must leave the directive subpaths EXTERNAL (served by the shared
  `tessera-runtime.esm.js` through the demo import map) instead of inlining
  a second copy of the directive code.
  """

  use Noizu.Tessera.Component, tag: "spike-directive-demo", js: "directive_demo.mjs"

  attr(:bg, :string, default: "red")
  attr(:accent, :string, default: "blue")
  attr(:title_text, :string)

  state(:active, :boolean, default: false)
  state(:highlight, :boolean, default: false)

  cy("spike-dir-root")

  template ~TSR"""
  <div data-cy="spike-dir-root">
    <div data-cy="spike-dir-class" class={class_map(%{active: @active, highlight: @highlight})}>classes</div>
    <div data-cy="spike-dir-style" style={style_map(%{backgroundColor: @bg, "--spike-directive-demo-accent": @accent})}>styled</div>
    <div data-cy="spike-dir-defined" title={if_defined(@title_text)}>defined</div>
    <div data-cy="spike-dir-nothing-attr" title={nothing}>nothing-attr</div>
    <div data-cy="spike-dir-nothing-child">{nothing}</div>
    <button type="button" data-cy="spike-dir-toggle-active" $click={:toggle_active}>active</button>
    <button type="button" data-cy="spike-dir-toggle-highlight" $click={:toggle_highlight}>highlight</button>
  </div>
  """

  action(:toggle_active, fn state, _params ->
    %{state | active: not state.active}
  end)

  action(:toggle_highlight, fn state, _params ->
    %{state | highlight: not state.highlight}
  end)
end
