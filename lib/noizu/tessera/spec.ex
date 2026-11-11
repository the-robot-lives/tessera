defmodule Noizu.Tessera.Spec do
  @moduledoc """
  The compiled spec of a tessera component (CONTRACT.md is authoritative).

  A spec is built at compile time by `use Noizu.Tessera.Component` from the
  `attr`/`prop`/`event`/`slot`/`cy` declarations of the component module, and
  is exposed on that module as `__tessera_spec__/0`. It is the single source
  the generated JS contract module (`Noizu.Tessera.Codegen.contract_module/1`),
  the Custom Elements Manifest (`Noizu.Tessera.Codegen.cem/1`) and the
  Hologram adapter all derive from.

  Entry shapes (plain maps):

      attrs:   %{name: :display_name, type: :string, required: true, default: nil, line: 3}
               optional: attribute: "custom-name" | false, reflect: true
      props:   %{name: :tag_list, type: :list, json: true, default: [], line: 4}
      events:  %{name: "persona-select", detail: %{persona_id: :string}, line: 5}
      slots:   %{name: "default", line: 6}
      styles:  %{kind: :css, value: ":host { … }", line: 7}
               %{kind: :shared, value: "./shared_styles.mjs", line: 8}
      css:     %{name: "--persona-card-accent", default: "#6366f1", line: 7}
      parts:   %{name: "select-button", line: 8}
      lifecycle: %{will_update: %{js: "…", line: 9}, …}  (only declared hooks)

  `css`/`part` entries are documentation metadata for the Custom Elements
  Manifest (and the gallery) — they do not ride the wire contract.
  """

  alias Noizu.Tessera.Naming

  defstruct version: 1,
            tag: nil,
            module: nil,
            file: nil,
            js: nil,
            cy: nil,
            attrs: [],
            props: [],
            events: [],
            slots: [],
            css_properties: [],
            parts: [],
            state: [],
            actions: [],
            template: nil,
            styles: [],
            lifecycle: %{}

  @type attr_entry :: %{
          required(:name) => Naming.snake(),
          required(:type) => atom(),
          optional(:required) => boolean(),
          optional(:default) => any(),
          optional(:attribute) => String.t() | false,
          optional(:reflect) => boolean(),
          optional(:line) => non_neg_integer()
        }

  @type prop_entry :: %{
          required(:name) => Naming.snake(),
          required(:type) => atom(),
          optional(:json) => boolean(),
          optional(:default) => any(),
          optional(:attribute) => String.t() | false,
          optional(:reflect) => boolean(),
          optional(:line) => non_neg_integer()
        }

  @type event_entry :: %{
          required(:name) => Naming.kebab(),
          optional(:detail) => %{Naming.snake() => atom()},
          optional(:line) => non_neg_integer()
        }

  @type slot_entry :: %{required(:name) => String.t(), optional(:line) => non_neg_integer()}

  @type css_entry :: %{
          required(:name) => String.t(),
          optional(:default) => String.t() | nil,
          optional(:line) => non_neg_integer()
        }

  @type part_entry :: %{required(:name) => String.t(), optional(:line) => non_neg_integer()}

  @type state_entry :: %{
          required(:name) => Naming.snake(),
          required(:type) => atom(),
          optional(:default) => any(),
          optional(:attribute) => String.t() | false,
          optional(:reflect) => boolean(),
          optional(:line) => non_neg_integer()
        }

  @type action_entry :: %{
          required(:name) => atom(),
          required(:js) => String.t(),
          optional(:line) => non_neg_integer()
        }

  @type template_entry :: %{
          required(:raw) => String.t(),
          required(:lexer) => :hologram | :minimal,
          required(:render_js) => String.t(),
          optional(:line) => non_neg_integer()
        }

  @type style_entry :: %{
          required(:kind) => :css | :shared,
          required(:value) => String.t(),
          optional(:line) => non_neg_integer()
        }

  @type lifecycle_hook :: :should_update | :will_update | :first_updated | :updated

  @type lifecycle_entry :: %{
          required(:js) => String.t(),
          optional(:line) => non_neg_integer()
        }

  @type lifecycle :: %{optional(lifecycle_hook()) => lifecycle_entry()}

  @type t :: %__MODULE__{
          version: pos_integer(),
          tag: Naming.kebab() | nil,
          module: module() | nil,
          file: String.t() | nil,
          js: String.t() | nil,
          cy: String.t() | nil,
          attrs: [attr_entry()],
          props: [prop_entry()],
          events: [event_entry()],
          slots: [slot_entry()],
          css_properties: [css_entry()],
          parts: [part_entry()],
          state: [state_entry()],
          actions: [action_entry()],
          template: template_entry() | nil,
          styles: [style_entry()],
          lifecycle: lifecycle()
        }

  @doc """
  Validates an option value against the contract and raises `CompileError`
  with a pointed message otherwise. Used at compile time by
  `Noizu.Tessera.Component` and by `mix tessera.gen.component`.

  `kind` is the DSL entry being validated (`"attr"`, `"prop"`, `"event"`, ...).
  """
  @spec validate!(
          atom(),
          String.t() | atom(),
          keyword() | %{atom() => atom()},
          String.t(),
          non_neg_integer()
        ) ::
          :ok
  def validate!(kind, name, detail_or_opts, file, line)

  # The detail-map clause comes first so events get BOTH the grammar check and
  # the per-key checks (a later general clause would otherwise shadow it).
  def validate!(:event, name, detail, file, line) when is_map(detail) do
    validate_grammar!(:event, name, file, line)

    Enum.each(detail, fn
      {key, type} when is_atom(key) ->
        validate_snake_name!("event detail", key, file, line)
        validate_round_trip!("event detail key", key, file, line)
        validate_type!(name, key, type, file, line)

      {key, _type} ->
        raise CompileError,
          file: file,
          line: line,
          description:
            "tessera event #{inspect(name)} detail key #{inspect(key)} must be a snake_case atom"
    end)

    :ok
  end

  def validate!(kind, name, _opts, file, line) when kind in [:tag, :event] do
    validate_grammar!(kind, name, file, line)
    :ok
  end

  def validate!(kind, name, opts, file, line) when kind in [:attr, :prop, :state] do
    validate_snake_name!(kind, name, file, line)
    validate_round_trip!(kind, name, file, line)

    unless Naming.known_type?(opts[:type]) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera #{kind} #{inspect(name)} has unknown type #{inspect(opts[:type])} — " <>
            "known types: #{inspect(Naming.known_types())}"
    end

    validate_attribute_opt!(kind, name, opts[:attribute], file, line)
    validate_reflect_opt!(kind, name, opts[:reflect], file, line)

    :ok
  end

  def validate!(:slot, name, _opts, file, line) do
    unless is_binary(name) and Regex.match?(~r/^[a-z][a-z0-9_-]*$/, name) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera slot name #{inspect(name)} must be a lowercase string " <>
            "([a-z][a-z0-9_-]*), e.g. \"header\" or \"default\""
    end

    :ok
  end

  def validate!(:part, name, _opts, file, line) do
    unless is_binary(name) and Regex.match?(~r/^[a-z][a-z0-9_-]*$/, name) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera part name #{inspect(name)} must be a lowercase string " <>
            "([a-z][a-z0-9_-]*), e.g. \"select-button\" — it is exposed as ::part(name)"
    end

    :ok
  end

  def validate!(:css, name, opts, file, line) do
    unless is_binary(name) and Regex.match?(~r/^--[a-z][a-z0-9-]*$/, name) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera css property #{inspect(name)} must be a lowercase CSS custom " <>
            "property name (--[a-z][a-z0-9-]*), e.g. \"--persona-card-accent\""
    end

    case opts[:default] do
      nil ->
        :ok

      default when is_binary(default) ->
        :ok

      other ->
        raise CompileError,
          file: file,
          line: line,
          description:
            "tessera css property #{inspect(name)} default must be a string " <>
              "(a CSS value), got: #{inspect(other)}"
    end

    :ok
  end

  @doc "Validates the DSL kind + type carried in a raw entry tuple."
  @spec validate_type!(String.t() | atom(), atom(), atom(), String.t(), non_neg_integer()) :: :ok
  def validate_type!(context, key, type, file, line) do
    unless Naming.known_type?(type) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera #{context} key #{inspect(key)} has unknown type #{inspect(type)} — " <>
            "known types: #{inspect(Naming.known_types())}"
    end

    :ok
  end

  defp validate_grammar!(kind, name, file, line) when kind in [:tag, :event] do
    # Reserved wire characters first, with their own pointed message: `:` `@`
    # `;` and whitespace delimit the `event:action@target;…` data-tsr-on entry
    # grammar (CONTRACT.md §3), so a name carrying one would corrupt or kill
    # its bridge entry at runtime even if some looser grammar allowed it.
    if is_binary(name) and String.match?(name, ~r/[\s:@;]/) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera #{kind} name #{inspect(name)} contains a reserved data-tsr-on character " <>
            "(whitespace, `:`, `@` or `;`) — these delimit the `event:action@target;…` bridge " <>
            "grammar (CONTRACT.md §3) and can never appear in a #{kind} name"
    end

    regex = if kind == :tag, do: Naming.tag_regex(), else: Naming.event_regex()

    unless is_binary(name) and Regex.match?(regex, name) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "invalid tessera #{kind} name #{inspect(name)} — must match the contract grammar " <>
            "^[a-z][a-z0-9]*(-[a-z0-9]+)+$ (lowercase with at least one hyphen)"
    end

    :ok
  end

  defp validate_snake_name!(kind, name, file, line) do
    unless is_atom(name) and Regex.match?(Naming.snake_regex(), Atom.to_string(name)) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera #{kind} name #{inspect(name)} must be a snake_case atom " <>
            "(e.g. :display_name)"
    end
  end

  defp validate_round_trip!(kind, name, file, line) do
    unless Naming.round_trips?(name) do
      camel = Naming.snake_to_camel(name)

      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera #{kind} #{inspect(name)} does not survive the snake↔camel wire " <>
            "round-trip (#{inspect(name)} → #{inspect(camel)} → " <>
            "#{inspect(Naming.camel_to_snake(camel))}). Rename it — the JS bridge converts " <>
            "keys byte-for-byte, so names with digit-initial segments (e.g. col_2_width) or " <>
            "double/trailing underscores (e.g. foo__bar, foo_) would silently change " <>
            "meaning across the bridge."
    end
  end

  # Lit property options (lit-parity brief 1c): `attribute:` renames or disables
  # the observed DOM attribute; `reflect:` writes property changes back to it.
  # Absent (nil) keeps Lit's defaults.
  defp validate_attribute_opt!(_kind, _name, nil, _file, _line), do: :ok
  defp validate_attribute_opt!(_kind, _name, false, _file, _line), do: :ok

  defp validate_attribute_opt!(kind, name, value, file, line) when is_binary(value) do
    unless value != "" and Regex.match?(~r/^[a-zA-Z_:][a-zA-Z0-9_:.\-]*$/, value) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera #{kind} #{inspect(name)} attribute: #{inspect(value)} is not a valid " <>
            "HTML attribute name — use a name like \"data-count\" (letters/digits/-/_/./:), " <>
            "or false to disable the attribute"
    end

    :ok
  end

  defp validate_attribute_opt!(kind, name, other, file, line) do
    raise CompileError,
      file: file,
      line: line,
      description:
        "tessera #{kind} #{inspect(name)} attribute: must be a string (custom attribute " <>
          "name) or false (no attribute), got: #{inspect(other)}"
  end

  defp validate_reflect_opt!(_kind, _name, nil, _file, _line), do: :ok
  defp validate_reflect_opt!(_kind, _name, value, _file, _line) when is_boolean(value), do: :ok

  defp validate_reflect_opt!(kind, name, other, file, line) do
    raise CompileError,
      file: file,
      line: line,
      description:
        "tessera #{kind} #{inspect(name)} reflect: must be a boolean, got: #{inspect(other)}"
  end

  @doc """
  The JSON-literal form of a spec default value, as it appears in the
  generated contract module (CONTRACT.md §2). `nil` becomes `null`.
  """
  @spec json_literal(any()) :: String.t()
  def json_literal(nil), do: "null"
  def json_literal(true), do: "true"
  def json_literal(false), do: "false"
  def json_literal(v) when is_integer(v) or is_float(v), do: to_string(v)
  def json_literal(v) when is_binary(v), do: ~s("#{escape_json(v)}")
  # Maps are encoded with keys sorted by name so the generated contract (and
  # goldens) are byte-deterministic across runs (Jason does not sort map keys).
  def json_literal(%{} = v) do
    inner =
      v
      |> Enum.map(fn {k, val} -> {json_key(k), val} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(",", fn {k, val} -> json_literal(k) <> ":" <> json_literal(val) end)

    "{" <> inner <> "}"
  end

  # Lists are encoded manually over json_literal (NOT Jason) so nested maps
  # keep the sorted-key byte determinism — Jason emits map keys in arbitrary
  # order.
  def json_literal(v) when is_list(v),
    do: "[" <> Enum.map_join(v, ",", &json_literal/1) <> "]"

  def json_literal(v) do
    raise ArgumentError,
          "tessera default value must be JSON-safe (string, number, boolean, list, map or nil), " <>
            "got: #{inspect(v)}"
  end

  @doc """
  Escapes a string for inclusion inside a JSON double-quoted literal. Every
  control character (< 0x20) is escaped: LF/CR/TAB as the short forms, all
  others (backspace, form feed, NUL, ESC, ...) as `\\u00XX` — a raw control
  byte would be a SyntaxError in the generated `.mjs` and break `JSON.parse`.
  """
  @spec escape_json(String.t()) :: String.t()
  def escape_json(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
    |> String.replace(~r/[\x00-\x1f]/, fn <<char>> ->
      hex = char |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0")
      "\\u" <> hex
    end)
  end

  defp json_key(k) when is_binary(k), do: k
  defp json_key(k), do: to_string(k)

  # Manifest entries carry property options only when the author declared them
  # (absent keeps the pre-1c manifest bytes for existing components).
  defp put_manifest_opt(map, _key, nil), do: map
  defp put_manifest_opt(map, key, value), do: Map.put(map, key, value)

  @doc "Spec rendered to a plain JSON-encodable map (used by `__tessera_manifest__/0`)."
  @spec to_manifest_map(t()) :: map()
  def to_manifest_map(%__MODULE__{} = spec) do
    %{
      "contractVersion" => spec.version,
      "tag" => spec.tag,
      "module" => spec.module && inspect(spec.module),
      "file" => spec.file,
      "js" => spec.js,
      "cy" => spec.cy,
      "attrs" =>
        Enum.map(spec.attrs, fn a ->
          %{
            "name" => Naming.snake_to_kebab(a.name),
            "type" => Atom.to_string(a.type),
            "required" => !!a[:required],
            "default" => a[:default]
          }
          |> put_manifest_opt("attribute", a[:attribute])
          |> put_manifest_opt("reflect", a[:reflect])
        end),
      "props" =>
        Enum.map(spec.props, fn p ->
          %{
            "name" => Naming.snake_to_camel(p.name),
            "type" => Atom.to_string(p.type),
            "json" => !!p[:json],
            "default" => p[:default]
          }
          |> put_manifest_opt("attribute", p[:attribute])
          |> put_manifest_opt("reflect", p[:reflect])
        end),
      "events" =>
        Enum.map(spec.events, fn e ->
          %{
            "name" => e.name,
            "detail" =>
              e[:detail]
              |> Map.new(fn {k, t} -> {Naming.snake_to_camel(k), Atom.to_string(t)} end)
          }
        end),
      "slots" => Enum.map(spec.slots, & &1.name),
      "cssProperties" =>
        Enum.map(spec.css_properties, fn c ->
          %{"name" => c.name, "default" => c[:default]}
        end),
      "parts" => Enum.map(spec.parts, & &1.name),
      "state" =>
        Enum.map(spec.state, fn s ->
          %{
            "name" => Atom.to_string(s.name),
            "type" => Atom.to_string(s.type),
            "default" => s[:default]
          }
          |> put_manifest_opt("attribute", s[:attribute])
          |> put_manifest_opt("reflect", s[:reflect])
        end),
      "actions" => Enum.map(spec.actions, &Atom.to_string(&1.name)),
      "lifecycle" =>
        (for hook <- [:should_update, :will_update, :first_updated, :updated],
             Map.has_key?(spec.lifecycle, hook),
             do: Atom.to_string(hook)),
      "template" =>
        if spec.template do
          %{"lexer" => Atom.to_string(spec.template.lexer), "raw" => spec.template.raw}
        else
          nil
        end,
      "styles" =>
        Enum.map(spec.styles, fn s ->
          %{"kind" => Atom.to_string(s.kind), "value" => s.value}
        end)
    }
  end
end
