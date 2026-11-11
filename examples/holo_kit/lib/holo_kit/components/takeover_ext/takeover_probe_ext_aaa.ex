defmodule HoloKit.Components.TakeoverProbeExtAaa do
  @moduledoc """
  Depth-1 tag-takeover layer over `TakeoverProbe` (brief 3f, §5.9; X-19 —
  the canonical-macro mirror of `TakeoverExtAaa`).

  Overrides `bump` with a PASS-THROUGH layer: fires its marker event
  `conf-ext-aaa` (synchronously via `Emit.js_emit/2` — `put_action/2` fills
  a single `next_action` slot, so multiple markers per dispatch need direct
  JS interop) and down-calls the chain via the injected `base_action/3`
  (Hologram's IR has no `super`). Adds no state keys — X-05's snapshot pin
  must survive the takeover.
  """

  use HoloKit.Components.TakeoverProbe, tag: :inherit, overrides: [:bump]

  def action(:bump, params, component) do
    HoloKit.Emit.js_emit(:conf_ext_aaa, %{layer: "aaa"})
    base_action(:bump, params, component)
  end
end
