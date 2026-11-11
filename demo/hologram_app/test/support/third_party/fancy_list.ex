defmodule ThirdParty.FancyList do
  @moduledoc """
  Spike item (A): a third-party, compile-time extension of
  `HoloKit.Components.EditableList` written by a consumer app — NOT part of
  the holo_kit package.

  * `use HoloKit.Components.EditableList, tag: "fancy-list", actions: [:archive]`
    rides the canonical `Noizu.Tessera.Component.Extension` derivation layer
    (§5.3/D4 — the SAME shared extension.ex machinery Tier 1 uses): option
    guards, §5.9 chain order, `merge_spec!/3`, the §8 pin check. The scaffold
    injects the `base_action/3` dispatcher + `defoverridable` — Hologram's IR
    has no `super`, so delegation goes through the injected dispatcher.
  * Overrides `action(:save, _params, comp)` — normalizes params/state
    before delegating to the injected `base_action/3` dispatcher. NOTE:
    delegation uses `base_action/3`, not `super` — Hologram 0.10.1's client
    transpiler has no `super` support (recorded in the spike notes).
  * Adds a brand-new action `:archive` (`actions: [:archive]` joins the
    §6.1 OPEN surface; dispatched from JS via `el.dispatchAction("archive", {id})`
    — spike item B) and emits `item-archived`.
  * Replaces the named template region `row_label/1` — rows render their
    name upcased, visibly distinguishing the derived element from the base
    one sitting on the same page.

  Compiles to its own element (`fancy-list`) that runs alongside the base
    element in all three hosts.
  """

  use HoloKit.Components.EditableList, tag: "fancy-list", actions: [:archive]

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

  # — named template region override: rows render upcased —————————
  # (no hand-written action catch-all: the canonical scaffold appends the
  # chain fallback `action/3` clause at __before_compile__, so an author
  # defines ONLY the clauses it overrides — Tier-1 authoring style.)

  def row_label(item), do: String.upcase(item.name)
end
