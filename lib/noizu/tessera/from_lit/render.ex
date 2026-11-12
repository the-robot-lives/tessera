defmodule Noizu.Tessera.FromLit.Render do
  @moduledoc """
  Converts a Lit `render() { return html\\`…\\` }` template into tessera `~TSR`
  markup for the template SUBSET the TSR compiler supports
  (`Noizu.Tessera.Component.Template` / `Expr`):

  | Lit | TSR |
  |---|---|
  | static markup | static markup |
  | `${this.x}` | `{@x}` |
  | `${c ? html\\`a\\` : html\\`b\\`}`, `${c && html\\`a\\`}` | `{%if c}a{%else}b{/if}` |
  | `${items.map((i) => html\\`…\\`)}` | `{%for i <- @items}…{/for}` |
  | `${repeat(items, (i) => i.id, (i) => html\\`…\\`)}` | `{%for i <- @items, key: i.id}…{/for}` |
  | `@click=${this.foo}` | `$click={:foo}` (+ an `action :foo` stub) |
  | `.prop=${…}`, `?attr=${…}`, `attr=${…}`, `attr="a ${…}"` | same shape, `{expr}` |
  | `classMap({…})`, `styleMap({…})`, `ifDefined`, `live`, `unsafeHTML`, `guard([…], expr)`, `nothing` | `class_map`, `style_map`, `if_defined`, `live`, `unsafe_html`, `guard`, `nothing` |

  Operators `=== !== == != < <= > >= + - * / % && || ! ?:` and string/number/
  boolean/null literals, `x.length` (→ `Enum.count`), `.toUpperCase()` /
  `.toLowerCase()` / `.trim()` and untagged template literals translate too.

  Operator semantics (TSR is compiled, not evaluated, on Tier 1 — the emitted
  Elixir lowers back to JS by `Expr`):

  * `===` and `==` both lower to strict JS `===` (`Expr` compiles Elixir `==`
    to `===`, expr.ex). JS `null` and `undefined` both map to `nil`, so
    `x == null` no longer also matches `undefined` — narrow `== null` guards
    by hand.
  * `&&`/`||`/`+` are emitted as Elixir `and`/`or`/`+`, which lower to JS
    `&&`/`||`/`+` — JS truthiness and string concatenation are preserved in
    the generated element. CAVEAT: Tier-2 SSR (`Hologram.Render`) evaluates
    the same markup as real Elixir on the server, where `and`/`or` demand
    booleans and `+` is numeric-only — keep those operands boolean/numeric if
    the component may be hosted on Tier 2.

  Nothing outside that subset is guessed: the construct is DROPPED from the
  markup and reported as a `todos` entry (`%{snippet, reason}`) which the
  generator turns into a `# TODO(tessera.from_lit): …` comment above the
  template plus a warning. The emitted markup therefore always compiles.

  Parsing is hand-rolled (no JS parser dependency): a nesting-aware template
  literal scanner, a small expression tokenizer/parser, and a char scanner
  that tracks whether each `${}` sits in child, attribute or quoted-attribute
  position.
  """

  alias Noizu.Tessera.Naming

  @void ~w(area base br col embed hr img input link meta source track wbr)
  @reserved ~w(do end fn nil true false when and or not in catch rescue after else)
  @directives ~w(classMap styleMap ifDefined live unsafeHTML guard)

  @render_re ~r/(?<![\w$.])(?:(?:public|protected|private|override)\s+)*render\s*\(\s*\)\s*(?::\s*[^{;=]+?)?\s*\{/

  @type todo :: %{snippet: String.t(), reason: String.t()}
  @type result :: %{markup: String.t(), todos: [todo()], actions: [String.t()]}

  # ---------------------------------------------------------------------------
  # locate (used by the Extractor)
  # ---------------------------------------------------------------------------

  @doc """
  Finds `render()` in comment-stripped Lit source and returns
  `{%{"template" => inner_raw} | nil, warnings}`; `inner_raw` is the text
  between the backticks of the first `return html\\`…\\``, nested templates intact.
  """
  @spec locate(String.t()) :: {map() | nil, [String.t()]}
  def locate(cleaned) when is_binary(cleaned) do
    case Regex.run(@render_re, cleaned, return: :index) do
      nil ->
        {nil, []}

      [{start, len}] ->
        from = start + len
        {body, _} = braced(binary_part(cleaned, from, byte_size(cleaned) - from), 1, [])
        locate_return(body)
    end
  end

  defp locate_return(body) do
    case Regex.run(~r/\breturn\s+html\s*`/, body, return: :index) do
      nil ->
        {nil,
         [
           "render(): no `return html`…`` found (other template tag, early/conditional return?) — template not converted"
         ]}

      [{s, l}] ->
        rest = binary_part(body, s + l, byte_size(body) - s - l)
        {_parts, after_tpl} = tpl(rest, [], [])
        raw = binary_part(rest, 0, byte_size(rest) - byte_size(after_tpl))

        inner =
          if String.ends_with?(raw, "`"), do: binary_part(raw, 0, byte_size(raw) - 1), else: raw

        preamble =
          if String.trim(binary_part(body, 0, s)) == "",
            do: [],
            else: [
              "render(): statements before `return` (locals/helpers) are not converted — references to them become TODOs"
            ]

        multi =
          if length(Regex.scan(~r/\breturn\b/, body)) > 1,
            do: [
              "render(): more than one `return` — only the first `return html`…`` was converted"
            ],
            else: []

        {%{"template" => inner}, preamble ++ multi}
    end
  end

  # ---------------------------------------------------------------------------
  # convert
  # ---------------------------------------------------------------------------

  @doc """
  Converts the raw template (`inner_raw` from `locate/1`) to TSR markup.
  `known` maps Lit property/state names (`"displayName"`) to their tessera
  snake_case atoms (`:display_name`) — only those are valid `this.x` reads.
  """
  @spec convert(String.t(), %{optional(String.t()) => atom()}) :: result()
  def convert(inner, known) when is_binary(inner) do
    {parts, _} = tpl(inner <> "`", [], [])
    ctx = %{known: known, scope: %{}, todos: [], actions: []}
    {markup, ctx} = convert_parts(parts, ctx)

    %{
      markup: tidy(markup),
      todos: ctx.todos |> Enum.reverse() |> Enum.uniq(),
      actions: ctx.actions |> Enum.reverse() |> Enum.uniq()
    }
  end

  defp convert_parts(parts, ctx) do
    {acc, _st, ctx} =
      Enum.reduce(parts, {"", :text, ctx}, fn
        {:text, t}, {acc, st, ctx} ->
          {out, st, ctx} = scan_text(t, st, "", ctx)
          {acc <> out, st, ctx}

        {:expr, js}, {acc, st, ctx} ->
          expr_part(js, acc, st, ctx)
      end)

    {acc, ctx}
  end

  # -- static text scanner ------------------------------------------------------

  defp scan_text("", st, out, ctx), do: {out, st, ctx}

  defp scan_text("<!--" <> rest, :text, out, ctx) do
    {rest, ctx} =
      case :binary.split(rest, "-->") do
        [_, after_comment] -> {after_comment, ctx}
        [_] -> {"", ctx}
      end

    scan_text(rest, :text, out, add_todo(ctx, "<!-- … -->", "HTML comment dropped"))
  end

  defp scan_text(<<c::utf8, rest::binary>>, st, out, ctx) when c in [?{, ?}] do
    scan_text(
      rest,
      st,
      out,
      add_todo(ctx, <<c::utf8>>, "literal brace in static markup needs escaping — dropped")
    )
  end

  defp scan_text("</" <> rest, :text, out, ctx) do
    case Regex.run(~r/^[A-Za-z][\w:-]*/, rest) do
      [name] ->
        scan_text(drop(rest, name), {:tag, String.downcase(name), true}, out <> "</" <> name, ctx)

      nil ->
        scan_text(rest, :text, out <> "</", ctx)
    end
  end

  defp scan_text("<" <> rest, :text, out, ctx) do
    case Regex.run(~r/^[A-Za-z][\w:-]*/, rest) do
      [name] ->
        scan_text(drop(rest, name), {:tag, String.downcase(name), false}, out <> "<" <> name, ctx)

      nil ->
        scan_text(rest, :text, out <> "<", ctx)
    end
  end

  defp scan_text("/>" <> rest, {:tag, _, _}, out, ctx),
    do: scan_text(rest, :text, out <> "/>", ctx)

  defp scan_text(">" <> rest, {:tag, name, closing}, out, ctx) do
    tail = if not closing and name in @void, do: " />", else: ">"
    scan_text(rest, :text, out <> tail, ctx)
  end

  defp scan_text(<<q, rest::binary>>, {:tag, n, cl}, out, ctx) when q in [?", ?'],
    do: scan_text(rest, {:quote, q, n, cl}, out <> <<q>>, ctx)

  defp scan_text(<<q, rest::binary>>, {:quote, q, n, cl}, out, ctx),
    do: scan_text(rest, {:tag, n, cl}, out <> <<q>>, ctx)

  defp scan_text(<<c::utf8, rest::binary>>, st, out, ctx),
    do: scan_text(rest, st, out <> <<c::utf8>>, ctx)

  defp drop(rest, name), do: binary_part(rest, byte_size(name), byte_size(rest) - byte_size(name))

  # -- ${expr} by position --------------------------------------------------------

  defp expr_part(js, acc, :text, ctx) do
    {out, ctx} = child(js, ctx)
    {acc <> out, :text, ctx}
  end

  defp expr_part(js, acc, {:tag, _, _} = st, ctx) do
    case Regex.run(~r/(?<=\s)([@.?]?)([A-Za-z_][\w:.-]*)=\z/, acc) do
      [full, prefix, name] ->
        head = String.replace_suffix(acc, full, "")

        case attr_tail(prefix, name, js, ctx) do
          {:ok, tail, ctx} ->
            {head <> tail, st, ctx}

          {:error, reason, ctx} ->
            {String.trim_trailing(head), st,
             add_todo(ctx, js, "`#{prefix}#{name}` binding: #{reason} — attribute omitted")}
        end

      nil ->
        {acc, st,
         add_todo(
           ctx,
           js,
           "interpolation is not an `attr=${…}` binding (element/spread part) — dropped"
         )}
    end
  end

  defp expr_part(js, acc, {:quote, _, _, _} = st, ctx) do
    prefix =
      case Regex.run(~r/([@.?]?)[A-Za-z_][\w:.-]*=["'][^"']*\z/, acc) do
        [_, p] -> p
        _ -> ""
      end

    result =
      if prefix != "" do
        {:error, "`#{prefix}` binding inside a quoted attribute value"}
      else
        with {:ok, ast} <- parse_expr(js) do
          try do
            if directive?(ast),
              do:
                throw(
                  {:unsupported,
                   "directive inside a quoted attribute value (unquote the binding)"}
                )

            {:ok, ex(ast, ctx)}
          catch
            {:unsupported, r} -> {:error, r}
          end
        end
      end

    case result do
      {:ok, s} -> {acc <> "{" <> s <> "}", st, ctx}
      {:error, r} -> {acc, st, add_todo(ctx, js, r <> " — interpolation dropped")}
    end
  end

  defp attr_tail(prefix, name, js, ctx) do
    with {:ok, ast} <- parse_expr(js) do
      try do
        case prefix do
          "@" ->
            action = handler(ast, ctx)
            {:ok, "$#{name}={:#{action}}", %{ctx | actions: [action | ctx.actions]}}

          p ->
            ctx = maybe_warn_unsafe_html(ast, ctx, js)
            {:ok, "#{p}#{name}={#{ex(ast, ctx)}}", ctx}
        end
      catch
        {:unsupported, r} -> {:error, r, ctx}
      end
    else
      {:error, r} -> {:error, r, ctx}
    end
  end

  defp handler({:member, {:this}, n}, ctx), do: action_name(n, ctx)

  defp handler({:call, {:member, {:member, {:this}, n}, "bind"}, [{:this}]}, ctx),
    do: action_name(n, ctx)

  defp handler(_, _),
    do:
      throw(
        {:unsupported,
         "event handler is not a plain `this.method` reference (inline arrow / call)"}
      )

  defp action_name(n, ctx) do
    snake = n |> Naming.camel_to_snake() |> Atom.to_string() |> String.trim_leading("_")

    if Regex.match?(Naming.snake_regex(), snake) and snake not in @reserved do
      if snake in ctx.actions do
        throw(
          {:unsupported,
           "handlers `_save`/`save` collapse to tessera action `:#{snake}` " <>
             "(a leading `_` is stripped) — rename one handler"}
        )
      else
        snake
      end
    else
      throw({:unsupported, "handler name #{inspect(n)} is not a valid tessera action name"})
    end
  end

  # -- child position ---------------------------------------------------------------

  defp child(js, ctx) do
    case parse_expr(js) do
      {:ok, ast} ->
        ctx = maybe_warn_unsafe_html(ast, ctx, js)
        safe_child(ast, ctx, js)

      {:error, reason} ->
        {"", add_todo(ctx, js, reason <> " — dropped")}
    end
  end

  defp safe_child(ast, ctx, snippet) do
    child_ast(ast, ctx)
  catch
    {:unsupported, reason} -> {"", add_todo(ctx, snippet, reason <> " — dropped")}
  end

  defp child_ast({:html, parts}, ctx), do: convert_parts(parts, ctx)

  defp child_ast({:ternary, c, a, b} = ast, ctx) do
    if branchy?(a) or branchy?(b) do
      cond_s = ex(c, ctx)
      {ma, ctx} = safe_child(a, ctx, "(then branch)")
      {mb, ctx} = safe_child(b, ctx, "(else branch)")

      block =
        cond do
          emptyish?(b) -> "{%if #{cond_s}}#{ma}{/if}"
          emptyish?(a) -> "{%if not #{ex_p(c, ctx)}}#{mb}{/if}"
          true -> "{%if #{cond_s}}#{ma}{%else}#{mb}{/if}"
        end

      {block, ctx}
    else
      generic(ast, ctx)
    end
  end

  defp child_ast({:bin, "&&", c, r} = ast, ctx) do
    if branchy?(r) do
      cond_s = ex(c, ctx)
      {mr, ctx} = safe_child(r, ctx, "(&& branch)")
      {"{%if #{cond_s}}#{mr}{/if}", ctx}
    else
      generic(ast, ctx)
    end
  end

  defp child_ast({:call, {:member, items, "map"}, [{:arrow, [p], body}]}, ctx),
    do: for_block(items, p, nil, body, ctx)

  defp child_ast(
         {:call, {:ident, "repeat"}, [items, {:arrow, [kp], kbody}, {:arrow, [p], body}]},
         ctx
       ) do
    key = ex(kbody, %{ctx | scope: Map.put(ctx.scope, kp, p)})
    for_block(items, p, key, body, ctx)
  end

  defp child_ast({:call, {:ident, "repeat"}, [items, {:arrow, [p], body}]}, ctx),
    do: for_block(items, p, nil, body, ctx)

  defp child_ast(ast, ctx), do: generic(ast, ctx)

  defp generic(ast, ctx), do: {"{" <> ex(ast, ctx) <> "}", ctx}

  defp for_block(items, p, key, body, ctx) do
    items_s = ex(items, ctx)
    var = loop_var!(p)
    outer = ctx.scope
    {m, ctx} = safe_child(body, %{ctx | scope: Map.put(outer, p, var)}, "(loop body)")
    ctx = %{ctx | scope: outer}
    key_s = if key, do: ", key: #{key}", else: ""
    {"{%for #{var} <- #{items_s}#{key_s}}#{m}{/for}", ctx}
  end

  defp loop_var!(p) do
    if Regex.match?(~r/^[a-z][A-Za-z0-9_]*$/, p) and p not in @reserved do
      p
    else
      throw(
        {:unsupported,
         "loop variable #{inspect(p)} is not a valid tessera template variable name"}
      )
    end
  end

  defp branchy?({:html, _}), do: true
  defp branchy?({:ternary, _, a, b}), do: branchy?(a) or branchy?(b)
  defp branchy?({:bin, "&&", _, r}), do: branchy?(r)
  defp branchy?({:call, {:member, _, "map"}, [{:arrow, [_], _}]}), do: true
  defp branchy?({:call, {:ident, "repeat"}, [_, {:arrow, _, _} | _]}), do: true
  defp branchy?(ast), do: emptyish?(ast)

  defp emptyish?({:ident, "nothing"}), do: true
  defp emptyish?({:str, ""}), do: true
  defp emptyish?({:null}), do: true
  defp emptyish?({:undef}), do: true
  defp emptyish?(_), do: false

  defp directive?({:call, {:ident, d}, _}) when d in @directives, do: true
  defp directive?({:ident, "nothing"}), do: true
  defp directive?(_), do: false

  # ---------------------------------------------------------------------------
  # expression translation (JS AST -> Elixir subset expression string)
  # ---------------------------------------------------------------------------

  defp ex({:num, s}, _ctx) do
    if Regex.match?(~r/^\d+(\.\d+)?$/, s),
      do: s,
      else: throw({:unsupported, "number literal #{s}"})
  end

  defp ex({:str, s}, _ctx) do
    if String.contains?(s, ["{", "}", "\\"]),
      do: throw({:unsupported, "string literal with braces/backslash"}),
      else: inspect(s)
  end

  defp ex({:bool, b}, _ctx), do: to_string(b)
  defp ex({:null}, _ctx), do: "nil"
  defp ex({:undef}, _ctx), do: "nil"
  defp ex({:ident, "nothing"}, _ctx), do: "nothing"

  defp ex({:ident, name}, ctx) do
    case Map.fetch(ctx.scope, name) do
      {:ok, var} ->
        var

      :error ->
        throw(
          {:unsupported,
           "identifier `#{name}` (render() local or import) is not in the supported subset"}
        )
    end
  end

  defp ex({:this}, _ctx), do: throw({:unsupported, "bare `this`"})

  defp ex({:member, {:this}, n}, ctx) do
    case Map.fetch(ctx.known, n) do
      {:ok, atom} ->
        "@#{atom}"

      :error ->
        throw(
          {:unsupported,
           "`this.#{n}` is not a converted property/state (getter, method or plain field)"}
        )
    end
  end

  defp ex({:member, obj, "length"}, ctx), do: "Enum.count(" <> ex(obj, ctx) <> ")"

  defp ex({:member, obj, name}, ctx) do
    cond do
      not Regex.match?(~r/^[a-z][A-Za-z0-9_]*$/, name) or name in @reserved ->
        throw({:unsupported, "member `.#{name}` is not a valid tessera template path"})

      not pathish?(obj) ->
        throw({:unsupported, "member access on a computed value"})

      true ->
        ex(obj, ctx) <> "." <> name
    end
  end

  defp ex({:index, _, _}, _), do: throw({:unsupported, "computed member access `[…]`"})
  defp ex({:not, x}, ctx), do: "not " <> ex_p(x, ctx)
  defp ex({:neg, x}, ctx), do: "-" <> ex_p(x, ctx)

  defp ex({:bin, op, l, r}, ctx) when op in ["===", "=="], do: bin("==", l, r, ctx)
  defp ex({:bin, op, l, r}, ctx) when op in ["!==", "!="], do: bin("!=", l, r, ctx)
  defp ex({:bin, "&&", l, r}, ctx), do: bin("and", l, r, ctx)
  defp ex({:bin, "||", l, r}, ctx), do: bin("or", l, r, ctx)
  defp ex({:bin, "%", l, r}, ctx), do: "rem(#{ex(l, ctx)}, #{ex(r, ctx)})"
  defp ex({:bin, "??", _, _}, _), do: throw({:unsupported, "nullish coalescing `??`"})
  defp ex({:bin, op, l, r}, ctx), do: bin(op, l, r, ctx)

  defp ex({:ternary, c, a, b}, ctx),
    do: "if(#{ex(c, ctx)}, do: #{ex(a, ctx)}, else: #{ex(b, ctx)})"

  defp ex({:tpl, parts}, ctx) do
    body =
      Enum.map_join(parts, fn
        {:text, t} ->
          if String.contains?(t, ["{", "}", "\\"]),
            do: throw({:unsupported, "template literal text with braces/backslash"})

          t |> String.replace("\"", "\\\"") |> String.replace("\#{", "\\\#{")

        {:expr, js} ->
          case parse_expr(js) do
            {:ok, a} -> "#" <> "{" <> ex(a, ctx) <> "}"
            {:error, r} -> throw({:unsupported, r})
          end
      end)

    ~s("#{body}")
  end

  defp ex({:html, _}, _),
    do: throw({:unsupported, "nested html`…` outside a ternary/&&/.map/repeat branch"})

  defp ex({:call, {:ident, "classMap"}, [arg]}, ctx), do: "class_map(" <> obj(arg, ctx) <> ")"
  defp ex({:call, {:ident, "styleMap"}, [arg]}, ctx), do: "style_map(" <> obj(arg, ctx) <> ")"
  defp ex({:call, {:ident, "ifDefined"}, [a]}, ctx), do: "if_defined(" <> ex(a, ctx) <> ")"
  defp ex({:call, {:ident, "live"}, [a]}, ctx), do: "live(" <> ex(a, ctx) <> ")"

  defp ex({:call, {:ident, "unsafeHTML"}, [a]}, ctx) do
    # The XSS-sink warning is added where the call ENTERS conversion (child /
    # attribute position — see maybe_warn_unsafe_html/3); ex/2 cannot thread
    # todos, so this clause only does the renaming.
    "unsafe_html(" <> ex(a, ctx) <> ")"
  end

  defp ex({:call, {:ident, "guard"}, [{:arr, deps}, {:arrow, [], body}]}, ctx) do
    if match?({:html, _}, body),
      do: throw({:unsupported, "guard() with an html`…` body (only value expressions)"})

    "guard([#{Enum.map_join(deps, ", ", &ex(&1, ctx))}], #{ex(body, ctx)})"
  end

  defp ex({:call, {:ident, "guard"}, _}, _),
    do:
      throw(
        {:unsupported,
         "guard() takes a literal dep array and a value-expression body — " <>
           "`guard([this.a, this.b], expr)`; variable deps or html bodies are outside the subset"}
      )

  defp ex({:call, {:member, o, m}, []}, ctx) when m in ["toUpperCase", "toLowerCase", "trim"] do
    fun = %{"toUpperCase" => "upcase", "toLowerCase" => "downcase", "trim" => "trim"}[m]
    "String.#{fun}(#{ex(o, ctx)})"
  end

  defp ex({:call, {:member, {:this}, m}, _}, _),
    do: throw({:unsupported, "method call `this.#{m}()` — port the helper by hand"})

  defp ex({:call, {:member, _, m}, _}, _),
    do: throw({:unsupported, "method call `.#{m}()` is outside the supported subset"})

  defp ex({:call, {:ident, f}, _}, _) do
    throw(
      {:unsupported,
       "call `#{f}(…)` is outside the supported subset " <>
         "(classMap/styleMap/ifDefined/live/unsafeHTML/guard/repeat are supported)"}
    )
  end

  defp ex({:call, _, _}, _), do: throw({:unsupported, "call expression"})
  defp ex({:arrow, _, _}, _), do: throw({:unsupported, "arrow function in value position"})
  defp ex({:arr, _}, _), do: throw({:unsupported, "array literal outside guard()"})
  defp ex({:obj, _}, _), do: throw({:unsupported, "object literal outside classMap/styleMap"})

  defp bin(op, l, r, ctx), do: "#{ex_p(l, ctx)} #{op} #{ex_p(r, ctx)}"

  # parenthesize anything that is not atomic
  defp ex_p(ast, ctx) do
    if atomic?(ast), do: ex(ast, ctx), else: "(" <> ex(ast, ctx) <> ")"
  end

  defp atomic?({t, _}) when t in [:num, :str, :bool], do: true
  defp atomic?({t}) when t in [:null, :undef], do: true
  defp atomic?({:ident, _}), do: true
  defp atomic?({:member, _, "length"}), do: true
  defp atomic?({:member, o, _}), do: pathish?(o)
  defp atomic?(_), do: false

  defp pathish?({:ident, _}), do: true
  defp pathish?({:member, {:this}, _}), do: true
  defp pathish?({:member, o, _}), do: pathish?(o)
  defp pathish?(_), do: false

  # directive object argument: classMap({ a: x, 'b-c': y }) -> %{a: x, "b-c": y}
  defp obj({:obj, pairs}, ctx) do
    inner = Enum.map_join(pairs, ", ", fn {k, v} -> obj_key(k) <> " " <> ex(v, ctx) end)
    "%{" <> inner <> "}"
  end

  defp obj(_, _),
    do:
      throw(
        {:unsupported,
         "classMap/styleMap take an inline object literal — variable or call arguments are outside the subset"}
      )

  defp obj_key(k) do
    cond do
      Regex.match?(~r/^[a-z_][A-Za-z0-9_]*$/, k) ->
        "#{k}:"

      String.contains?(k, ["{", "}", "\\", "\""]) ->
        throw({:unsupported, "object key #{inspect(k)}"})

      true ->
        ~s("#{k}":)
    end
  end

  # ---------------------------------------------------------------------------
  # JS scanning: template literals
  # ---------------------------------------------------------------------------

  # `rest` begins AFTER the opening backtick. Returns {parts, rest_after_closing_backtick}.
  defp tpl("`" <> rest, text, parts), do: {Enum.reverse(flush(text, parts)), rest}

  defp tpl("\\" <> <<c::utf8, rest::binary>>, text, parts) do
    ch = if c in [?`, ?$, ?\\], do: <<c::utf8>>, else: "\\" <> <<c::utf8>>
    tpl(rest, [text, ch], parts)
  end

  defp tpl("${" <> rest, text, parts) do
    {expr, rest} = braced(rest, 1, [])
    tpl(rest, [], [{:expr, String.trim(expr)} | flush(text, parts)])
  end

  defp tpl(<<c::utf8, rest::binary>>, text, parts), do: tpl(rest, [text, <<c::utf8>>], parts)
  defp tpl("", text, parts), do: {Enum.reverse(flush(text, parts)), ""}

  defp flush(text, parts) do
    case IO.iodata_to_binary(text) do
      "" -> parts
      t -> [{:text, t} | parts]
    end
  end

  # Reads to the matching `}` (rest begins after the opener, `depth` open braces).
  # Returns {inner, rest_after_closer}. Strings and nested templates are skipped.
  defp braced("}" <> rest, 1, acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), rest}
  defp braced("}" <> rest, d, acc), do: braced(rest, d - 1, ["}" | acc])
  defp braced("{" <> rest, d, acc), do: braced(rest, d + 1, ["{" | acc])

  defp braced(<<q, rest::binary>>, d, acc) when q in [?", ?'] do
    {s, rest} = raw_string(rest, q, [<<q>>])
    braced(rest, d, [s | acc])
  end

  defp braced("`" <> rest, d, acc) do
    {s, rest} = raw_tpl(rest, ["`"])
    braced(rest, d, [s | acc])
  end

  defp braced(<<c::utf8, rest::binary>>, d, acc), do: braced(rest, d, [<<c::utf8>> | acc])
  defp braced("", _d, acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), ""}

  defp raw_string("\\" <> <<c::utf8, rest::binary>>, q, acc),
    do: raw_string(rest, q, [<<c::utf8>>, "\\" | acc])

  defp raw_string(<<q, rest::binary>>, q, acc),
    do: {IO.iodata_to_binary(Enum.reverse([<<q>> | acc])), rest}

  defp raw_string(<<c::utf8, rest::binary>>, q, acc), do: raw_string(rest, q, [<<c::utf8>> | acc])
  defp raw_string("", _q, acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), ""}

  defp raw_tpl("\\" <> <<c::utf8, rest::binary>>, acc),
    do: raw_tpl(rest, [<<c::utf8>>, "\\" | acc])

  defp raw_tpl("`" <> rest, acc), do: {IO.iodata_to_binary(Enum.reverse(["`" | acc])), rest}

  defp raw_tpl("${" <> rest, acc) do
    {inner, rest} = braced(rest, 1, [])
    raw_tpl(rest, ["}", inner, "${" | acc])
  end

  defp raw_tpl(<<c::utf8, rest::binary>>, acc), do: raw_tpl(rest, [<<c::utf8>> | acc])
  defp raw_tpl("", acc), do: {IO.iodata_to_binary(Enum.reverse(acc)), ""}

  # ---------------------------------------------------------------------------
  # JS expression tokenizer + parser
  # ---------------------------------------------------------------------------

  defp parse_expr(js) do
    toks = tokenize(js, [])
    {ast, rest} = p_ternary(toks)

    if rest != [] do
      throw({:unsupported, "unsupported expression syntax near #{describe(hd(rest))}"})
    end

    {:ok, ast}
  catch
    {:unsupported, r} -> {:error, r}
  end

  defp describe({:p, p}), do: "`#{p}`"
  defp describe({:id, n}), do: "`#{n}`"
  defp describe({:num, n}), do: "`#{n}`"
  defp describe(_), do: "a literal"

  @ops3 ["===", "!==", "..."]
  @ops2 ["==", "!=", "<=", ">=", "&&", "||", "??", "?.", "=>"]
  @ops1 ["(", ")", "[", "]", "{", "}", ",", ".", "?", ":", "!", "+", "-", "*", "/", "%", "<", ">"]

  defp tokenize("", acc), do: Enum.reverse(acc)

  defp tokenize(<<c, rest::binary>>, acc) when c in [?\s, ?\t, ?\n, ?\r], do: tokenize(rest, acc)

  defp tokenize("html`" <> rest, acc) do
    {parts, rest} = tpl(rest, [], [])
    tokenize(rest, [{:html, parts} | acc])
  end

  defp tokenize("`" <> rest, acc) do
    {parts, rest} = tpl(rest, [], [])
    tokenize(rest, [{:tpl, parts} | acc])
  end

  defp tokenize(<<q, rest::binary>>, acc) when q in [?", ?'] do
    {raw, rest} = raw_string(rest, q, [])
    s = binary_part(raw, 0, max(byte_size(raw) - 1, 0))
    tokenize(rest, [{:str, unescape(s)} | acc])
  end

  defp tokenize(src, acc) do
    cond do
      m = Regex.run(~r/^\d+(\.\d+)?/, src) ->
        tokenize(drop(src, hd(m)), [{:num, hd(m)} | acc])

      m = Regex.run(~r/^[A-Za-z_$][\w$]*/, src) ->
        tokenize(drop(src, hd(m)), [{:id, hd(m)} | acc])

      op = Enum.find(@ops3, &String.starts_with?(src, &1)) ->
        tokenize(drop(src, op), [{:p, op} | acc])

      op = Enum.find(@ops2, &String.starts_with?(src, &1)) ->
        tokenize(drop(src, op), [{:p, op} | acc])

      op = Enum.find(@ops1, &String.starts_with?(src, &1)) ->
        tokenize(drop(src, op), [{:p, op} | acc])

      true ->
        <<c::utf8, _::binary>> = src

        throw(
          {:unsupported, "unsupported token `#{<<c::utf8>>}` (assignment/bitwise/other operator)"}
        )
    end
  end

  defp unescape(s), do: s |> String.replace("\\n", "\n") |> String.replace(~r/\\(.)/, "\\1")

  @prec %{
    "??" => 1,
    "||" => 1,
    "&&" => 2,
    "==" => 3,
    "!=" => 3,
    "===" => 3,
    "!==" => 3,
    "<" => 4,
    "<=" => 4,
    ">" => 4,
    ">=" => 4,
    "+" => 5,
    "-" => 5,
    "*" => 6,
    "/" => 6,
    "%" => 6
  }

  defp p_ternary(toks) do
    {c, rest} = p_bin(toks, 1)

    case rest do
      [{:p, "?"} | r] ->
        {a, r} = p_ternary(r)
        r = expect(r, ":")
        {b, r} = p_ternary(r)
        {{:ternary, c, a, b}, r}

      _ ->
        {c, rest}
    end
  end

  defp p_bin(toks, min) do
    {lhs, rest} = p_unary(toks)
    bin_loop(lhs, rest, min)
  end

  defp bin_loop(lhs, [{:p, op} | rest] = toks, min) do
    case @prec[op] do
      prec when is_integer(prec) and prec >= min ->
        {rhs, rest2} = p_bin(rest, prec + 1)
        bin_loop({:bin, op, lhs, rhs}, rest2, min)

      _ ->
        {lhs, toks}
    end
  end

  defp bin_loop(lhs, toks, _min), do: {lhs, toks}

  defp p_unary([{:p, "!"} | r]) do
    {x, r} = p_unary(r)
    {{:not, x}, r}
  end

  defp p_unary([{:p, "-"} | r]) do
    {x, r} = p_unary(r)
    {{:neg, x}, r}
  end

  defp p_unary(toks) do
    {e, rest} = p_primary(toks)
    post_loop(e, rest)
  end

  defp post_loop(e, [{:p, "."}, {:id, name} | rest]), do: post_loop({:member, e, name}, rest)
  defp post_loop(_e, [{:p, "?."} | _]), do: throw({:unsupported, "optional chaining `?.`"})

  defp post_loop(e, [{:p, "["} | rest]) do
    {ix, r} = p_ternary(rest)
    post_loop({:index, e, ix}, expect(r, "]"))
  end

  defp post_loop(e, [{:p, "("} | rest]) do
    {args, r} = p_args(rest, [])
    post_loop({:call, e, args}, r)
  end

  defp post_loop(e, rest), do: {e, rest}

  defp p_args([{:p, ")"} | r], acc), do: {Enum.reverse(acc), r}
  defp p_args([{:p, "..."} | _], _), do: throw({:unsupported, "spread argument"})

  defp p_args(toks, acc) do
    {a, r} = p_ternary(toks)

    case r do
      [{:p, ","} | r2] -> p_args(r2, [a | acc])
      [{:p, ")"} | r2] -> {Enum.reverse([a | acc]), r2}
      _ -> throw({:unsupported, "malformed call arguments"})
    end
  end

  defp p_primary([{:num, s} | r]), do: {{:num, s}, r}
  defp p_primary([{:str, s} | r]), do: {{:str, s}, r}
  defp p_primary([{:html, parts} | r]), do: {{:html, parts}, r}
  defp p_primary([{:tpl, parts} | r]), do: {{:tpl, parts}, r}
  defp p_primary([{:id, "true"} | r]), do: {{:bool, true}, r}
  defp p_primary([{:id, "false"} | r]), do: {{:bool, false}, r}
  defp p_primary([{:id, "null"} | r]), do: {{:null}, r}
  defp p_primary([{:id, "undefined"} | r]), do: {{:undef}, r}
  defp p_primary([{:id, "this"} | r]), do: {{:this}, r}

  defp p_primary([{:id, n}, {:p, "=>"} | r]) do
    {body, r} = arrow_body(r)
    {{:arrow, [n], body}, r}
  end

  defp p_primary([{:id, n} | r]), do: {{:ident, n}, r}

  defp p_primary([{:p, "("} | r]) do
    case arrow_params(r, []) do
      {:ok, params, after_arrow} ->
        {body, rest} = arrow_body(after_arrow)
        {{:arrow, params, body}, rest}

      :no ->
        {e, r2} = p_ternary(r)
        {e, expect(r2, ")")}
    end
  end

  defp p_primary([{:p, "["} | r]), do: p_array(r, [])
  defp p_primary([{:p, "{"} | r]), do: p_object(r, [])

  defp p_primary([tok | _]),
    do: throw({:unsupported, "unsupported expression syntax near #{describe(tok)}"})

  defp p_primary([]), do: throw({:unsupported, "empty expression"})

  defp arrow_params([{:p, ")"}, {:p, "=>"} | rest], acc), do: {:ok, Enum.reverse(acc), rest}

  defp arrow_params([{:id, n}, {:p, ")"}, {:p, "=>"} | rest], acc),
    do: {:ok, Enum.reverse([n | acc]), rest}

  defp arrow_params([{:id, n}, {:p, ","} | rest], acc), do: arrow_params(rest, [n | acc])
  defp arrow_params(_, _), do: :no

  defp arrow_body([{:p, "{"} | _]), do: throw({:unsupported, "block-bodied arrow function"})
  defp arrow_body(toks), do: p_ternary(toks)

  defp p_array([{:p, "]"} | r], acc), do: {{:arr, Enum.reverse(acc)}, r}

  defp p_array(toks, acc) do
    {e, r} = p_ternary(toks)

    case r do
      [{:p, ","} | r2] -> p_array(r2, [e | acc])
      [{:p, "]"} | r2] -> {{:arr, Enum.reverse([e | acc])}, r2}
      _ -> throw({:unsupported, "malformed array literal"})
    end
  end

  defp p_object([{:p, "}"} | r], acc), do: {{:obj, Enum.reverse(acc)}, r}

  defp p_object([{kind, k}, {:p, ":"} | rest], acc) when kind in [:id, :str] do
    {v, r} = p_ternary(rest)

    case r do
      [{:p, ","} | r2] -> p_object(r2, [{k, v} | acc])
      [{:p, "}"} | r2] -> {{:obj, Enum.reverse([{k, v} | acc])}, r2}
      _ -> throw({:unsupported, "malformed object literal"})
    end
  end

  defp p_object(_, _),
    do: throw({:unsupported, "object literal with shorthand/spread/computed keys"})

  defp expect([{:p, p} | r], p), do: r
  defp expect(_, p), do: throw({:unsupported, "expected `#{p}` in expression"})

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  # unsafeHTML reaches conversion only through child / attribute positions, and
  # ex/2 cannot thread todos — so the XSS-sink warning is recorded where ctx
  # flows (PR #44 review, thread 4545471200).
  defp maybe_warn_unsafe_html(ast, ctx, snippet) do
    if has_unsafe_html?(ast) do
      add_todo(
        ctx,
        snippet,
        "unsafeHTML → unsafe_html (XSS sink — bind only trusted, sanitized markup)"
      )
    else
      ctx
    end
  end

  defp has_unsafe_html?({:call, {:ident, "unsafeHTML"}, _}), do: true

  defp has_unsafe_html?(t) when is_tuple(t),
    do: t |> Tuple.to_list() |> Enum.any?(&has_unsafe_html?/1)

  defp has_unsafe_html?(l) when is_list(l), do: Enum.any?(l, &has_unsafe_html?/1)
  defp has_unsafe_html?(_), do: false

  defp add_todo(ctx, js, reason) do
    snippet =
      js
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
      |> String.replace("\"\"\"", "'''")
      |> then(fn s -> if String.length(s) > 90, do: String.slice(s, 0, 90) <> "…", else: s end)

    %{ctx | todos: [%{snippet: snippet, reason: reason} | ctx.todos]}
  end

  # trim + dedent (Lit templates are indented inside the class body)
  defp tidy(markup) do
    lines = markup |> String.split("\n") |> Enum.map(&String.trim_trailing/1)

    {first, rest} =
      case lines do
        [f | r] -> {String.trim_leading(f), r}
        [] -> {"", []}
      end

    indent =
      rest
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn l -> byte_size(l) - byte_size(String.trim_leading(l)) end)
      |> Enum.min(fn -> 0 end)

    rest =
      Enum.map(rest, fn l ->
        if l == "", do: "", else: binary_part(l, indent, byte_size(l) - indent)
      end)

    [first | rest]
    |> Enum.join("\n")
    |> String.trim()
  end
end
