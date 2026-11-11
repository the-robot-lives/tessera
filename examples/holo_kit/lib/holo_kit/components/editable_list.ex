defmodule HoloKit.Components.EditableList do
  @moduledoc """
  Complex demo component — an ordinary Hologram component.

  `<tsr-holo-list title=".." tsr-props='{"items":[...]}'>`: a filterable,
  keyboard-navigable list with an inline edit form.

  * text filter (`$input`),
  * arrow-key selection (`$key_down.arrow_down/arrow_up` on the listbox),
  * Enter opens the inline editor for the selected row, Esc cancels,
  * the form validates (non-empty, no duplicate names — only manually
    ported String fns: `trim/1`, `downcase/1`, `contains?/2`),
  * `item-saved` is emitted with `%{item_id, name, index}` — an idiomatic
    `put_action/2` at the synthetic host cid (see `HoloKit.Emit`),
  * the visible count is derived from `items` + `filter`.
  """

  use Hologram.Component

  prop :title, :string, default: "Items"
  prop :items, :list, default: []

  def init(props, component) do
    component
    |> HoloKit.Emit.mount(props)
    |> Hologram.Component.put_state(
      items: Map.get(props, :items, []),
      filter: "",
      selected_id: nil,
      editing_id: nil,
      draft: "",
      error: ""
    )
  end

  # — actions ——————————————————————————————————

  def action(:filter_changed, %{event: %{value: value}}, component) do
    Hologram.Component.put_state(component, filter: value)
  end

  def action(:select_item, %{id: id}, component) do
    Hologram.Component.put_state(component, selected_id: id)
  end

  def action(:select_down, _params, component) do
    move_selection(component, 1)
  end

  def action(:select_up, _params, component) do
    move_selection(component, -1)
  end

  def action(:start_edit, _params, component) do
    items = Map.get(component.state, :items, [])
    filter = Map.get(component.state, :filter, "")
    selected_id = Map.get(component.state, :selected_id, nil)
    item = find_by_id(filtered_items(items, filter), selected_id)

    if item == nil do
      component
    else
      component
      |> Hologram.Component.put_state(editing_id: item.id, draft: item.name, error: "")
    end
  end

  def action(:cancel_edit, _params, component) do
    Hologram.Component.put_state(component, editing_id: nil, draft: "", error: "")
  end

  def action(:draft_changed, %{event: %{value: value}}, component) do
    Hologram.Component.put_state(component, draft: value)
  end

  def action(:save_item, _params, component) do
    state = component.state
    items = Map.get(state, :items, [])
    editing_id = Map.get(state, :editing_id, nil)
    draft = Map.get(state, :draft, "")

    error = validation_error(items, editing_id, draft)

    if error == "" do
      name = String.trim(draft)
      new_items = rename_item(items, editing_id, name)
      index = index_of_id(items, editing_id)

      component
      |> Hologram.Component.put_state(items: new_items, editing_id: nil, draft: "", error: "")
      |> HoloKit.Emit.emit(:item_saved, %{item_id: editing_id, name: name, index: index})
    else
      Hologram.Component.put_state(component, error: error)
    end
  end

  def action(_other, _params, component), do: component

  # — public helpers (shared by template and actions) ————————————

  def filtered_items(items, filter) do
    needle = String.downcase(filter)

    Enum.filter(items, fn item ->
      String.contains?(String.downcase(item.name), needle)
    end)
  end

  def list_count(items, filter) do
    Enum.count(filtered_items(items, filter))
  end

  def item_class(item, selected_id, editing_id) do
    base = "tsr-list-item"

    sel = if item.id == selected_id, do: base <> " is-selected", else: base

    if item.id == editing_id, do: sel <> " is-editing", else: sel
  end

  # — private helpers ————————————————————————————

  defp move_selection(component, delta) do
    items = Map.get(component.state, :items, [])
    filter = Map.get(component.state, :filter, "")
    selected_id = Map.get(component.state, :selected_id, nil)

    next_id = select_offset(items, filter, selected_id, delta)
    Hologram.Component.put_state(component, selected_id: next_id)
  end

  defp select_offset(items, filter, selected_id, delta) do
    filtered = filtered_items(items, filter)
    count = Enum.count(filtered)

    idx = Enum.find_index(filtered, fn item -> item.id == selected_id end)

    current =
      if idx == nil do
        if delta > 0, do: -1, else: 0
      else
        idx
      end

    candidate = current + delta

    clamped =
      if candidate < 0 do
        0
      else
        if candidate >= count, do: count - 1, else: candidate
      end

    item = Enum.at(filtered, clamped)

    if item == nil, do: selected_id, else: item.id
  end

  defp find_by_id(items, id) do
    Enum.find(items, fn item -> item.id == id end)
  end

  defp index_of_id(items, id) do
    idx = Enum.find_index(items, fn item -> item.id == id end)

    if idx == nil, do: -1, else: idx
  end

  defp rename_item(items, id, name) do
    Enum.map(items, fn item ->
      if item.id == id do
        %{item | name: name}
      else
        item
      end
    end)
  end

  defp validation_error(items, _editing_id, draft) do
    trimmed = String.trim(draft)

    if trimmed == "" do
      "name can't be blank"
    else
      if duplicate_name?(items, trimmed) do
        "name already exists"
      else
        ""
      end
    end
  end

  defp duplicate_name?(items, name) do
    needle = String.downcase(name)

    Enum.any?(items, fn item ->
      String.downcase(String.trim(item.name)) == needle
    end)
  end

  # — template ——————————————————————————————————

  def template do
    ~HOLO"""
    <div class="tsr-list" data-cy="holo-list-root">
      <div class="tsr-list-head">
        <strong data-cy="holo-list-title">{@title}</strong>
        <span data-cy="holo-list-count">{list_count(@items, @filter)}</span>
      </div>

      <input
        type="text"
        placeholder="filter…"
        data-cy="holo-list-filter"
        value={@filter}
        $input={:filter_changed}
      />

      {%if @editing_id != nil}
      <form data-cy="holo-list-form" $submit={:save_item}>
        <input
          type="text"
          data-cy="holo-list-draft"
          value={@draft}
          $input={:draft_changed}
          $key_down.escape={:cancel_edit}
        />
        <button type="submit" data-cy="holo-list-save">save</button>
        <button type="button" data-cy="holo-list-cancel" $click={:cancel_edit}>cancel</button>
        {%if @error != ""}
        <span class="tsr-list-error" data-cy="holo-list-error">{@error}</span>
        {/if}
      </form>
      {/if}

      <ul
        role="listbox"
        tabindex="0"
        data-cy="holo-list-items"
        $key_down.arrow_down={:select_down}
        $key_down.arrow_up={:select_up}
        $key_down.enter={:start_edit}
      >
        {%for item <- filtered_items(@items, @filter)}
        <li
          role="option"
          data-cy="holo-list-item"
          class={item_class(item, @selected_id, @editing_id)}
          $click={:select_item, id: item.id}
        >{item.name}</li>
        {/for}
      </ul>
    </div>
    """
  end
end
