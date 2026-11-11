defmodule Noizu.Tessera.FromLit.Extractor do
  @moduledoc """
  Mechanical shape extraction from a Lit 3 component source (`.js`/`.ts`).

  Best-effort regex/scanner parsing — deliberately NOT a JavaScript parser.
  It recognizes the common Lit 3 declaration patterns and returns a plain
  JSON-able shape descriptor that `Noizu.Tessera.FromLit.Generator` turns
  into a tessera spec stub. Anything it cannot parse mechanically is surfaced
  in `"warnings"` — never silently dropped (a conversion tool that lies is
  worse than none).

  Supported patterns:

    * `@customElement("tag")` and `customElements.define("tag", Class)`;
    * `@property({...})` / `@state()` decorated fields (multiline options,
      TS annotations, `declare`/`accessor`/visibility modifiers, literal
      defaults);
    * `static properties = {...}` and `static get properties() { return {...} }`
      (option objects and `name: Type` shorthand, `state: true` entries);
    * `this.dispatchEvent(new CustomEvent("name", {detail: {...}, bubbles,
      composed}))` and `new Event("name")` — detail key types are inferred
      from literal values, non-literal values become `"any"`;
    * `<slot>` / `<slot name="...">` (unnamed slots become `"default"`);
    * `static styles = css\\`...\\`` (single, array, or getter form) — raw CSS
      text is captured; `${...}` interpolation is flagged, not resolved.

  Known limitations (warned, not guessed): computed defaults, custom
  converters / `hasChanged`, spread options, non-literal event names,
  interpolated styles, events constructed away from their `dispatchEvent`
  call, and templates nested inside `${...}` interpolations.

  Shape descriptor (string keys, JSON-encodable):

      %{
        "source" => path | nil,
        "tag" => "my-element" | nil,
        "class_name" => "MyElement" | nil,
        "properties" => [
          %{"name" => "displayName", "kind" => "property" | "state" | "static",
            "type" => "string" | "integer" | "float" | "boolean" | "list" | "map" | "any",
            "source_type" => "String" | "number" | nil,
            "default" => literal | nil, "default_expression" => raw | nil,
            "attribute" => true | false | "custom-name", "reflect" => boolean}
        ],
        "events" => [
          %{"name" => "persona-select",
            "detail" => [%{"name" => "personaId", "type" => "string"}],
            "bubbles" => boolean, "composed" => boolean}
        ],
        "slots" => [%{"name" => "header"}],
        "styles" => ["raw css", ...],
        "warnings" => ["..."]
      }
  """

  @type shape :: map()

  @doc """
  Extracts the shape descriptor from a Lit component source string. `opts`:
  `:path` — the source path recorded in `"source"` and used in warnings.
  """
  @spec extract(String.t(), keyword()) :: shape()
  def extract(source, opts \\ []) when is_binary(source) do
    path = opts[:path]
    cleaned = strip_comments(source)

    {tag, tag_warnings} = extract_tag(cleaned)
    {class_name, class_warnings} = extract_class(cleaned)
    {decorated, dec_warnings} = extract_decorated_properties(cleaned)
    {statics, static_warnings} = extract_static_properties(cleaned)
    {events, event_warnings} = extract_events(cleaned)
    {slots, slot_warnings} = extract_slots(cleaned)
    {styles, style_warnings} = extract_styles(cleaned)

    {properties, dup_warnings} = merge_properties(decorated, statics)

    warnings =
      (tag_warnings ++
         class_warnings ++
         dec_warnings ++
         static_warnings ++
         event_warnings ++ slot_warnings ++ style_warnings ++ dup_warnings)
      |> Enum.uniq()

    %{
      "source" => path,
      "tag" => tag,
      "class_name" => class_name,
      "properties" => properties,
      "events" => events,
      "slots" => slots,
      "styles" => styles,
      "warnings" => warnings
    }
  end

  @doc "Reads a file and extracts its shape. Returns `{:ok, shape}` or `{:error, reason}`."
  @spec extract_file(Path.t()) :: {:ok, shape()} | {:error, term()}
  def extract_file(path) do
    case File.read(path) do
      {:ok, source} -> {:ok, extract(source, path: path)}
      {:error, reason} -> {:error, reason}
    end
  end

  # -- tag / class -------------------------------------------------------------

  defp extract_tag(src) do
    cond do
      m = Regex.run(~r/@customElement\(\s*["']([^"']+)["']\s*\)/, src) ->
        {Enum.at(m, 1), []}

      m = Regex.run(~r/customElements\.define\(\s*["']([^"']+)["']/, src) ->
        {Enum.at(m, 1), []}

      true ->
        {nil,
         [
           "no @customElement/customElements.define tag found — pass --tag or rely on the filename"
         ]}
    end
  end

  defp extract_class(src) do
    case Regex.run(
           ~r/(?:export\s+)?class\s+([A-Za-z_$][\w$]*)\s+extends\s+(?:LitElement|ReactiveElement)\b/,
           src
         ) do
      [_, name] -> {name, []}
      nil -> {nil, ["no `class ... extends LitElement` found — is this a Lit component?"]}
    end
  end

  # -- decorated fields ----------------------------------------------------------

  defp extract_decorated_properties(src) do
    Regex.scan(~r/@(property|state)\b/, src, return: :index)
    |> Enum.map(fn [{start, len} | _captures] ->
      parse_decorated_field(src, start + len, :binary.part(src, start + 1, len - 1))
    end)
    |> Enum.reduce({[], []}, fn
      {nil, warnings}, {props, ws} -> {props, ws ++ warnings}
      {prop, warnings}, {props, ws} -> {[prop | props], ws ++ warnings}
    end)
    |> then(fn {props, ws} -> {Enum.reverse(props), ws} end)
  end

  defp parse_decorated_field(src, pos, decorator) do
    pos = skip_ws(src, pos)

    {opts_raw, pos} =
      if at(src, pos) == ?( do
        {inner, next} = read_balanced(src, pos)
        {inner, next}
      else
        {"", pos}
      end

    pos = skip_ws(src, pos)
    pos = skip_modifiers(src, pos)
    pos = skip_ws(src, pos)

    case read_ident(src, pos) do
      {:error, _} ->
        {nil, ["@#{decorator} at offset #{pos}: could not read the field name — skipped"]}

      {name, pos} ->
        if String.starts_with?(name, "#") do
          {nil, ["@#{decorator} #{name}: private (#) fields are not wire surface — skipped"]}
        else
          pos = skip_ws(src, pos)

          {ts_type, pos} =
            if at(src, pos) == ?: do
              {type, next} = read_until(src, pos + 1, [:equals, :semicolon, :newline])
              {String.trim(type), next}
            else
              {nil, pos}
            end

          pos = skip_ws(src, pos)

          {default_expr, _pos} =
            if at(src, pos) == ?= do
              {expr, next} = read_until(src, pos + 1, [:semicolon, :newline])
              {String.trim(expr), next}
            else
              {nil, pos}
            end

          build_property(name, decorator, opts_raw, ts_type, default_expr)
        end
    end
  end

  # TS/JS field modifiers that can sit between the decorator and the name.
  defp skip_modifiers(src, pos) do
    Enum.reduce_while(
      ["declare", "accessor", "public", "private", "protected", "readonly", "static"],
      pos,
      fn _mod, acc ->
        case Regex.run(
               ~r/^(?:declare|accessor|public|private|protected|readonly|static)\b/,
               binary_part(src, acc, byte_size(src) - acc)
             ) do
          nil -> {:halt, acc}
          [m] -> {:cont, skip_ws(src, acc + byte_size(m))}
        end
      end
    )
  end

  defp build_property(name, decorator, opts_raw, ts_type, default_expr) do
    {opts, opt_warnings} = parse_options(opts_raw, name)

    {default, default_expression, default_warnings} =
      case default_expr do
        nil ->
          {nil, nil, []}

        expr ->
          case parse_literal(expr) do
            {:ok, value} ->
              {value, nil, []}

            :error ->
              {nil, expr,
               [
                 "#{name}: computed default `#{expr}` is not a literal — not carried into the stub"
               ]}
          end
      end

    kind = if decorator == "state" or opts["state"] == "true", do: "state", else: "property"

    {type, source_type, type_warnings} = resolve_type(opts["type"], ts_type, default, name)

    attribute =
      cond do
        kind == "state" -> false
        Map.has_key?(opts, "attribute") and opts["attribute"] == "false" -> false
        Map.has_key?(opts, "attribute") -> unquote_string(opts["attribute"]) || true
        true -> true
      end

    reflect = kind != "state" and opts["reflect"] == "true"

    prop = %{
      "name" => name,
      "kind" => kind,
      "type" => type,
      "source_type" => source_type,
      "default" => default,
      "default_expression" => default_expression,
      "attribute" => attribute,
      "reflect" => reflect
    }

    {prop, opt_warnings ++ default_warnings ++ type_warnings}
  end

  # -- static properties ---------------------------------------------------------

  defp extract_static_properties(src) do
    field = Regex.scan(~r/static\s+properties\s*=\s*\{/, src, return: :index)

    getter =
      Regex.scan(~r/static\s+get\s+properties\s*\(\s*\)\s*\{\s*return\s*\{/, src, return: :index)

    (field ++ getter)
    |> Enum.map(fn [{start, len}] ->
      brace = start + len - 1
      {inner, _next} = read_balanced(src, brace)
      parse_static_entries(inner)
    end)
    |> Enum.reduce({[], []}, fn {entries, ws}, {acc, accw} -> {acc ++ entries, accw ++ ws} end)
  end

  defp parse_static_entries(inner) do
    split_top_level(inner, ?,)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce({[], []}, fn entry, {props, ws} ->
      case split_first_colon(entry) do
        :error ->
          {props,
           ws ++ ["static properties entry `#{entry}` is not `name: options` — skipped (spread?)"]}

        {key, value} ->
          key = unquote_string(String.trim(key)) || String.trim(key)
          value = String.trim(value)

          opts_raw =
            if String.starts_with?(value, "{") do
              value
            else
              "{type: #{value}}"
            end

          {prop, more} = build_property(key, "property", opts_raw, nil, nil)

          {props ++
             [Map.put(prop, "kind", if(prop["kind"] == "state", do: "state", else: "static"))],
           ws ++ more}
      end
    end)
  end

  defp merge_properties(decorated, statics) do
    {merged, dups} =
      Enum.reduce(statics, {decorated, []}, fn prop, {acc, ws} ->
        if Enum.any?(acc, &(&1["name"] == prop["name"])) do
          {acc,
           ws ++
             [
               "#{prop["name"]}: declared both as a decorated field and in static properties — kept the decorated declaration"
             ]}
        else
          {acc ++ [prop], ws}
        end
      end)

    {merged, dups}
  end

  # -- options / types -------------------------------------------------------------

  defp parse_options("", _name), do: {%{}, []}

  defp parse_options(raw, name) do
    trimmed = String.trim(raw)

    if String.starts_with?(trimmed, "{") do
      {inner, _} = read_balanced(trimmed, 0)

      {pairs, warnings} =
        split_top_level(inner, ?,)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.reduce({%{}, []}, fn pair, {acc, ws} ->
          case split_first_colon(pair) do
            :error ->
              {acc, ws ++ ["#{name}: option `#{pair}` is not `key: value` — ignored (spread?)"]}

            {key, value} ->
              key = unquote_string(String.trim(key)) || String.trim(key)
              {Map.put(acc, key, String.trim(value)), ws}
          end
        end)

      unsupported =
        for key <- ["converter", "hasChanged", "noAccessor"], Map.has_key?(pairs, key) do
          "#{name}: Lit option `#{key}` has no tessera equivalent — port it by hand"
        end

      {pairs, warnings ++ unsupported}
    else
      {%{}, ["#{name}: decorator options are not an object literal — ignored"]}
    end
  end

  defp resolve_type(lit_type, ts_type, default, name) do
    cond do
      lit_type != nil ->
        case lit_type do
          "String" -> {"string", lit_type, []}
          "Number" -> {"float", lit_type, []}
          "Boolean" -> {"boolean", lit_type, []}
          "Array" -> {"list", lit_type, []}
          "Object" -> {"map", lit_type, []}
          other -> {"any", other, ["#{name}: unknown Lit type `#{other}` — mapped to :any"]}
        end

      ts_type != nil and ts_type != "" ->
        {type, warning} = type_from_ts(ts_type, name)
        {type, ts_type, warning}

      default != nil ->
        {type_from_literal(default), nil, []}

      true ->
        # Lit's default converter is String when no type is declared.
        {"string", nil, []}
    end
  end

  defp type_from_ts(ts, name) do
    normalized = String.replace(ts, ~r/\s+/, " ") |> String.trim()

    cond do
      normalized in ["string", "number", "boolean"] ->
        {normalized |> String.replace("number", "float"), []}

      normalized in ["any", "unknown"] ->
        {"any", []}

      String.ends_with?(normalized, "[]") or
        String.starts_with?(normalized, "Array<") or
          String.starts_with?(normalized, "ReadonlyArray<") ->
        {"list", []}

      normalized == "object" or String.starts_with?(normalized, "Record<") or
          String.starts_with?(normalized, "{") ->
        {"map", []}

      true ->
        {"any", ["#{name}: unmapped TS type `#{ts}` — mapped to :any"]}
    end
  end

  defp type_from_literal(v) when is_binary(v), do: "string"
  defp type_from_literal(v) when is_integer(v), do: "integer"
  defp type_from_literal(v) when is_float(v), do: "float"
  defp type_from_literal(v) when is_boolean(v), do: "boolean"
  defp type_from_literal(v) when is_list(v), do: "list"
  defp type_from_literal(v) when is_map(v), do: "map"
  defp type_from_literal(_), do: "any"

  # -- events ---------------------------------------------------------------------

  defp extract_events(src) do
    dispatched =
      Regex.scan(~r/dispatchEvent\s*\(/, src, return: :index)
      |> Enum.flat_map(fn [{start, len}] ->
        {args, _next} = read_balanced(src, start + len - 1)
        parse_dispatch_args(args)
      end)

    {events, warnings} = dedupe_events(dispatched)

    constructed = length(Regex.scan(~r/new\s+(?:CustomEvent|Event)\s*\(/, src))
    missed = constructed - length(dispatched)

    extra =
      if missed > 0 do
        [
          "#{missed} CustomEvent/Event construction(s) not tied to a dispatchEvent call — not captured"
        ]
      else
        []
      end

    {events, warnings ++ extra}
  end

  defp parse_dispatch_args(args) do
    case Regex.run(~r/new\s+(CustomEvent|Event)\s*\(/, args, return: :index) do
      nil ->
        []

      [{start, len} | _captures] ->
        {inner, _next} = read_balanced(args, start + len - 1)
        parts = split_top_level(inner, ?,) |> Enum.map(&String.trim/1)

        case parts do
          [name_raw | rest] ->
            case unquote_string(name_raw) do
              nil ->
                # non-literal event name — cannot be a wire contract
                []

              name ->
                opts = Enum.at(rest, 0, "")
                {detail, bubbles, composed} = parse_event_options(opts)

                [
                  %{
                    "name" => name,
                    "detail" => detail,
                    "bubbles" => bubbles,
                    "composed" => composed
                  }
                ]
            end

          [] ->
            []
        end
    end
  end

  defp parse_event_options(""), do: {[], false, false}

  defp parse_event_options(raw) do
    trimmed = String.trim(raw)

    if String.starts_with?(trimmed, "{") do
      {inner, _} = read_balanced(trimmed, 0)

      pairs =
        split_top_level(inner, ?,)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.flat_map(fn pair ->
          case split_first_colon(pair) do
            :error -> []
            {k, v} -> [{unquote_string(String.trim(k)) || String.trim(k), String.trim(v)}]
          end
        end)
        |> Map.new()

      detail =
        case Map.get(pairs, "detail") do
          nil ->
            []

          value ->
            if String.starts_with?(value, "{") do
              {obj, _} = read_balanced(value, 0)

              split_top_level(obj, ?,)
              |> Enum.map(&String.trim/1)
              |> Enum.reject(&(&1 == ""))
              |> Enum.flat_map(fn pair ->
                case split_first_colon(pair) do
                  :error ->
                    []

                  {k, v} ->
                    key = unquote_string(String.trim(k)) || String.trim(k)

                    type =
                      case parse_literal(String.trim(v)) do
                        {:ok, lit} -> type_from_literal(lit)
                        :error -> "any"
                      end

                    [%{"name" => key, "type" => type}]
                end
              end)
            else
              []
            end
        end

      {detail, pairs["bubbles"] == "true", pairs["composed"] == "true"}
    else
      {[], false, false}
    end
  end

  defp dedupe_events(events) do
    {merged, warnings} =
      Enum.reduce(events, {[], []}, fn event, {acc, ws} ->
        case Enum.find(acc, &(&1["name"] == event["name"])) do
          nil ->
            {acc ++ [event], ws}

          existing ->
            merged_detail =
              (existing["detail"] ++ event["detail"])
              |> Enum.uniq_by(& &1["name"])

            merged =
              existing
              |> Map.put("detail", merged_detail)
              |> Map.update!("bubbles", &(&1 or event["bubbles"]))
              |> Map.update!("composed", &(&1 or event["composed"]))

            {Enum.map(acc, fn e -> if e["name"] == event["name"], do: merged, else: e end),
             ws ++ ["event #{event["name"]}: dispatched more than once — detail keys merged"]}
        end
      end)

    {merged, warnings}
  end

  # -- slots ------------------------------------------------------------------------

  defp extract_slots(src) do
    slots =
      Regex.scan(~r/<slot\b([^>]*?)\/?>/i, src)
      |> Enum.map(fn [_, attrs] ->
        case Regex.run(~r/name\s*=\s*["']([^"']+)["']/, attrs) do
          [_, name] -> %{"name" => name}
          nil -> %{"name" => "default"}
        end
      end)
      |> Enum.uniq()

    {slots, []}
  end

  # -- styles -------------------------------------------------------------------------

  defp extract_styles(src) do
    exprs =
      Regex.scan(~r/static\s+styles\s*=\s*/, src, return: :index)
      |> Enum.map(fn [{start, len}] ->
        {expr, _next} = read_until(src, start + len, [:semicolon, :newline])
        expr
      end)

    getter_exprs =
      Regex.scan(~r/static\s+get\s+styles\s*\(\s*\)\s*\{\s*return\s+/, src, return: :index)
      |> Enum.map(fn [{start, len}] ->
        {expr, _next} = read_until(src, start + len, [:semicolon, :newline])
        expr
      end)

    {styles, warnings} =
      Enum.reduce(exprs ++ getter_exprs, {[], []}, fn expr, {acc, ws} ->
        {css, more} = extract_css_templates(expr)
        {acc ++ css, ws ++ more}
      end)

    {styles, Enum.uniq(warnings)}
  end

  defp extract_css_templates(expr) do
    matches = Regex.scan(~r/\bcss`/, expr, return: :index)

    if matches == [] do
      if String.trim(expr) == "" do
        {[], []}
      else
        {[], ["static styles is not a css`` literal — not captured (imported/unsafeCSS styles?)"]}
      end
    else
      Enum.reduce(matches, {[], []}, fn [{start, len}], {acc, ws} ->
        {raw, _next} = read_template(expr, start + len - 1)
        inner = binary_part(raw, 1, byte_size(raw) - 2)

        warning =
          if String.contains?(inner, "${") do
            ["styles contain ${...} interpolation — captured raw, resolve by hand"]
          else
            []
          end

        {acc ++ [inner], ws ++ warning}
      end)
    end
  end

  # -- literals -----------------------------------------------------------------------

  @doc false
  # Parses a JS literal expression into a JSON-safe Elixir term. Returns
  # `{:ok, value}` or `:error` for anything non-literal (identifiers, calls,
  # member expressions, template literals, ...).
  @spec parse_literal(String.t()) :: {:ok, term()} | :error
  def parse_literal(raw) do
    trimmed = String.trim(raw)

    cond do
      trimmed in ["true", "false"] ->
        {:ok, trimmed == "true"}

      trimmed in ["null", "undefined"] ->
        {:ok, nil}

      unquote_string(trimmed) != nil ->
        {:ok, unquote_string(trimmed)}

      Regex.match?(~r/^-?\d+$/, trimmed) ->
        {:ok, String.to_integer(trimmed)}

      Regex.match?(~r/^-?(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?$/, trimmed) ->
        {:ok, String.to_float(trimmed)}

      trimmed == "[]" ->
        {:ok, []}

      trimmed == "{}" ->
        {:ok, %{}}

      String.starts_with?(trimmed, "[") and String.ends_with?(trimmed, "]") ->
        parse_array(trimmed)

      String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}") ->
        parse_object(trimmed)

      true ->
        :error
    end
  end

  defp parse_array(raw) do
    {inner, _} = read_balanced(raw, 0)

    if String.trim(inner) == "" do
      {:ok, []}
    else
      inner
      |> split_top_level(?,)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce_while([], fn elem, acc ->
        case parse_literal(elem) do
          {:ok, v} -> {:cont, [v | acc]}
          :error -> {:halt, :error}
        end
      end)
      |> case do
        :error -> :error
        list -> {:ok, Enum.reverse(list)}
      end
    end
  end

  defp parse_object(raw) do
    {inner, _} = read_balanced(raw, 0)

    if String.trim(inner) == "" do
      {:ok, %{}}
    else
      inner
      |> split_top_level(?,)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce_while(%{}, fn pair, acc ->
        with {key, value} <- split_first_colon(pair),
             key when is_binary(key) <- unquote_string(String.trim(key)) || String.trim(key),
             {:ok, v} <- parse_literal(String.trim(value)) do
          {:cont, Map.put(acc, key, v)}
        else
          _ -> {:halt, :error}
        end
      end)
      |> case do
        :error -> :error
        map -> {:ok, map}
      end
    end
  end

  # -- comment stripping ----------------------------------------------------------------

  # Removes // and /* */ comments while preserving string/template contents
  # (a `//` inside "https://..." is not a comment). Block comments become a
  # single space so tokens never glue together. Template literals are skipped
  # wholesale to the next unescaped backtick — a backtick nested inside a
  # `${...}` interpolation can end the skip early (documented limitation).
  @doc false
  @spec strip_comments(String.t()) :: String.t()
  def strip_comments(source) do
    do_strip(source, 0, [:code], [])
    |> IO.iodata_to_binary()
  end

  defp do_strip(src, pos, _stack, acc) when pos >= byte_size(src), do: Enum.reverse(acc)

  defp do_strip(src, pos, [state | rest] = stack, acc) do
    c = :binary.at(src, pos)
    two = if pos + 1 < byte_size(src), do: binary_part(src, pos, 2), else: <<c>>

    case state do
      :code ->
        cond do
          two == "//" -> do_strip(src, pos + 2, [:line | stack], acc)
          two == "/*" -> do_strip(src, pos + 2, [:block | stack], acc)
          c in [?", ?'] -> do_strip(src, pos + 1, [{:string, c} | stack], [acc, <<c>>])
          c == ?` -> do_strip(src, pos + 1, [:template | stack], [acc, <<c>>])
          true -> do_strip(src, pos + 1, stack, [acc, <<c>>])
        end

      :line ->
        if c == ?\n do
          do_strip(src, pos + 1, rest, [acc, <<c>>])
        else
          do_strip(src, pos + 1, stack, acc)
        end

      :block ->
        if two == "*/" do
          do_strip(src, pos + 2, rest, [acc, " "])
        else
          do_strip(src, pos + 1, stack, acc)
        end

      {:string, q} ->
        cond do
          c == ?\\ and pos + 1 < byte_size(src) ->
            do_strip(src, pos + 2, stack, [acc, binary_part(src, pos, 2)])

          c == q ->
            do_strip(src, pos + 1, rest, [acc, <<c>>])

          true ->
            do_strip(src, pos + 1, stack, [acc, <<c>>])
        end

      :template ->
        cond do
          c == ?\\ and pos + 1 < byte_size(src) ->
            do_strip(src, pos + 2, stack, [acc, binary_part(src, pos, 2)])

          c == ?` ->
            do_strip(src, pos + 1, rest, [acc, <<c>>])

          two == "${" ->
            do_strip(src, pos + 2, [{:interp, 1} | stack], [acc, two])

          true ->
            do_strip(src, pos + 1, stack, [acc, <<c>>])
        end

      {:interp, depth} ->
        cond do
          two == "//" -> do_strip(src, pos + 2, [:line | stack], acc)
          two == "/*" -> do_strip(src, pos + 2, [:block | stack], acc)
          c in [?", ?'] -> do_strip(src, pos + 1, [{:string, c} | stack], [acc, <<c>>])
          c == ?` -> do_strip(src, pos + 1, [:template | stack], [acc, <<c>>])
          c == ?{ -> do_strip(src, pos + 1, [{:interp, depth + 1} | tl(stack)], [acc, <<c>>])
          c == ?} and depth == 1 -> do_strip(src, pos + 1, rest, [acc, <<c>>])
          c == ?} -> do_strip(src, pos + 1, [{:interp, depth - 1} | tl(stack)], [acc, <<c>>])
          true -> do_strip(src, pos + 1, stack, [acc, <<c>>])
        end
    end
  end

  # -- low-level scanning helpers ---------------------------------------------------------

  defp at(src, pos) when pos < byte_size(src), do: :binary.at(src, pos)
  defp at(_src, _pos), do: nil

  defp ws?(c), do: c in [?\s, ?\t, ?\r, ?\n]

  defp skip_ws(src, pos) do
    if pos < byte_size(src) and ws?(:binary.at(src, pos)) do
      skip_ws(src, pos + 1)
    else
      pos
    end
  end

  defp read_ident(src, pos) when pos >= byte_size(src), do: {:error, pos}

  defp read_ident(src, pos) do
    if :binary.at(src, pos) == ?# do
      pos = pos + 1
      {rest, next} = read_ident(src, pos)

      case rest do
        "" -> {:error, pos}
        name -> {"#" <> name, next}
      end
    else
      case Regex.run(~r/^[A-Za-z_$][\w$]*/, binary_part(src, pos, max(byte_size(src) - pos, 0))) do
        [name] -> {name, pos + byte_size(name)}
        nil -> {:error, pos}
      end
    end
  end

  # Reads a quoted string starting at `pos` (the opening quote). Returns the
  # raw slice including quotes and the position after the closing quote.
  defp read_string(src, pos) do
    q = :binary.at(src, pos)
    scan_string(src, pos + 1, q, pos)
  end

  defp scan_string(src, pos, q, start) do
    cond do
      pos >= byte_size(src) -> {binary_part(src, start, pos - start), pos}
      :binary.at(src, pos) == ?\\ -> scan_string(src, min(pos + 2, byte_size(src)), q, start)
      :binary.at(src, pos) == q -> {binary_part(src, start, pos + 1 - start), pos + 1}
      true -> scan_string(src, pos + 1, q, start)
    end
  end

  # Reads a template literal starting at `pos` (the opening backtick), naive:
  # to the next unescaped backtick (see strip_comments limitation).
  defp read_template(src, pos), do: scan_string(src, pos + 1, ?`, pos)

  @openers %{?( => ?), ?{ => ?}, ?[ => ?]}
  @closers %{?) => ?(, ?} => ?{, ?] => ?[}

  # Reads a balanced bracket group starting at `pos` (the opener). Returns
  # the inner slice (without the outer brackets) and the position after the
  # closer. Strings/templates inside are skipped; all bracket kinds count.
  defp read_balanced(src, pos) do
    opener = :binary.at(src, pos)
    closer = Map.fetch!(@openers, opener)
    scan_balanced(src, pos + 1, closer, 1, pos + 1)
  end

  defp scan_balanced(src, pos, closer, depth, inner_start) do
    cond do
      pos >= byte_size(src) ->
        {binary_part(src, inner_start, pos - inner_start), pos}

      :binary.at(src, pos) in [?", ?'] ->
        {_, next} = read_string(src, pos)
        scan_balanced(src, next, closer, depth, inner_start)

      :binary.at(src, pos) == ?` ->
        {_, next} = read_template(src, pos)
        scan_balanced(src, next, closer, depth, inner_start)

      Map.has_key?(@openers, :binary.at(src, pos)) ->
        scan_balanced(src, pos + 1, closer, depth + 1, inner_start)

      :binary.at(src, pos) == closer and depth == 1 ->
        {binary_part(src, inner_start, pos - inner_start), pos + 1}

      Map.has_key?(@closers, :binary.at(src, pos)) ->
        scan_balanced(src, pos + 1, closer, depth - 1, inner_start)

      true ->
        scan_balanced(src, pos + 1, closer, depth, inner_start)
    end
  end

  # Reads from `pos` until a top-level stopper: `;`, `=` (when requested) or
  # a newline at bracket depth 0. Brackets/strings/templates are skipped.
  defp read_until(src, pos, stoppers) do
    scan_until(src, pos, pos, 0, stoppers)
  end

  defp scan_until(src, pos, start, depth, stoppers) do
    cond do
      pos >= byte_size(src) ->
        {binary_part(src, start, pos - start), pos}

      :binary.at(src, pos) in [?", ?'] ->
        {_, next} = read_string(src, pos)
        scan_until(src, next, start, depth, stoppers)

      :binary.at(src, pos) == ?` ->
        {_, next} = read_template(src, pos)
        scan_until(src, next, start, depth, stoppers)

      Map.has_key?(@openers, :binary.at(src, pos)) ->
        scan_until(src, pos + 1, start, depth + 1, stoppers)

      Map.has_key?(@closers, :binary.at(src, pos)) ->
        scan_until(src, pos + 1, start, max(depth - 1, 0), stoppers)

      depth == 0 and :binary.at(src, pos) == ?; and :semicolon in stoppers ->
        {binary_part(src, start, pos - start), pos}

      depth == 0 and :binary.at(src, pos) == ?= and :equals in stoppers ->
        {binary_part(src, start, pos - start), pos}

      depth == 0 and :binary.at(src, pos) == ?\n and :newline in stoppers ->
        {binary_part(src, start, pos - start), pos}

      true ->
        scan_until(src, pos + 1, start, depth, stoppers)
    end
  end

  # Splits on a separator char at bracket depth 0, string/template aware.
  defp split_top_level(str, sep) do
    do_split(str, 0, 0, 0, sep, [])
    |> Enum.reverse()
  end

  defp do_split(str, pos, start, depth, sep, acc) do
    cond do
      pos >= byte_size(str) ->
        [binary_part(str, start, pos - start) | acc]

      :binary.at(str, pos) in [?", ?'] ->
        {_, next} = read_string(str, pos)
        do_split(str, next, start, depth, sep, acc)

      :binary.at(str, pos) == ?` ->
        {_, next} = read_template(str, pos)
        do_split(str, next, start, depth, sep, acc)

      Map.has_key?(@openers, :binary.at(str, pos)) ->
        do_split(str, pos + 1, start, depth + 1, sep, acc)

      Map.has_key?(@closers, :binary.at(str, pos)) ->
        do_split(str, pos + 1, start, max(depth - 1, 0), sep, acc)

      depth == 0 and :binary.at(str, pos) == sep ->
        do_split(str, pos + 1, pos + 1, depth, sep, [binary_part(str, start, pos - start) | acc])

      true ->
        do_split(str, pos + 1, start, depth, sep, acc)
    end
  end

  # Splits `key: value` at the first top-level colon. Returns :error when
  # there is none (e.g. a spread entry).
  defp split_first_colon(str) do
    case find_colon(str, 0, 0) do
      nil -> :error
      pos -> {binary_part(str, 0, pos), binary_part(str, pos + 1, byte_size(str) - pos - 1)}
    end
  end

  defp find_colon(str, pos, depth) do
    cond do
      pos >= byte_size(str) ->
        nil

      :binary.at(str, pos) in [?", ?'] ->
        {_, next} = read_string(str, pos)
        find_colon(str, next, depth)

      :binary.at(str, pos) == ?` ->
        {_, next} = read_template(str, pos)
        find_colon(str, next, depth)

      Map.has_key?(@openers, :binary.at(str, pos)) ->
        find_colon(str, pos + 1, depth + 1)

      Map.has_key?(@closers, :binary.at(str, pos)) ->
        find_colon(str, pos + 1, max(depth - 1, 0))

      depth == 0 and :binary.at(str, pos) == ?: ->
        pos

      true ->
        find_colon(str, pos + 1, depth)
    end
  end

  # If `raw` is a quoted string literal, returns its unescaped content;
  # otherwise nil.
  defp unquote_string(raw) do
    trimmed = String.trim(raw)

    if byte_size(trimmed) >= 2 do
      first = :binary.at(trimmed, 0)
      last = :binary.at(trimmed, byte_size(trimmed) - 1)

      if first in [?", ?'] and first == last do
        trimmed
        |> binary_part(1, byte_size(trimmed) - 2)
        |> unescape()
      end
    end
  end

  defp unescape(str), do: do_unescape(str, 0, [])

  defp do_unescape(str, pos, acc) when pos >= byte_size(str),
    do: IO.iodata_to_binary(Enum.reverse(acc))

  defp do_unescape(str, pos, acc) do
    case :binary.at(str, pos) do
      ?\\ when pos + 1 < byte_size(str) ->
        next = :binary.at(str, pos + 1)

        decoded =
          case next do
            ?n -> "\n"
            ?t -> "\t"
            ?r -> "\r"
            ?b -> "\b"
            ?f -> "\f"
            ?v -> "\v"
            ?0 -> <<0>>
            other -> <<other>>
          end

        do_unescape(str, pos + 2, [decoded | acc])

      c ->
        do_unescape(str, pos + 1, [<<c>> | acc])
    end
  end
end
