defmodule ThirdParty.FancyList do
  @moduledoc """
  Spike item (A): a third-party, compile-time extension of
  `HoloKit.Components.EditableList` written by a consumer app — NOT part of
  the holo_kit package.

  * `use HoloKit.Components.EditableList, tag: "fancy-list"` re-defines the
    whole base component in THIS module (see `EditableList.Base`).
  * Overrides `action(:save, _params, comp)` — normalizes params/state
    before delegating to the injected `base_action/3` dispatcher. NOTE:
    delegation uses `base_action/3`, not `super` — Hologram 0.10.1's client
    transpiler has no `super` support (recorded in the spike notes).
  * Adds a brand-new action `:archive` (dispatched from JS via
    `el.dispatchAction("archive", {id})` — spike item B) and emits
    `item-archived`.
  * Replaces the named template region `row_label/1` — rows render their
    name upcased, visibly distinguishing the derived element from the base
    one sitting on the same page.

  Compiles to its own element (`fancy-list`) that runs alongside the base
    element in all three hosts.
  """

  use HoloKit.Components.EditableList, tag: "fancy-list"

  # — override: normalize before delegating to the base implementation ——
  # The base :save reads the draft from state, so normalization here means:
  # trim the draft in state first, then run the base save logic.

  def action(:save, _params, component) do
    draft = Map.get(component.state, :draft, "")
    trimmed = String.trim(draft)

    normalized =
      Hologram.Component.put_state(component, draft: trimmed)

    base_action(:save, %{}, normalized)
  end

  # — brand-new action dispatched from the host JS ————————————

  def action(:archive, %{id: id}, component) do
    items = Map.get(component.state, :items, [])

    new_items =
      Enum.map(items, fn item ->
        if item.id == id do
          %{item | name: item.name <> " [archived]"}
        else
          item
        end
      end)

    component
    |> Hologram.Component.put_state(items: new_items)
    |> HoloKit.Emit.emit(:item_archived, %{item_id: id})
  end

  # — everything else keeps the base behavior ————————————————

  def action(other, params, component), do: base_action(other, params, component)

  # — named template region override: rows render upcased —————————

  def row_label(item), do: String.upcase(item.name)
end
