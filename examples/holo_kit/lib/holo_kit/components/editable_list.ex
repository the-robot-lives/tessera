defmodule HoloKit.Components.EditableList.Base do
  @moduledoc """
  Injectable base definitions for the editable list (spike item A).

  `use HoloKit.Components.EditableList, tag: "..."` pulls this in, so an
  extending module becomes a FULL component in its own right: props, init,
  template, helpers — all re-defined in the extender's module. That is what
  lets a template region call (`row_label/1`) resolve to the extender's
  override and lets new actions sit beside base ones after Hologram
  compiles the derived module.

  **`super` finding (recorded in the spike notes):** Hologram 0.10.1's
  client transpiler has NO `super` support (nothing in
  `lib/hologram/compiler/ir/` handles it), so although `defoverridable` +
  `super` work on the BEAM, an overridden client action cannot call `super`
  once transpiled. The extension contract therefore routes delegation
  through the injected plain-function dispatcher `base_action/3` —
  extensible without any Hologram internals.

  Overridable: `action/3`, `row_label/1` (named template region: the row
  label), `init/2`.
  """

  defmacro __using__(_opts) do
    quote do
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

      # — named template region: the row label ————————————————

      def row_label(item), do: item.name

      # — base action logic (dispatcher, transpilable plain calls) ————

      def base_action(:filter_changed, %{event: %{value: value}}, component) do
        Hologram.Component.put_state(component, filter: value)
      end

      def base_action(:select_item, %{id: id}, component) do
        Hologram.Component.put_state(component, selected_id: id)
      end

      def base_action(:select_down, _params, component) do
        HoloKit.Components.EditableList.Helpers.move_selection(component, 1)
      end

      def base_action(:select_up, _params, component) do
        HoloKit.Components.EditableList.Helpers.move_selection(component, -1)
      end

      def base_action(:start_edit, _params, component) do
        items = Map.get(component.state, :items, [])
        filter = Map.get(component.state, :filter, "")
        selected_id = Map.get(component.state, :selected_id, nil)
        item = Enum.find(filtered_items(items, filter), fn i -> i.id == selected_id end)

        if item == nil do
          component
        else
          component
          |> Hologram.Component.put_state(editing_id: item.id, draft: item.name, error: "")
        end
      end

      def base_action(:cancel_edit, _params, component) do
        Hologram.Component.put_state(component, editing_id: nil, draft: "", error: "")
      end

      def base_action(:draft_changed, %{event: %{value: value}}, component) do
        Hologram.Component.put_state(component, draft: value)
      end

      def base_action(:save, _params, component) do
        state = component.state
        items = Map.get(state, :items, [])
        editing_id = Map.get(state, :editing_id, nil)
        draft = Map.get(state, :draft, "")

        error = HoloKit.Components.EditableList.Helpers.validation_error(items, draft)

        if error == "" do
          name = String.trim(draft)
          new_items = HoloKit.Components.EditableList.Helpers.rename_item(items, editing_id, name)
          index = HoloKit.Components.EditableList.Helpers.index_of_id(items, editing_id)

          component
          |> Hologram.Component.put_state(items: new_items, editing_id: nil, draft: "", error: "")
          |> HoloKit.Emit.emit(:item_saved, %{item_id: editing_id, name: name, index: index})
        else
          Hologram.Component.put_state(component, error: error)
        end
      end

      def base_action(_other, _params, component), do: component

      # default action entry point — delegates everything to base_action/3
      def action(name, params, component), do: base_action(name, params, component)

      # — shared helpers (used by template and base_action) ——————————

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

      defoverridable action: 3, row_label: 1, init: 2

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
          <form data-cy="holo-list-form" $submit={:save}>
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
            >{row_label(item)}</li>
            {/for}
          </ul>
        </div>
        """
      end
    end
  end
end

defmodule HoloKit.Components.EditableList.Helpers do
  @moduledoc """
  Pure helpers for the editable list. Kept in a plain module (referenced by
  fully-qualified remote calls) so BOTH the base component and any
  `use`-derived extension share one implementation without needing
  `super`-style inheritance in client-transpiled code.
  """

  def move_selection(component, delta) do
    items = Map.get(component.state, :items, [])
    filter = Map.get(component.state, :filter, "")
    selected_id = Map.get(component.state, :selected_id, nil)

    next_id = select_offset(items, filter, selected_id, delta)
    Hologram.Component.put_state(component, selected_id: next_id)
  end

  def select_offset(items, filter, selected_id, delta) do
    filtered = HoloKit.Components.EditableList.filtered_items(items, filter)
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

  def index_of_id(items, id) do
    idx = Enum.find_index(items, fn item -> item.id == id end)

    if idx == nil, do: -1, else: idx
  end

  def rename_item(items, id, name) do
    Enum.map(items, fn item ->
      if item.id == id do
        %{item | name: name}
      else
        item
      end
    end)
  end

  def validation_error(items, draft) do
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

  def duplicate_name?(items, name) do
    needle = String.downcase(name)

    Enum.any?(items, fn item ->
      String.downcase(String.trim(item.name)) == needle
    end)
  end
end

defmodule HoloKit.Components.EditableList do
  @moduledoc """
  Complex demo component — an ordinary Hologram component.

  `<tsr-holo-editable_list title=".." tsr-props='{"items":[...]}'>`: a
  filterable, keyboard-navigable list with an inline edit form.

  * text filter (`$input`),
  * arrow-key selection (`$key_down.arrow_down/arrow_up` on the listbox),
  * Enter opens the inline editor for the selected row, Esc cancels,
  * the form validates (non-empty, no duplicate names),
  * `item-saved` is emitted with `%{item_id, name, index}` via
    `HoloKit.Emit` (synthetic host-bridge `put_action/2`),
  * the visible count is derived from `items` + `filter`.

  ## Compile-time extension (spike item A)

      use HoloKit.Components.EditableList, tag: "fancy-list"

  re-defines this whole component in the extending module (see
  `EditableList.Base`). Override `action/3` (delegate to `base_action/3` —
  the transpiler has no `super`), add new actions, or replace the
  `row_label/1` template region. No Hologram macro changes required.
  """

  use Hologram.Component
  use HoloKit.Components.EditableList.Base

  defmacro __using__(opts) do
    tag = Keyword.get(opts, :tag)

    quote do
      use Hologram.Component
      use HoloKit.Components.EditableList.Base

      if unquote(tag) do
        def __tessera_tag__, do: unquote(tag)
      end
    end
  end
end
