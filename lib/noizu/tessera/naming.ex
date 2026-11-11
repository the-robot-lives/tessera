defmodule Noizu.Tessera.Naming do
  @moduledoc """
  Naming conversions of the tessera wire contract (CONTRACT.md §1).

  | Elixir (spec)            | DOM / JS                    | Rule |
  |--------------------------|-----------------------------|------|
  | `attr :display_name`     | attribute `display-name`    | snake → kebab |
  | `prop :tag_list`         | property `tagList`          | snake → camel |
  | `event "persona-select"` | CustomEvent `persona-select`| kebab, verbatim |
  | `event "persona-select"` | binding prop `on_persona_select` | `"on_" <> snake` |
  | `event "persona-select"` | default action `:persona_select` | `snake(event)` |
  | detail key `persona_id`  | detail key `personaId`      | snake → camel |
  """

  @typedoc "A snake_case identifier, e.g. `:display_name`."
  @type snake :: atom()

  @typedoc "A kebab-case DOM name, e.g. `\"display-name\"`."
  @type kebab :: String.t()

  @typedoc "A camelCase DOM name, e.g. `\"displayName\"`."
  @type camel :: String.t()

  @doc "Custom-element tag grammar (CONTRACT.md §1): lowercase with a hyphen."
  @spec tag_regex() :: Regex.t()
  def tag_regex, do: ~r/^[a-z][a-z0-9]*(-[a-z0-9]+)+$/

  @doc "Event-name grammar (CONTRACT.md §1): kebab-case, at least one hyphen."
  @spec event_regex() :: Regex.t()
  def event_regex, do: ~r/^[a-z][a-z0-9]*(-[a-z0-9]+)+$/

  @doc "Spec identifier grammar for attr/prop/detail names: snake_case atoms."
  @spec snake_regex() :: Regex.t()
  def snake_regex, do: ~r/^[a-z][a-z0-9_]*$/

  @doc """
  Wire-contract value types (CONTRACT.md §2).
  """
  @spec known_types() :: [atom()]
  def known_types, do: [:string, :integer, :float, :boolean, :list, :map, :any]

  @doc "True when the given atom is a contract type."
  @spec known_type?(atom()) :: boolean()
  def known_type?(type), do: type in known_types()

  @doc "snake_case atom → kebab-case DOM attribute name."
  @spec snake_to_kebab(snake()) :: kebab()
  def snake_to_kebab(name) when is_atom(name) do
    name |> Atom.to_string() |> String.replace("_", "-")
  end

  @doc """
  snake_case atom → camelCase DOM property / detail key.

  BYTE-EXACT with the JS core (`priv/js/src/events.mjs`): split the snake
  string on `"_"` and capitalize the first letter of every segment after the
  first (`persona_id` → `personaId`). Note this deliberately DIFFERS from
  `Macro.camelize/1`/`Macro.underscore/1` for acronyms/digits
  (`Macro.underscore("userID")` = `user_id`, but the JS rule gives
  `user_i_d`) — never use Macro.* for contract keys.
  """
  @spec snake_to_camel(snake()) :: camel()
  def snake_to_camel(name) when is_atom(name) do
    # `trim: false` (vs `true`) is equivalent-in-context — names with a
    # leading underscore never reach this conversion (rejected upstream by
    # snake_regex) — but keeping the exact JS-core split rule byte-exact is
    # worth more than deleting the dead branch.
    [first | rest] = name |> Atom.to_string() |> String.split("_", trim: false)

    rest
    |> Enum.map(&upcase_first/1)
    |> then(&Enum.join([first | &1], ""))
  end

  @doc "kebab-case event/tag name → snake_case atom."
  @spec kebab_to_snake(kebab()) :: snake()
  def kebab_to_snake(kebab) when is_binary(kebab) do
    kebab |> String.replace("-", "_") |> String.to_atom()
  end

  @doc "Binding-prop name for an event: `\"on_\" <> snake(event)` (CONTRACT.md §1)."
  @spec event_binding_prop(kebab()) :: snake()
  def event_binding_prop(event_name) when is_binary(event_name) do
    String.to_atom("on_" <> String.replace(event_name, "-", "_"))
  end

  @doc "Default action atom for an event: `snake(event)` (CONTRACT.md §1)."
  @spec event_default_action(kebab()) :: snake()
  def event_default_action(event_name) when is_binary(event_name) do
    kebab_to_snake(event_name)
  end

  @doc """
  Converts a camelCase key back to snake_case — mirrors the JS core's
  `snakeKeysDeep`: EVERY uppercase char becomes `"_"` + its lowercase
  (`userID` → `user_i_d`), byte-exact with `priv/js/src/events.mjs`.
  """
  @spec camel_to_snake(camel()) :: snake()
  def camel_to_snake(camel) when is_binary(camel) do
    camel
    |> String.replace(~r/[A-Z]/, fn cap -> "_" <> String.downcase(cap) end)
    |> String.to_atom()
  end

  @doc """
  True when a snake name survives the wire round-trip:
  `snake |> snake_to_camel |> camel_to_snake == snake`.

  The JS core and the Elixir bridge rely on this equivalence; names that do
  not round-trip would silently change meaning across the bridge. Fails for
  digit-initial segments (`col_2_width` → `col2Width` → `col2_width`) and
  for double/trailing underscores (`foo__bar`, `foo_`).
  """
  @spec round_trips?(snake()) :: boolean()
  def round_trips?(name) when is_atom(name) do
    name |> snake_to_camel() |> camel_to_snake() == name
  end

  defp upcase_first(<<c, rest::binary>>) when c in ?a..?z, do: <<c - 32>> <> rest
  defp upcase_first(other), do: other
end
