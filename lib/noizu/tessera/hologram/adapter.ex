defmodule Noizu.Tessera.Hologram.Adapter do
  @moduledoc """
  Generates the Hologram component (the "adapter", CONTRACT.md §3/§5) inside a
  module that did `use Noizu.Tessera.Component`.

  The generated component, in the same module as the spec:

    * declares a Hologram `prop` for every `attr` and every `on_<event>`
      binding prop — put directly by the DSL macros during module-body
      expansion, so they are part of Hologram's `@__props__` accumulator
      before Hologram's `__before_compile__` runs (hooks run in registration
      order). Json/regular `prop` entries are declared by the author's own
      `prop` DSL line, which delegates to Hologram's `prop` macro, with
      tessera opts `json:`/`default:` riding along;
    * renders the component tag with kebab-case attributes, booleans by
      presence (`nil`/`false` values make Hologram drop the attribute),
      `tsr-props` JSON (camelCase keys, omitted when no json prop is set),
      the `data-tsr-on` bridge map built from the binding props
      (`:action` ⇒ `@page`; `{:action, target: "layout" | cid}`), `data-cy`,
      and passes slot content through with `<slot />`;
    * the `js_import` of the component `.mjs` by ABSOLUTE path (built from the
      component module's `__DIR__`) binding `register` is emitted as raw
      `@__js_imports__`/`@external_resource` attributes at `__using__` time
      (same expansion as Hologram's own `js_import/2` macro produces), and a
      generated `init/3` calls it via `Hologram.JS.call/2` so the bundler
      keeps it (CONTRACT.md §5).
  """

  alias Noizu.Tessera.Codegen
  alias Noizu.Tessera.Naming
  alias Noizu.Tessera.Spec

  @doc "True when Hologram is compiled into the path (adapter generation is gated on this)."
  @spec available?() :: boolean()
  def available? do
    match?({:module, _}, Code.ensure_loaded(Hologram.Component))
  end

  @doc "The absolute `.mjs` path for a spec module file + colocated js filename."
  @spec mjs_path(String.t(), String.t()) :: String.t()
  def mjs_path(module_file, js) do
    module_file
    |> Path.dirname()
    |> Path.join(js)
    |> Path.expand()
  end

  @doc """
  The raw AST equivalent of Hologram's `js_import(:register, from: path)` —
  the `@__js_imports__` + `@external_resource` attribute puts. Emitted at
  `__using__` time so the entries are in the accumulator before any
  `__before_compile__` runs.
  """
  @spec js_import_asts(String.t() | nil) :: [Macro.t()]
  def js_import_asts(nil), do: []

  def js_import_asts(mjs_path) when is_binary(mjs_path) do
    [
      quote do
        @external_resource unquote(mjs_path)
        @__js_imports__ %{export: "register", from: unquote(mjs_path), as: "register"}
      end
    ]
  end

  @doc """
  The `~HOLO` markup rendered by the generated component (CONTRACT.md §3).
  """
  @spec template_markup(Spec.t()) :: String.t()
  def template_markup(%Spec{} = spec) do
    attr_lines =
      Enum.map(spec.attrs, fn a -> "  #{Naming.snake_to_kebab(a.name)}={@#{a.name}}" end)

    tsr_props_line = tsr_props_line(spec)
    data_tsr_on_line = data_tsr_on_line(spec)
    cy_line = if spec.cy, do: ~s(  data-cy="#{spec.cy}")

    lines =
      (attr_lines ++ List.wrap(tsr_props_line) ++ List.wrap(data_tsr_on_line) ++ List.wrap(cy_line))
      |> Enum.reject(&is_nil/1)

    open = "<#{spec.tag}#{format_open(lines)}>"
    String.trim_trailing("""
    #{open}
      <slot />
    </#{spec.tag}>\
    """)
  end

  defp tsr_props_line(%Spec{} = spec) do
    json_props = Enum.filter(spec.props, fn p -> !!p[:json] end)

    if json_props != [] do
      pairs = Enum.map_join(json_props, ", ", fn p -> "#{p.name}: @#{p.name}" end)
      "  tsr-props={__tessera_props_json__(%{#{pairs}})}"
    end
  end

  defp data_tsr_on_line(%Spec{} = spec) do
    if spec.events != [] do
      pairs =
        Enum.map_join(spec.events, ", ", fn e ->
          binding = Naming.event_binding_prop(e.name)
          "#{binding}: @#{binding}"
        end)

      "  data-tsr-on={__tessera_data_tsr_on__(%{#{pairs}})}"
    end
  end

  defp format_open([]), do: ""

  defp format_open(lines), do: "\n" <> Enum.join(lines, "\n") <> "\n"

  @doc """
  `[{on_persona_select, "persona-select"}, ...]` — binding-prop atom to event
  name pairs, in spec order. Drives the generated `data-tsr-on` helper.
  """
  @spec event_pairs(Spec.t()) :: [{Naming.snake(), Naming.kebab()}]
  def event_pairs(%Spec{} = spec) do
    Enum.map(spec.events, fn e -> {Naming.event_binding_prop(e.name), e.name} end)
  end

  @doc """
  `[{tag_list, "tagList"}, ...]` — json prop atom to camelCase key pairs, in
  spec order. Drives the generated `tsr-props` helper.
  """
  @spec json_prop_pairs(%{props: [map()]}) :: [{Naming.snake(), Naming.camel()}]
  def json_prop_pairs(%{props: props}) do
    props
    |> Enum.filter(fn p -> !!p[:json] end)
    |> Enum.map(fn p -> {p.name, Naming.snake_to_camel(p.name)} end)
  end

  @doc """
  Hologram `prop` declaration entries the DSL must put into `@__props__`
  (Hologram's own `{name, type, opts}` shape): one per attr and one
  `on_<event>` binding prop per event. Put during module-body expansion —
  NOT from `__before_compile__` — so Hologram's `__before_compile__` (hooks
  run in registration order) sees the complete list.
  """
  @spec hologram_prop_entries(Spec.t()) :: [{atom(), atom(), keyword()}]
  def hologram_prop_entries(%Spec{} = spec) do
    attr_entries =
      Enum.map(spec.attrs, fn a -> {a.name, a.type, [default: a[:default]]} end)

    binding_entries =
      Enum.map(spec.events, fn e ->
        {Naming.event_binding_prop(e.name), :any, [default: nil]}
      end)

    attr_entries ++ binding_entries
  end

  @doc """
  The quoted AST of the generated component body: `init/3` (+ the
  `__tessera_init__/3` hook, both defoverridable), the template, the bridge
  helpers and the `__tessera_spec__/0` + `__tessera_manifest__/0` readers.
  Spliced from `__before_compile__` (the spec must be known). `caller_dir` is
  the directory of the component module's file; the `.mjs` import path is
  built from it and must be absolute (CONTRACT.md §5).
  """
  @spec body_ast(Spec.t(), String.t()) :: Macro.t()
  def body_ast(%Spec{} = spec, caller_dir) when is_binary(caller_dir) do
    quote do
      # Generated init: the client-side mount runs the transpiled init/2
      # derived from this init/3; `call(:register, [])` both defines the
      # custom element on mount and keeps the js_import in the page call
      # graph (Hologram only bundles imports the call graph references —
      # CONTRACT.md §5). On the server (SSR) it is an :ok pass-through.
      def init(props, component, server) do
        call(:register, [])
        __tessera_init__(props, component, server)
      end

      @doc """
      Default tessera init body — a no-op returning the component. Override
      this (not `init/3`) to seed state, so element registration keeps
      running; if you must override `init/3` itself, call
      `super(props, component, server)` first.
      """
      def __tessera_init__(_props, component, _server), do: component

      defoverridable init: 3, __tessera_init__: 3

      @doc "The compiled `Noizu.Tessera.Spec` struct for this component."
      @spec __tessera_spec__() :: Noizu.Tessera.Spec.t()
      def __tessera_spec__, do: unquote(Macro.escape(spec))

      @doc "The tessera manifest entry (plain map) for this component."
      @spec __tessera_manifest__() :: map()
      def __tessera_manifest__, do: unquote(Macro.escape(Spec.to_manifest_map(spec)))

      @doc """
      The tessera template: renders the contract tag with kebab attrs,
      `tsr-props` JSON, the `data-tsr-on` bridge map, `data-cy` and the
      consumer's children as slot content. Generated — do not override.
      """
      def template do
        Hologram.Template.sigil_HOLO(unquote(template_markup(spec)), [])
      end

      unquote_splicing(bridge_helper_asts(spec))
    end
  end

  @doc """
  Writes the generated contract module next to the component's `.mjs`
  (colocated with the spec module) when `spec.js` is set and the content
  changed. Warns (never raises) when the write fails, so a read-only source
  tree cannot break the host build.
  """
  @spec write_contract_next_to_mjs(Spec.t()) :: :ok
  def write_contract_next_to_mjs(%Spec{js: nil}), do: :ok

  def write_contract_next_to_mjs(%Spec{file: nil}), do: :ok

  def write_contract_next_to_mjs(%Spec{} = spec) do
    dir = Path.dirname(spec.file)

    case Codegen.write_contract_module(spec, dir) do
      :written ->
        :ok

      :unchanged ->
        :ok

      {:error, reason} ->
        IO.warn(
          "noizu_tessera: could not write generated contract module " <>
            "#{inspect(Codegen.contract_path(spec, dir))}: #{inspect(reason)}. " <>
            "The component's .mjs imports this file; run `mix compile` in a writable checkout.",
          []
        )

        :ok
    end
  end

  # -- internals -------------------------------------------------------------

  defp bridge_helper_asts(%Spec{} = spec) do
    if spec.events != [] or spec.props != [] and Enum.any?(spec.props, fn p -> !!p[:json] end) do
      event_pairs = event_pairs(spec)
      json_pairs = json_prop_pairs(spec)

      [
        quote do
          @doc false
          @spec __tessera_data_tsr_on__(map) :: String.t() | nil
          def __tessera_data_tsr_on__(bindings) do
            parts =
              Enum.flat_map(unquote(Macro.escape(event_pairs)), fn pair ->
                case Map.get(bindings, elem(pair, 0)) do
                  nil ->
                    []

                  binding ->
                    [
                      elem(pair, 1) <>
                        ":" <> tessera_action_name(binding) <> "@" <> tessera_target_name(binding)
                    ]
                end
              end)

            if parts == [], do: nil, else: Enum.join(parts, ";")
          end

          @doc false
          @spec __tessera_props_json__(map) :: String.t() | nil
          def __tessera_props_json__(bindings) do
            parts =
              Enum.flat_map(unquote(Macro.escape(json_pairs)), fn pair ->
                case Map.get(bindings, elem(pair, 0)) do
                  nil ->
                    []

                  value ->
                    ["\"" <> elem(pair, 1) <> "\":" <> __tessera_json_encode__(value)]
                end
              end)

            if parts == [], do: nil, else: "{" <> Enum.join(parts, ",")
          end

          # Minimal JSON encoder over the contract types, written with
          # client-transpilable ops only (this runs inside the page bundle on
          # re-render). Server-side output matches the Elixir-side encoder.
          @doc false
          def __tessera_json_encode__(nil), do: "null"
          def __tessera_json_encode__(true), do: "true"
          def __tessera_json_encode__(false), do: "false"

          def __tessera_json_encode__(value) when is_binary(value) do
            "\"" <> tessera_json_escape(value) <> "\""
          end

          def __tessera_json_encode__(value) when is_integer(value), do: Integer.to_string(value)

          def __tessera_json_encode__(value) when is_float(value), do: Float.to_string(value)

          def __tessera_json_encode__(value) when is_list(value) do
            "[" <> Enum.map_join(value, ",", &__tessera_json_encode__/1) <> "]"
          end

          def __tessera_json_encode__(value) when is_map(value) do
            inner =
              value
              |> Map.keys()
              |> Enum.sort()
              |> Enum.map_join(",", fn key ->
                tessera_json_key(key) <> ":" <> __tessera_json_encode__(Map.get(value, key))
              end)

            "{" <> inner <> "}"
          end

          def __tessera_json_encode__(value),
            do: "\"" <> tessera_json_escape(to_string(value)) <> "\""

          defp tessera_json_key(key) when is_atom(key), do: "\"" <> Atom.to_string(key) <> "\""

          defp tessera_json_key(key) when is_binary(key),
            do: "\"" <> tessera_json_escape(key) <> "\""

          defp tessera_json_key(key), do: "\"" <> tessera_json_escape(to_string(key)) <> "\""

          defp tessera_json_escape(value) do
            value
            |> String.replace("\\", "\\\\")
            |> String.replace("\"", "\\\"")
            |> String.replace("\n", "\\n")
            |> String.replace("\r", "\\r")
            |> String.replace("\t", "\\t")
          end

          defp tessera_action_name(action) when is_atom(action), do: Atom.to_string(action)

          defp tessera_action_name({action, _opts}) when is_atom(action),
            do: Atom.to_string(action)

          defp tessera_target_name({_action, opts}) when is_list(opts) do
            case :lists.keyfind(:target, 1, opts) do
              {:target, target} -> target
              _ -> "page"
            end
          end

          defp tessera_target_name(_), do: "page"
        end
      ]
    else
      []
    end
  end
end
