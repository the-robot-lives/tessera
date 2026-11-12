defmodule Noizu.Tessera.FromLit.Generator do
  @moduledoc """
  Turns a `Noizu.Tessera.FromLit.Extractor` shape descriptor into a tessera
  component stub: the spec module (attr/prop/event/slot/cy DSL), a colocated
  Lit-based `.mjs` element template, and the WTR test skeleton.

  Pure functions of their arguments (the Mix task only parses args and writes
  files), mirroring `Noizu.Tessera.Scaffold`. File layout and the WTR skeleton
  are reused from `Scaffold.generate/3` so a converted component is
  indistinguishable from a scaffolded one.

  Everything the contract grammar cannot represent is adapted LOUDLY (a
  warning + a comment in the generated file), never silently:

    * single-word / camelCase Lit event names are kebab-cased, and hyphen-less
      names are prefixed with the tag (`close` → `<tag>-close`);
    * Lit `@state` fields become commented-out `state` declarations (the
      element DSL is all-or-nothing: state + actions + template);
    * custom Lit `attribute:` names that differ from the snake→kebab wire name
      are flagged; complex (list/map) properties always ship as `json: true`
      props through tsr-props;
    * names that fail the snake_case grammar or the snake↔camel round-trip
      are skipped with a warning.
  """

  alias Noizu.Tessera.FromLit.Extractor
  alias Noizu.Tessera.FromLit.Render
  alias Noizu.Tessera.Naming
  alias Noizu.Tessera.Scaffold

  @doc """
  Builds the stub files for `shape` under host project `root`. Returns
  `{files, warnings}` where `files` is a list of `{absolute_path, content}`
  (the caller writes them). Raises `CompileError` when the tag violates the
  contract grammar.
  """
  @spec generate(Extractor.shape(), String.t(), String.t(), keyword()) ::
          {[{String.t(), String.t()}], [String.t()]}
  def generate(shape, module_name, root, opts \\ []) do
    tag = shape["tag"]
    {plan, warnings} = plan(shape, Keyword.get(opts, :render, true))

    [{lib_path, _spec}, {mjs_path, _mjs}, test_file] = Scaffold.generate(tag, module_name, root)
    spec = {lib_path, spec_module_content(shape, module_name, plan, warnings)}

    files =
      if plan.render do
        # element generated from the spec at `mix compile` — no hand-written stub
        [spec, test_file]
      else
        [spec, {mjs_path, mjs_content(shape, plan)}, test_file]
      end

    {files, warnings}
  end

  # -- planning ------------------------------------------------------------------

  defp plan(shape, render?) do
    tag = shape["tag"]

    {attrs, props, states, prop_warnings} =
      Enum.reduce(shape["properties"] || [], {[], [], [], []}, fn prop,
                                                                  {attrs, props, states, ws} ->
        case plan_property(prop, tag) do
          {:attr, entry, more} -> {attrs ++ [entry], props, states, ws ++ more}
          {:prop, entry, more} -> {attrs, props ++ [entry], states, ws ++ more}
          {:state, entry, more} -> {attrs, props, states ++ [entry], ws ++ more}
          {:skip, more} -> {attrs, props, states, ws ++ more}
        end
      end)

    {events, event_warnings} =
      Enum.reduce(shape["events"] || [], {[], []}, fn event, {acc, ws} ->
        {name, name_warnings} = adapt_event_name(event["name"], tag)
        {detail, detail_warnings} = plan_detail(event["detail"] || [], name)
        {acc ++ [%{name: name, detail: detail}], ws ++ name_warnings ++ detail_warnings}
      end)

    {slots, slot_warnings} =
      Enum.reduce(shape["slots"] || [], {[], []}, fn slot, {acc, ws} ->
        name = slot["name"]

        if is_binary(name) and Regex.match?(~r/^[a-z][a-z0-9_-]*$/, name) do
          {acc ++ [name], ws}
        else
          {acc, ws ++ ["slot #{inspect(name)}: invalid tessera slot name — skipped"]}
        end
      end)

    {render, render_warnings} =
      plan_render(shape, render?, Enum.map(attrs ++ props ++ states, &{&1.original, &1.name}))

    {%{
       attrs: attrs,
       props: props,
       states: states,
       events: events,
       slots: slots,
       render: render
     }, prop_warnings ++ event_warnings ++ slot_warnings ++ render_warnings}
  end

  defp plan_render(shape, true, known) do
    with %{"template" => raw} <- shape["render"],
         %{markup: markup} = converted when markup != "" <- Render.convert(raw, Map.new(known)) do
      warnings =
        Enum.map(converted.todos, fn t ->
          "render(): #{t.reason} — `#{t.snippet}` left as a TODO marker in the template"
        end)

      {converted, warnings}
    else
      _ -> {nil, []}
    end
  end

  defp plan_render(_shape, false, _known), do: {nil, []}

  defp plan_property(prop, _tag) do
    original = prop["name"]

    case wire_name(original) do
      {:error, warning} ->
        {:skip, [warning]}

      {:ok, name} ->
        type = String.to_atom(prop["type"] || "any")
        default = prop["default"]
        reflect = prop["reflect"] == true
        attribute = prop["attribute"]

        computed_warning =
          if prop["default_expression"] do
            [
              "#{original}: computed default `#{prop["default_expression"]}` not carried — set it in the element"
            ]
          else
            []
          end

        cond do
          prop["kind"] == "state" ->
            {:state, %{name: name, type: type, default: default, original: original},
             computed_warning}

          type in [:list, :map] ->
            attribute_warning =
              if attribute not in [false, nil] do
                [
                  "#{original}: complex Lit property ships as a json prop (tsr-props); Lit attribute observation dropped"
                ]
              else
                []
              end

            {:prop, %{name: name, type: type, json: true, default: default, original: original},
             computed_warning ++ attribute_warning}

          attribute == false ->
            {:prop, %{name: name, type: type, json: false, default: default, original: original},
             computed_warning}

          true ->
            kebab = Naming.snake_to_kebab(name)

            custom_attribute_warning =
              if is_binary(attribute) and attribute != kebab do
                [
                  "#{original}: custom Lit attribute #{inspect(attribute)} is not representable — the wire attribute is #{inspect(kebab)}"
                ]
              else
                []
              end

            {:attr,
             %{
               name: name,
               type: type,
               default: default,
               reflect: reflect,
               original: original,
               attribute: attribute
             }, computed_warning ++ custom_attribute_warning}
        end
    end
  end

  # JS identifier → tessera snake_case atom, validated against the contract
  # grammar AND the snake↔camel round-trip (Naming — never Macro.*).
  defp wire_name(original) do
    snake =
      original
      |> Naming.camel_to_snake()
      |> Atom.to_string()
      |> String.trim_leading("_")

    atom = String.to_atom(snake)

    cond do
      not Regex.match?(Naming.snake_regex(), snake) ->
        {:error, "#{original}: #{inspect(snake)} is not a snake_case contract name — skipped"}

      not Naming.round_trips?(atom) ->
        {:error,
         "#{original}: #{inspect(snake)} fails the snake↔camel wire round-trip — skipped (rename in the source)"}

      true ->
        {:ok, atom}
    end
  end

  defp adapt_event_name(name, tag) do
    kebab =
      name
      |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1-\\2")
      |> String.replace("_", "-")
      |> String.downcase()

    cond do
      Regex.match?(Naming.event_regex(), kebab) and kebab == name ->
        {name, []}

      Regex.match?(Naming.event_regex(), kebab) ->
        {kebab,
         [
           "event #{inspect(name)}: kebab-cased to #{inspect(kebab)} for the tessera contract — emit the new name in the element"
         ]}

      true ->
        adapted = "#{tag}-#{kebab}"

        {adapted,
         [
           "event #{inspect(name)}: the tessera grammar requires a hyphen — emitted as #{inspect(adapted)}; rename in spec AND element if you want the original"
         ]}
    end
  end

  defp plan_detail(detail, event_name) do
    Enum.reduce(detail, {[], []}, fn key, {acc, ws} ->
      case wire_name(key["name"]) do
        {:error, warning} ->
          {acc, ws ++ ["event #{event_name} detail: " <> warning]}

        {:ok, name} ->
          type = String.to_atom(key["type"] || "any")

          if Naming.known_type?(type) do
            {acc ++ [{name, type}], ws}
          else
            {acc ++ [{name, :any}],
             ws ++
               [
                 "event #{event_name} detail #{key["name"]}: unknown type #{inspect(type)} — mapped to :any"
               ]}
          end
      end
    end)
    |> then(fn {pairs, ws} -> {Map.new(pairs), ws} end)
  end

  # -- spec module -----------------------------------------------------------------

  @doc false
  @spec spec_module_content(Extractor.shape(), String.t(), map(), [String.t()]) :: String.t()
  def spec_module_content(shape, module_name, plan, warnings) do
    tag = shape["tag"]
    snake = String.replace(tag, "-", "_")
    source = shape["source"] || "a Lit component"

    # Extraction warnings ride along with the planning warnings so the
    # generated moduledoc is the complete honest inventory of what was not
    # carried (the task prints both sets too).
    warnings = (shape["warnings"] || []) ++ warnings

    state_fun = if plan.render, do: &live_state_line/1, else: &state_line/1

    {style_warnings, style_dsl} = styles_dsl(shape, plan)
    warnings = warnings ++ style_warnings

    warning_lines =
      if warnings == [] do
        []
      else
        ["", "  Conversion warnings (verify by hand):"] ++
          Enum.map(warnings, fn w -> "    * #{heredoc_safe(w)}" end)
      end

    dsl =
      Enum.map_join(plan.attrs, "\n", &attr_line/1) <>
        section(plan.props, &prop_line/1) <>
        section(plan.states, state_fun) <>
        section(plan.events, &event_line/1) <>
        section(plan.slots, fn name -> "  " <> ~s(slot "#{name}") end)

    # Built as explicit lines (not a nested heredoc) so the emitted module's
    # indentation is exact and the inner @moduledoc """ cannot terminate an
    # outer heredoc early.
    lines =
      [
        "defmodule #{module_name} do",
        "  @moduledoc \"\"\"",
        "  `#{tag}` — tessera web component spec, converted from Lit by",
        "  `mix tessera.from_lit` (source: #{source}).",
        "",
        "  STUB: the DSL below was extracted mechanically. Verify every entry",
        "  against the original element before shipping — see the tessera",
        "  `docs/notes/from-lit.md`. `mix compile` regenerates",
        "  `#{snake}.contract.generated.mjs` next to `#{snake}.mjs`."
      ] ++
        warning_lines ++
        [
          "  \"\"\"",
          "",
          "  use Noizu.Tessera.Component, tag: \"#{tag}\", js: \"#{snake}.mjs\"",
          "",
          dsl,
          "",
          "  cy \"#{tag}-root\""
        ] ++ style_dsl ++ render_dsl(plan.render) ++ ["end"]

    Enum.join(lines, "\n") <> "\n"
  end

  # warnings embed JS snippets: keep them inert inside the emitted heredoc
  defp heredoc_safe(w) do
    w
    |> String.replace("\\", "\\\\")
    |> String.replace("\#{", "\\\#{")
    |> String.replace("\"\"\"", "\\\"\\\"\\\"")
  end

  defp live_state_line(entry) do
    opts = default_opt(entry.default) || ""
    comment = entry_comment(entry, "state")
    "  #{comment}state :#{entry.name}, :#{entry.type}#{opts_suffix(opts)}"
  end

  # Non-interpolated `static styles` move to the `styles` DSL when the element
  # is generated from a template; interpolated blocks stay a warned comment.
  defp styles_dsl(_shape, %{render: nil}), do: {[], []}

  defp styles_dsl(shape, _plan) do
    {plain, interpolated} =
      Enum.split_with(shape["styles"] || [], fn css -> not String.contains?(css, "${") end)

    lines =
      Enum.flat_map(plain, fn css ->
        ["", "  styles(~CSS\"\"\""] ++ indent_block(dedent(css)) ++ ["  \"\"\")"]
      end)

    warnings =
      if interpolated == [],
        do: [],
        else: [
          "static styles with ${...} interpolation not carried into the `styles` DSL — port by hand"
        ]

    {warnings, lines}
  end

  defp render_dsl(nil), do: []

  defp render_dsl(render) do
    todo_lines =
      Enum.map(render.todos, fn t ->
        "  # TODO(tessera.from_lit): #{t.reason} — `#{t.snippet}`"
      end)

    template_lines =
      ["", "  template(~TSR\"\"\""] ++ indent_block(render.markup) ++ ["  \"\"\")"]

    action_lines =
      Enum.flat_map(render.actions, fn name ->
        [
          "",
          "  # Lit handler `#{name}` — port the method body (state/emit DSL); no-op stub.",
          "  action(:#{name}, fn state, _params -> state end)"
        ]
      end)

    [""] ++ todo_lines ++ template_lines ++ action_lines
  end

  defp dedent(text) do
    lines = text |> String.trim("\n") |> String.split("\n") |> Enum.map(&String.trim_trailing/1)

    indent =
      lines
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn l -> byte_size(l) - byte_size(String.trim_leading(l)) end)
      |> Enum.min(fn -> 0 end)

    Enum.map_join(lines, "\n", fn l ->
      if l == "", do: "", else: binary_part(l, indent, byte_size(l) - indent)
    end)
  end

  defp indent_block(text) do
    text |> String.split("\n") |> Enum.map(fn l -> if l == "", do: "", else: "  " <> l end)
  end

  defp section([], _fun), do: ""
  defp section(entries, fun), do: "\n" <> Enum.map_join(entries, "\n", fun)

  defp attr_line(entry) do
    opts =
      [
        default_opt(entry.default),
        if(entry[:reflect], do: "reflect: true"),
        # A custom Lit attribute name rides the attr itself as `attribute:`
        # (review on PR #54): reflected attrs must reflect to the ORIGINAL
        # attribute, not the kebab derivation of the snake_case atom.
        if(custom_attribute?(entry), do: ~s(attribute: "#{entry.attribute}"))
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    comment = entry_comment(entry, "attr")
    "  #{comment}attr :#{entry.name}, :#{entry.type}#{opts_suffix(opts)}"
  end

  # The DSL derives the wire attribute from the snake_case atom (kebab);
  # only a name that DIFFERS needs the explicit option.
  defp custom_attribute?(entry) do
    is_binary(entry[:attribute]) and
      entry.attribute != String.replace(Atom.to_string(entry.name), "_", "-")
  end

  defp prop_line(entry) do
    opts =
      [if(entry.json, do: "json: true"), default_opt(entry.default)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    comment = entry_comment(entry, "prop")
    "  #{comment}prop :#{entry.name}, :#{entry.type}#{opts_suffix(opts)}"
  end

  defp state_line(entry) do
    opts = default_opt(entry.default) || ""

    "  # Lit @state #{entry.original} — internal, not wire surface. Enable with the\n" <>
      "  # element DSL (state + actions + template ~TSR, docs/notes/spike-elixir-to-lit.md):\n" <>
      "  # state :#{entry.name}, :#{entry.type}#{opts_suffix(opts)}"
  end

  defp event_line(entry) do
    detail =
      if entry.detail == %{} do
        ""
      else
        inner =
          entry.detail
          |> Enum.sort_by(fn {k, _} -> Atom.to_string(k) end)
          |> Enum.map_join(", ", fn {k, t} -> "#{k}: :#{t}" end)

        ", detail: %{#{inner}}"
      end

    ~s(  event "#{entry.name}"#{detail})
  end

  defp entry_comment(entry, _kind) do
    notes =
      [
        if(entry.original != Atom.to_string(entry.name), do: "Lit: #{entry.original}")
        # reflect and custom attribute names ride the attr itself as
        # `reflect: true` / `attribute: "..."` (reviews on PRs #50/#54):
        # bare comments documented the flags without declaring them.
      ]
      |> Enum.reject(&is_nil/1)

    case notes do
      [] -> ""
      notes -> "# " <> Enum.join(notes, "; ") <> "\n  "
    end
  end

  defp default_opt(nil), do: nil
  defp default_opt(default), do: "default: #{elixir_literal(default)}"

  defp opts_suffix(""), do: ""
  defp opts_suffix(opts), do: ", " <> opts

  # Renders a JSON-safe default as an Elixir literal (Spec.json_literal/1
  # validates JSON-safety; the DSL needs Elixir syntax, not JSON).
  defp elixir_literal(nil), do: "nil"
  defp elixir_literal(v) when is_boolean(v) or is_number(v), do: to_string(v)
  defp elixir_literal(v) when is_binary(v), do: inspect(v)

  defp elixir_literal(v) when is_list(v),
    do: "[" <> Enum.map_join(v, ", ", &elixir_literal/1) <> "]"

  defp elixir_literal(v) when is_map(v) do
    inner =
      v
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.map_join(", ", fn {k, val} -> "#{inspect(k)} => #{elixir_literal(val)}" end)

    "%{#{inner}}"
  end

  # -- .mjs element stub --------------------------------------------------------------

  @doc false
  @spec mjs_content(Extractor.shape(), map()) :: String.t()
  def mjs_content(shape, plan) do
    tag = shape["tag"]
    snake = String.replace(tag, "-", "_")
    camel = Scaffold.camelize_tag(tag)
    styles = shape["styles"] || []
    interpolated? = Enum.any?(styles, &String.contains?(&1, "${"))

    lit_imports =
      if styles != [] and not interpolated?, do: "LitElement, html, css", else: "LitElement, html"

    styles_block =
      cond do
        styles == [] ->
          ""

        interpolated? ->
          "\n  // Extracted styles contain ${...} interpolation — resolve by hand, then uncomment:\n" <>
            Enum.map_join(styles, "\n", fn css ->
              "  // static styles = css`" <> css <> "`;"
            end) <> "\n"

        true ->
          case styles do
            [single] ->
              "\n  static styles = css`" <> single <> "`;\n"

            many ->
              "\n  static styles = [\n" <>
                Enum.map_join(many, ",\n", fn css -> "    css`" <> css <> "`" end) <> "\n  ];\n"
          end
      end

    state_note =
      case plan.states do
        [] ->
          ""

        states ->
          names = Enum.map_join(states, ", ", & &1.original)
          "  // Lit @state to port as internal reactive state: #{names}\n"
      end

    """
    // #{tag} — tessera web component, converted from Lit by mix tessera.from_lit.
    //
    // STUB: port the original element's render()/methods here. The generated
    // wire contract (./#{snake}.contract.generated.mjs) is regenerated by
    // `mix compile` from the spec module and already declares the reactive
    // attrs/props + defaults. Keep the `register` export — the Hologram
    // adapter binds it by name (CONTRACT.md §5).
    import { #{lit_imports} } from "lit";
    import { defineOnce, TesseraElement } from "@noizu/tessera-core";
    import contract from "./#{snake}.contract.generated.mjs";

    class #{camel} extends TesseraElement(LitElement, contract) {
    #{styles_block}#{state_note}  render() {
        // TODO: port the original Lit render() template.
        return html`<slot></slot>`;
      }
    }

    export function register() {
      return defineOnce("#{tag}", #{camel});
    }

    // LOAD-BEARING: top-level registration — page bundles define the element
    // when this module evaluates; defineOnce makes re-execution safe
    // (CONTRACT.md §3/§4).
    register();
    """
  end
end
