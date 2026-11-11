defmodule ThirdParty.TidyList do
  @moduledoc """
  Spike item (A), same-tag variant (EXTENSION-CONTRACT v0.1 §"same-tag
  layering"): a third-party module takes over the VENDOR's tag
  (`tsr-holo-editable-list`) — as an extension that layers on the base,
  never a substitute.

  Mechanically identical to `ThirdParty.FancyList` (injected
  `base_action/3` dispatcher, no `super` in Hologram's compiler IR), the
  only difference being the tag: `tag: :inherit` takes over the vendor's
  element name (`tsr-holo-editable-list`). The element registry (runtime
  tag→module map) repoints the tag to this module; vendor behaviour stays
  fully reachable — every action not overridden falls through unchanged, and
  the overridden `:save` still delegates to the vendor's
  validation/rename/emit pipeline.

  This is the canonical §5.9 takeover: `use Vendor, tag: <vendor tag>`
  resolves to `:inherit`, and the layer rides the SAME chain machinery as
  Tier 1 (chain order → depth → priority → module; the conflict warning
  fires through the shared registry, compile order never hides it).

  The layered behaviour: saved names are downcased before the vendor save
  runs (visible in e2e — typing `EARTH` saves as `earth`, while the
  vendor's empty/duplicate validation still rejects bad input).

  JS-side note (recorded in the spike notes): a custom element CLASS cannot
  be redefined once registered; same-tag takeover is resolved at the
  tag→module map, applying to elements that connect from the repoint on.
  """

  use HoloKit.Components.EditableList, tag: :inherit

  # — layer: downcase the draft, then run the vendor's save ————————————

  def action(:save, _params, component) do
    draft = Map.get(component.state, :draft, "")
    tidied = String.downcase(String.trim(draft))

    normalized =
      Hologram.Component.put_state(component, draft: tidied)

    base_action(:save, %{}, normalized)
  end

  # (no hand-written action catch-all: the canonical scaffold appends the
  # chain fallback `action/3` clause at __before_compile__ — authoring is
  # override-clauses only, mirroring the Tier-1 DSL style.)
end
