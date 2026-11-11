defmodule ThirdParty.TidyList do
  @moduledoc """
  Spike item (A), same-tag variant (EXTENSION-CONTRACT v0.1 §"same-tag
  layering"): a third-party module takes over the VENDOR's tag
  (`tsr-holo-editable-list`) — as an extension that layers on the base,
  never a substitute.

  Mechanically identical to `ThirdParty.FancyList` (injected
  `base_action/3` dispatcher, no `super` in Hologram's compiler IR), the
  only difference being the tag: `tag: "tsr-holo-editable-list"` reuses the
  vendor's element name. The element registry (runtime tag→module map)
  repoints the tag to this module; vendor behaviour stays fully reachable —
  every action not overridden falls through unchanged, and the overridden
  `:save` still delegates to the vendor's validation/rename/emit pipeline.

  The layered behaviour: saved names are downcased before the vendor save
  runs (visible in e2e — typing `EARTH` saves as `earth`, while the
  vendor's empty/duplicate validation still rejects bad input).

  JS-side note (recorded in the spike notes): a custom element CLASS cannot
  be redefined once registered; same-tag takeover is resolved at the
  tag→module map, applying to elements that connect from the repoint on.
  """

  use HoloKit.Components.EditableList, tag: "tsr-holo-editable-list"

  # — layer: downcase the draft, then run the vendor's save ————————————

  def action(:save, _params, component) do
    draft = Map.get(component.state, :draft, "")
    tidied = String.downcase(String.trim(draft))

    normalized =
      Hologram.Component.put_state(component, draft: tidied)

    base_action(:save, %{}, normalized)
  end

  # — everything else keeps the vendor behaviour ————————————————

  def action(other, params, component), do: base_action(other, params, component)
end
