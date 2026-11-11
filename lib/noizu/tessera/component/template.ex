defmodule Noizu.Tessera.Component.Template do
  @moduledoc """
  SPIKE (`spike/elixir-to-lit`): `~TSR` element-template parsing and lit-html
  emission (docs/notes/spike-elixir-to-lit.md §template-parser).

  Two lexers produce the SAME token stream, and one tree-ifier builds the
  tree (`parse/1`):

    * **Hologram path** — when Hologram 0.10.1 is compiled into the path, the
      markup is tokenized by `Hologram.Template.Parser.parse_markup/1` (a
      public, documented, pure function on an `@moduledoc false` module —
      de-facto internal-but-callable; see the notes for the stability
      discussion). Its flat parsed-tag stream is converted 1:1 into the
      subset token stream below.
    * **Minimal path** — a hand-rolled lexer for exactly the subset (plain
      elements, static/interpolated attributes, `{expr}`, `{%if}/{%else}/{/if}`,
      `{%for pat <- expr}/{/for}`, `$event={:action[, params]}`), used when
      Hologram is absent so spec-only consumers (npm/UMD packaging without a
      Hologram host) still compile.

  Token stream (the shared subset):

      {:start_tag, tag, attrs} | {:self_closing_tag, tag, attrs} | {:end_tag, tag}
      {:text, s} | {:expr, ast}
      {:if_start, ast} | :else | :if_end
      {:for_start, var, coll_ast} | :for_end

      attrs :: [{name, {:static, s} | {:parts, [{:text, s} | {:expr, expr_string}]}}
                | {:"$event", dom_event, binding_src}
                | {:"$bool", name, {:static, s} | {:parts, [...]}}]

  `?attr={expr}` (Lit boolean attribute binding) shares the `{:"$bool", …}`
  form across both lexers; `<slot>…</slot>` (non-void, fallback content) is
  supported under both lexers — the Hologram path renames slot tags through
  a reserved placeholder because Hologram's parser treats `<slot>` as void.

  Tree shape:

      {:element, tag, attrs, children} | {:text, s} | {:expr, ast}
      {:if, ast, children, else_children} | {:for, var, coll_ast, children}
      {:fragment, children}

  `to_lit_render/2` emits a Lit `render()` body as nested `html` template
  literals.
  """

  alias Noizu.Tessera.Component.Expr

  @hologram_parser Hologram.Template.Parser

  # Module attributes cannot appear in call position; route through a
  # resolved module name instead (Hologram may not be loaded at all).
  defp hologram_module, do: @hologram_parser

  # -- parse -----------------------------------------------------------------

  @doc """
  Parse markup into the subset tree. Uses Hologram's template parser when
  compiled in, otherwise the minimal lexer. Returns `{:ok, tree}` or
  `{:error, message}` (message names the construct).
  """
  @spec parse(String.t()) :: {:ok, term()} | {:error, String.t()}
  def parse(markup) when is_binary(markup) do
    with {:ok, tokens} <- lex(markup) do
      treeify(tokens, [], [])
    end
  end

  @doc "Which lexer `parse/1` uses right now."
  @spec lexer() :: :hologram | :minimal
  def lexer do
    if hologram_available?(), do: :hologram, else: :minimal
  end

  defp hologram_available? do
    mod = hologram_module()
    match?({:module, ^mod}, Code.ensure_loaded(mod)) and function_exported?(mod, :parse_markup, 1)
  end

  defp lex(markup) do
    if hologram_available?() do
      hologram_lex(markup)
    else
      minimal_lex(markup)
    end
  end

  # -- hologram lexer ----------------------------------------------------------

  defp hologram_lex(markup) do
    mod = hologram_module()

    # Hologram's parser raises an opaque internals error on directives it does
    # not know ({%unless ...}) — reject them by name before handing off.
    case unknown_directive(markup) do
      nil ->
        if Regex.match?(~r/<\/?tsrslot[\s>\/]/, markup) do
          {:error,
           "<tsrslot> is a reserved tessera tag name (the internal slot placeholder) — use <slot>"}
        else
          hologram_lex_with(mod, slot_prepass(markup))
        end

      dir ->
        {:error,
         "{%#{dir}} (or {/#{dir}}) is outside the tessera element template subset — " <>
           "supported directives: {%if}/{%else}/{/if}, {%for}/{/for}"}
    end
  end

  defp hologram_lex_with(mod, markup) do
    try do
      markup
      |> mod.parse_markup()
      |> Enum.reduce_while([], fn tag, acc ->
        case holo_token(tag) do
          {:ok, token} -> {:cont, [token | acc]}
          :skip -> {:cont, acc}
          {:error, msg} -> {:halt, {:error, msg}}
        end
      end)
      |> case do
        {:error, msg} -> {:error, msg}
        tokens -> {:ok, Enum.reverse(tokens)}
      end
    rescue
      e -> {:error, "hologram template parser: " <> Exception.message(e)}
    end
  end

  @directives ~w(if else for raw)

  defp unknown_directive(markup) do
    ~r/{(?:%|\/)([a-z_]+)/
    |> Regex.scan(markup)
    |> Enum.find_value(fn [_, name] -> if name in @directives, do: nil, else: name end)
  end

  defp holo_token({:start_tag, {tag, attrs}}) do
    tag = unmap_slot_tag(tag)
    component_guard(tag, {:start_tag, tag, holo_attrs(attrs)})
  end

  defp holo_token({:self_closing_tag, {tag, attrs}}) do
    tag = unmap_slot_tag(tag)
    component_guard(tag, {:self_closing_tag, tag, holo_attrs(attrs)})
  end

  defp holo_token({:end_tag, tag}), do: {:ok, {:end_tag, unmap_slot_tag(tag)}}
  defp holo_token({:text, text}), do: {:ok, {:text, text}}

  defp holo_token({:expression, expr}) do
    case expr_ast(strip_braces(expr)) do
      {:ok, ast} -> {:ok, {:expr, ast}}
      {:error, msg} -> {:error, msg}
    end
  end

  defp holo_token({:block_start, {"if", expr}}) do
    case expr_ast(strip_braces(expr)) do
      {:ok, ast} -> {:ok, {:if_start, ast}}
      {:error, msg} -> {:error, msg}
    end
  end

  defp holo_token({:block_start, "else"}), do: {:ok, :else}
  defp holo_token({:block_end, "if"}), do: {:ok, :if_end}

  defp holo_token({:block_start, {"for", expr}}) do
    case for_pattern(strip_braces(expr)) do
      {:ok, {var, coll}} -> {:ok, {:for_start, var, coll}}
      {:error, msg} -> {:error, msg}
    end
  end

  defp holo_token({:block_end, "for"}), do: {:ok, :for_end}

  defp holo_token({:block_start, "raw"}),
    do: {:error, "{%raw} blocks are outside the tessera element template subset"}

  defp holo_token({:block_end, "raw"}), do: :skip

  defp holo_token({:doctype, _}),
    do: {:error, "doctype is outside the tessera element template subset"}

  defp holo_token(:public_comment_start),
    do: {:error, "HTML comments are outside the tessera element template subset"}

  defp holo_token(:public_comment_end), do: :skip

  defp holo_token(other),
    do:
      {:error,
       "#{inspect(elem(other, 0))} template construct is outside the tessera element subset"}

  defp component_guard(tag, token) do
    if component_tag?(tag) do
      {:error,
       "component tag <#{tag}> is outside the tessera element template subset — " <>
         "the element template renders plain DOM; use the `behaviors.add` escape hatch for JS"}
    else
      {:ok, token}
    end
  end

  # Hologram attributes: {name, [{:text, s} | {:expression, s}]} — expression
  # parts keep their braces; strip them for the shared expr-string parts.
  defp holo_attrs(attrs) do
    Enum.map(attrs, fn
      {"$" <> event, parts} ->
        case parts do
          [{:expression, expr}] -> {:"$event", event, strip_braces(expr)}
          [{:text, action}] -> {:"$event", event, String.trim(action)}
          mixed -> {:"$event", event, Enum.map_join(mixed, "", &elem(&1, 1))}
        end

      {"?" <> name, parts} ->
        {:"$bool", name, bool_value(parts)}

      {name, [{:text, s}]} ->
        {name, {:static, s}}

      {name, [{:expression, expr}]} ->
        {name, {:parts, [{:expr, strip_braces(expr)}]}}

      {name, parts} when is_list(parts) ->
        {name, {:parts, Enum.map(parts, &holo_part/1)}}
    end)
  end

  # Boolean-attribute values normalize to the SAME shapes the minimal lexer
  # produces: bare presence → {:static, ""}, quoted text → {:static, s},
  # a single {expr} → {:parts, [{:expr, src}]}.
  defp bool_value([]), do: {:static, ""}
  defp bool_value([{:text, s}]), do: {:static, s}
  defp bool_value([{:expression, expr}]), do: {:parts, [{:expr, strip_braces(expr)}]}
  defp bool_value(parts) when is_list(parts), do: {:parts, Enum.map(parts, &holo_part/1)}

  defp holo_part({:text, s}), do: {:text, s}
  defp holo_part({:expression, s}), do: {:expr, strip_braces(s)}

  # -- slot pre-pass -----------------------------------------------------------
  #
  # Hologram's parser treats <slot> as a VOID element (Helpers.void_element?/1
  # lists "slot" alongside br/img), so `<slot></slot>` and `<slot>fallback</slot>`
  # arrive as a self-closing tag plus an orphan end tag. HTML's <slot> is NOT
  # void — fallback content is valid and lit-html renders it. Rename slot tags
  # to a reserved non-void placeholder before parse_markup and map them back in
  # holo_token/1 (unmap_slot_tag/1). The minimal lexer has no void list, so it
  # needs no pre-pass — both lexers emit the same start/end tag tokens.
  #
  # The scanner rewrites ONLY the tag-name position right after `<` / `</`;
  # quoted attribute values and {expr} interpolations pass through byte-for-byte,
  # so a literal "<slot>" inside a value or expression is never touched.

  @slot_placeholder "tsrslot"

  defp unmap_slot_tag(@slot_placeholder), do: "slot"
  defp unmap_slot_tag(tag), do: tag

  defp slot_prepass(markup), do: slot_text(markup, "")

  defp slot_text("", acc), do: acc

  defp slot_text("<" <> rest, acc) do
    {slash, rest1} =
      case rest do
        "/" <> r -> {"/", r}
        _ -> {"", rest}
      end

    {name, remaining} = take_name(rest1, "")
    renamed = if name == "slot", do: @slot_placeholder, else: name
    slot_tag_body(remaining, acc <> "<" <> slash <> renamed)
  end

  defp slot_text(<<c::utf8, rest::binary>>, acc), do: slot_text(rest, acc <> <<c::utf8>>)

  defp slot_tag_body("", acc), do: acc
  defp slot_tag_body(">" <> rest, acc), do: slot_text(rest, acc <> ">")

  defp slot_tag_body(<<q::utf8, rest::binary>>, acc) when q in [?", ?'] do
    {quoted, remaining} = slot_quoted(rest, q, "")
    slot_tag_body(remaining, acc <> <<q::utf8>> <> quoted <> <<q::utf8>>)
  end

  defp slot_tag_body("{" <> rest, acc) do
    {expr, remaining} = slot_braces(rest, 1, "")
    slot_tag_body(remaining, acc <> "{" <> expr <> "}")
  end

  defp slot_tag_body(<<c::utf8, rest::binary>>, acc),
    do: slot_tag_body(rest, acc <> <<c::utf8>>)

  defp slot_quoted("", _q, acc), do: {acc, ""}

  defp slot_quoted("\\" <> <<c::utf8, rest::binary>>, q, acc),
    do: slot_quoted(rest, q, acc <> "\\" <> <<c::utf8>>)

  defp slot_quoted(<<q::utf8, rest::binary>>, q, acc), do: {acc, rest}

  defp slot_quoted(<<c::utf8, rest::binary>>, q, acc),
    do: slot_quoted(rest, q, acc <> <<c::utf8>>)

  defp slot_braces("", _depth, acc), do: {acc, ""}
  defp slot_braces("}" <> rest, 1, acc), do: {acc, rest}
  defp slot_braces("}" <> rest, depth, acc), do: slot_braces(rest, depth - 1, acc <> "}")
  defp slot_braces("{" <> rest, depth, acc), do: slot_braces(rest, depth + 1, acc <> "{")

  defp slot_braces(<<q::utf8, rest::binary>>, depth, acc) when q in [?", ?'] do
    {quoted, remaining} = slot_quoted(rest, q, "")
    slot_braces(remaining, depth, acc <> <<q::utf8>> <> quoted <> <<q::utf8>>)
  end

  defp slot_braces(<<c::utf8, rest::binary>>, depth, acc),
    do: slot_braces(rest, depth, acc <> <<c::utf8>>)

  defp strip_braces(expr) do
    expr = String.trim(expr)

    case {String.starts_with?(expr, "{"), String.ends_with?(expr, "}")} do
      {true, true} when byte_size(expr) > 1 ->
        expr |> String.slice(1..-2//1) |> String.trim()

      _ ->
        expr
    end
  end

  defp expr_ast(expr_str) do
    case Code.string_to_quoted(expr_str) do
      {:ok, ast} ->
        {:ok, ast}

      {:error, {line, _, msg}} ->
        {:error, "invalid expression `#{expr_str}` (line #{line}): #{msg}"}
    end
  end

  defp for_pattern(expr_str) do
    case Code.string_to_quoted(expr_str) do
      {:ok, {:<-, _, [{var, _, nil}, coll]}} when is_atom(var) ->
        {:ok, {var, coll}}

      _ ->
        {:error,
         "for pattern `#{expr_str}` is outside the tessera element subset — " <>
           "use a single variable: {%for item <- @items}"}
    end
  end

  # -- minimal lexer ------------------------------------------------------------

  @doc """
  Minimal lexer for exactly the subset (used when Hologram is not loaded).
  """
  @spec minimal_lex(String.t()) :: {:ok, list()} | {:error, String.t()}
  def minimal_lex(markup) do
    min_tokens(String.trim(markup), [])
  end

  defp min_tokens("", acc), do: {:ok, Enum.reverse(acc)}

  # blocks
  defp min_tokens("{%if" <> rest, acc) do
    case split_expr(rest, "", 0) do
      {:ok, expr, remaining} ->
        case expr_ast(String.trim(expr)) do
          {:ok, ast} -> min_tokens(remaining, [{:if_start, ast} | acc])
          {:error, msg} -> {:error, msg}
        end

      :error ->
        {:error, "unclosed {%if} block"}
    end
  end

  defp min_tokens("{%else}" <> rest, acc), do: min_tokens(rest, [:else | acc])
  defp min_tokens("{/if}" <> rest, acc), do: min_tokens(rest, [:if_end | acc])

  defp min_tokens("{%for" <> rest, acc) do
    case split_expr(rest, "", 0) do
      {:ok, expr, remaining} ->
        case for_pattern(String.trim(expr)) do
          {:ok, {var, coll}} -> min_tokens(remaining, [{:for_start, var, coll} | acc])
          {:error, msg} -> {:error, msg}
        end

      :error ->
        {:error, "unclosed {%for} block"}
    end
  end

  defp min_tokens("{/for}" <> rest, acc), do: min_tokens(rest, [:for_end | acc])

  # escapes
  defp min_tokens("\\{" <> rest, acc), do: min_text("{", rest, acc)
  defp min_tokens("\\}" <> rest, acc), do: min_text("}", rest, acc)

  # closing tag
  defp min_tokens("</" <> rest, acc) do
    {name, remaining} = take_name(rest, "")

    if name == "" do
      {:error, "invalid closing tag: </#{String.slice(rest, 0, 10)}"}
    else
      case String.trim_leading(remaining) do
        ">" <> after_close -> min_tokens(after_close, [{:end_tag, name} | acc])
        _ -> {:error, "malformed closing tag </#{name}"}
      end
    end
  end

  # expression
  defp min_tokens("{" <> rest, acc) do
    case split_expr(rest, "", 0) do
      {:ok, expr, remaining} ->
        case expr_ast(String.trim(expr)) do
          {:ok, ast} -> min_tokens(remaining, [{:expr, ast} | acc])
          {:error, msg} -> {:error, msg}
        end

      :error ->
        {:error, "unclosed {expression}"}
    end
  end

  # tags
  defp min_tokens("<" <> rest, acc) do
    {name, remaining} = take_name(rest, "")

    if name == "" or String.starts_with?(name, "-") or String.starts_with?(name, "?") do
      {:error, "invalid tag start: <#{String.slice(rest, 0, 10)}"}
    else
      if name == "tsrslot" do
        {:error,
         "<tsrslot> is a reserved tessera tag name (the internal slot placeholder) — use <slot>"}
      else
        if component_tag?(name) do
          {:error,
           "component tag <#{name}> is outside the tessera element template subset — " <>
             "the element template renders plain DOM; use the `behaviors.add` escape hatch for JS"}
        else
          case min_attrs(String.trim_leading(remaining), []) do
            {:ok, attrs, after_tag, self_closing} ->
              token =
                if self_closing,
                  do: {:self_closing_tag, name, attrs},
                  else: {:start_tag, name, attrs}

              min_tokens(after_tag, [token | acc])

            {:error, msg} ->
              {:error, msg}
          end
        end
      end
    end
  end

  # literal `<%` text
  defp min_tokens("<%" <> rest, acc), do: min_text("<%", rest, acc)

  # text run until the next special char
  defp min_tokens(markup, acc) do
    case Regex.run(~r/^[^<{\\]+/, markup) do
      [text] -> min_text(text, String.slice(markup, String.length(text)..-1//1), acc)
      nil -> {:error, "unexpected character in template: #{String.slice(markup, 0, 10)}"}
    end
  end

  defp min_text(text, rest, acc) do
    case acc do
      [{:text, prev} | acc_rest] -> min_tokens(rest, [{:text, prev <> text} | acc_rest])
      _ -> min_tokens(rest, [{:text, text} | acc])
    end
  end

  # split "expr}rest" honoring nested braces inside the expression
  defp split_expr("}" <> rest, expr, 0), do: {:ok, expr, rest}
  defp split_expr("{" <> rest, expr, depth), do: split_expr(rest, expr <> "{", depth + 1)

  defp split_expr("}" <> rest, expr, depth) when depth > 0,
    do: split_expr(rest, expr <> "}", depth - 1)

  defp split_expr(<<c::utf8, rest::binary>>, expr, depth),
    do: split_expr(rest, expr <> <<c::utf8>>, depth)

  defp split_expr("", _expr, _depth), do: :error

  defp take_name(<<c::utf8, rest::binary>>, acc)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c in [?-, ?_, ?$, ?., ??],
       do: take_name(rest, acc <> <<c::utf8>>)

  defp take_name(rest, acc), do: {acc, rest}

  defp min_attrs("/>" <> rest, attrs), do: {:ok, Enum.reverse(attrs), rest, true}
  defp min_attrs(">" <> rest, attrs), do: {:ok, Enum.reverse(attrs), rest, false}
  defp min_attrs(" " <> rest, attrs), do: min_attrs(rest, attrs)

  defp min_attrs(markup, attrs) do
    {name, rest} = take_name(markup, "")

    if name == "" do
      {:error, "invalid attribute: #{String.slice(markup, 0, 10)}"}
    else
      case rest do
        "=" <> more ->
          case min_attr_value(String.trim_leading(more)) do
            {:ok, value, remaining} ->
              min_attrs(String.trim_leading(remaining), [event_attr(name, value) | attrs])

            {:error, msg} ->
              {:error, msg}
          end

        _ ->
          # bare attribute (e.g. disabled, ?hidden) — boolean by presence
          min_attrs(rest, [event_attr(name, {:static, ""}) | attrs])
      end
    end
  end

  defp min_attr_value("\"" <> rest) do
    case String.split(rest, "\"", parts: 2) do
      [value, remaining] -> {:ok, attr_parts(value), remaining}
      _ -> {:error, "unterminated attribute value"}
    end
  end

  defp min_attr_value("{" <> rest) do
    case split_expr(rest, "", 0) do
      {:ok, expr, remaining} -> {:ok, {:parts, [{:expr, String.trim(expr)}]}, remaining}
      :error -> {:error, "unclosed attribute expression"}
    end
  end

  defp min_attr_value(other),
    do:
      {:error, "attribute value must be \"static\" or {expr}, got: #{String.slice(other, 0, 10)}"}

  # `$event={...}` bindings become the shared {:"$event", event, src} attr
  # shape (same as the Hologram lexer's holo_attrs), so attr_js handles both
  # lexers identically.
  defp event_attr("$" <> event, {:parts, [{:expr, src}]}), do: {:"$event", event, src}
  defp event_attr("$" <> event, {:static, s}), do: {:"$event", event, String.trim(s)}
  defp event_attr("?" <> name, value), do: {:"$bool", name, value}
  defp event_attr(name, value), do: {name, value}

  # "text {expr} more" mixed value → parts (expr kept as string for parity
  # with the Hologram lexer)
  defp attr_parts(value) do
    case min_tokens(value, []) do
      {:ok, tokens} -> {:parts, Enum.map(tokens, &attr_part/1)}
      _ -> {:static, value}
    end
  end

  defp attr_part({:text, s}), do: {:text, s}
  defp attr_part({:expr, ast}), do: {:expr, Macro.to_string(ast)}

  # -- tree-ification (shared) ---------------------------------------------------

  @doc """
  Tree-ify the shared token stream. Frames: `{:elem, {tag, attrs, children}}`,
  `{:if, {ast, then, else}}`, `{:else, {ast, then, else}}`,
  `{:for, {var, coll, children}}`. Top-level nodes accumulate in `top`.
  """
  @spec treeify(list(), list(), list()) :: {:ok, term()} | {:error, String.t()}
  def treeify([], [], top), do: {:ok, finish_root(Enum.reverse(top))}
  def treeify([], _stack, _top), do: {:error, "unclosed element(s) at end of template"}

  def treeify([{:start_tag, tag, attrs} | rest], stack, top) do
    treeify(rest, [{:elem, {tag, attrs, []}} | stack], top)
  end

  def treeify([{:self_closing_tag, tag, attrs} | rest], stack, top),
    do: push({:element, tag, attrs, []}, stack, rest, top)

  def treeify([{:end_tag, closing} | rest], [{:elem, {open, attrs, children}} | stack], top)
      when closing == open do
    push({:element, closing, attrs, Enum.reverse(children)}, stack, rest, top)
  end

  def treeify([{:end_tag, tag} | _], _stack, _top),
    do: {:error, "unexpected </#{tag}> — no matching open tag"}

  def treeify([{:text, text} | rest], stack, top) do
    if stack == [] and String.trim(text) == "" do
      treeify(rest, stack, top)
    else
      push({:text, text}, stack, rest, top)
    end
  end

  def treeify([{:expr, ast} | rest], stack, top), do: push({:expr, ast}, stack, rest, top)

  def treeify([{:if_start, ast} | rest], stack, top),
    do: treeify(rest, [{:if, {ast, [], []}} | stack], top)

  def treeify([:else | rest], [{:if, {ast, then_c, _}} | stack], top),
    do: treeify(rest, [{:else, {ast, then_c, []}} | stack], top)

  def treeify([:else | _], _stack, _top),
    do: {:error, "{%else} outside an {%if} block"}

  def treeify([:if_end | rest], [{_frame, {ast, then_c, else_c}} | stack], top),
    do: push({:if, ast, Enum.reverse(then_c), Enum.reverse(else_c)}, stack, rest, top)

  def treeify([:if_end | _], _stack, _top),
    do: {:error, "{/if} without a matching {%if}"}

  def treeify([{:for_start, var, coll} | rest], stack, top),
    do: treeify(rest, [{:for, {var, coll, []}} | stack], top)

  def treeify([:for_end | rest], [{:for, {var, coll, children}} | stack], top),
    do: push({:for, var, coll, Enum.reverse(children)}, stack, rest, top)

  defp push(node, [], rest, top), do: treeify(rest, [], [node | top])

  defp push(node, [{:elem, {tag, attrs, children}} | stack], rest, top),
    do: treeify(rest, [{:elem, {tag, attrs, [node | children]}} | stack], top)

  defp push(node, [{:if, {ast, then_c, else_c}} | stack], rest, top),
    do: treeify(rest, [{:if, {ast, [node | then_c], else_c}} | stack], top)

  defp push(node, [{:else, {ast, then_c, else_c}} | stack], rest, top),
    do: treeify(rest, [{:else, {ast, then_c, [node | else_c]}} | stack], top)

  defp push(node, [{:for, {var, coll, children}} | stack], rest, top),
    do: treeify(rest, [{:for, {var, coll, [node | children]}} | stack], top)

  defp finish_root([single]), do: single
  defp finish_root(many), do: {:fragment, many}

  # -- lit-html emission -------------------------------------------------------

  @doc """
  Emit the JavaScript expression for a Lit `render()` body (without the
  leading `return`). `ctx` is a `Noizu.Tessera.Component.Expr` context.
  """
  @spec to_lit_render(term(), Expr.t()) :: String.t()
  def to_lit_render(tree, %Expr{} = ctx), do: "html`#{node_js(tree, ctx)}`"

  defp node_js({:fragment, children}, ctx),
    do: Enum.map_join(children, " ", &node_js(&1, ctx))

  defp node_js({:element, tag, attrs, children}, ctx) do
    attr_js =
      attrs
      |> Enum.map_join(" ", &attr_js(&1, ctx))
      |> then(fn s -> if s == "", do: "", else: " " <> s end)

    children_js = Enum.map_join(children, "", &node_js(&1, ctx))
    "<#{tag}#{attr_js}>#{children_js}</#{tag}>"
  end

  defp node_js({:text, s}, _ctx), do: escape_lit_text(s)

  # Child position: a directive (class_map/style_map/if_defined) or the bare
  # `nothing` sentinel emits WITHOUT the __t wrapper — directives are valid
  # child expressions and `nothing` must reach lit-html untouched (__t would
  # pass it through anyway, but the unquoted form is the canonical one).
  defp node_js({:expr, ast}, ctx) do
    if directive_ast?(ast) do
      "${#{Expr.translate(ast, ctx)}}"
    else
      "${__t(#{Expr.translate(ast, ctx)})}"
    end
  end

  defp node_js({:if, ast, children, []}, ctx) do
    inner = Enum.map_join(children, "", &node_js(&1, ctx))
    "${(#{Expr.translate(ast, ctx)}) ? html`#{inner}` : html``}"
  end

  defp node_js({:if, ast, children, else_children}, ctx) do
    inner = Enum.map_join(children, "", &node_js(&1, ctx))
    else_inner = Enum.map_join(else_children, "", &node_js(&1, ctx))
    "${(#{Expr.translate(ast, ctx)}) ? html`#{inner}` : html`#{else_inner}`}"
  end

  defp node_js({:for, var, coll, children}, ctx) do
    # the loop var is pattern-bound inside the callback — body expressions
    # (interpolations AND attribute expressions) may reference it
    inner_ctx = %{ctx | vars: MapSet.put(ctx.vars, var)}
    inner = Enum.map_join(children, "", &node_js(&1, inner_ctx))
    "${(#{Expr.translate(coll, ctx)} ?? []).map((#{var}) => html`#{inner}`)}"
  end

  # attribute emission
  defp attr_js({:"$event", event, binding_src}, ctx) do
    case parse_binding(binding_src) do
      {:ok, ast} ->
        emit_event_binding(event, ast, ctx)

      :error ->
        raise CompileError,
          file: ctx.file,
          line: ctx.line || 0,
          description:
            "invalid $#{event} binding `#{binding_src}` — use $#{event}={:action} or " <>
              "$#{event}={:action, key: value}"
    end
  end

  # `?attr={expr}` — Lit boolean attribute binding: truthy → attribute present,
  # falsy → removed. No quotes and no __t wrapper (null must stay falsy).
  defp attr_js({:"$bool", name, {:parts, [{:expr, e}]}}, ctx) do
    ast = if is_binary(e), do: to_ast(e, ctx), else: e
    "?#{name}=${#{Expr.translate(ast, ctx)}}"
  end

  # Static `?attr` (bare or quoted text) → bare presence attribute.
  defp attr_js({:"$bool", name, {:static, _s}}, _ctx), do: name

  defp attr_js({:"$bool", name, {:parts, parts}}, ctx) do
    if Enum.all?(parts, &match?({:text, _}, &1)) do
      name
    else
      raise CompileError,
        file: ctx.file,
        line: ctx.line || 0,
        description:
          "tessera ?#{name} boolean attribute must bind a single {expr} (or be static) — " <>
            "mixed text/expression values are outside the lit-html boolean-binding subset"
    end
  end

  defp attr_js({name, {:static, s}}, _ctx) do
    ~s(#{name}="#{escape_attr(s)}")
  end

  # A single directive expression in attribute position (class={class_map(…)},
  # style={style_map(…)}, title={if_defined(…)}, title={nothing}) emits UNQUOTED
  # and without __t — lit-html directive part position. A quoted directive is
  # treated as a string; `nothing` unquoted removes the attribute.
  defp attr_js({name, {:parts, [{:expr, e}]}}, ctx) do
    ast = if is_binary(e), do: to_ast(e, ctx), else: e

    if directive_ast?(ast) do
      "#{name}=${#{Expr.translate(ast, ctx)}}"
    else
      "#{name}=\"${__t(#{Expr.translate(ast, ctx)})}\""
    end
  end

  defp attr_js({name, {:parts, parts}}, ctx) do
    inner =
      Enum.map_join(parts, "", fn
        {:text, s} ->
          escape_lit_text(s)

        {:expr, e} ->
          ast = if is_binary(e), do: to_ast(e, ctx), else: e
          "${__t(#{Expr.translate(ast, ctx)})}"
      end)

    "#{name}=\"#{inner}\""
  end

  # Binding sources arrive brace-stripped: ":increment" or ":increment, step: 1"
  # (Hologram expression form) or "increment" (Hologram string form). Accept
  # the bare atom, the bare-identifier string form, and the braced tuple.
  defp parse_binding(src) when is_binary(src) do
    src = String.trim(src)

    cond do
      Regex.match?(~r/^[a-z][a-zA-Z0-9_]*$/, src) ->
        {:ok, String.to_atom(src)}

      true ->
        case Code.string_to_quoted(src) do
          {:ok, ast} ->
            {:ok, ast}

          {:error, _} ->
            case Code.string_to_quoted("{#{src}}") do
              {:ok, ast} -> {:ok, ast}
              {:error, _} -> :error
            end
        end
    end
  end

  defp parse_binding(_), do: :error

  defp emit_event_binding(event, action, ctx) when is_atom(action) do
    validate_action!(action, ctx)
    "@#{event}=${(ev) => this.__tesseraRunAction(\"#{action}\", {}, ev)}"
  end

  defp emit_event_binding(event, {action, params}, ctx)
       when is_atom(action) and is_list(params) do
    validate_action!(action, ctx)

    params_js =
      "{" <>
        Enum.map_join(params, ", ", fn {k, v} ->
          "#{k}: #{Expr.translate(literal_only!(k, v, ctx), ctx)}"
        end) <> "}"

    "@#{event}=${(ev) => this.__tesseraRunAction(\"#{action}\", #{params_js}, ev)}"
  end

  defp emit_event_binding(event, other, ctx) do
    raise CompileError,
      file: ctx.file,
      line: ctx.line || 0,
      description:
        "invalid $#{event} binding #{Macro.to_string(other)} — use $#{event}={:action} or " <>
          "$#{event}={:action, key: value}"
  end

  defp literal_only!(k, v, ctx) do
    unless is_atom(k) and literal?(v) do
      raise CompileError,
        file: ctx.file,
        line: ctx.line || 0,
        description:
          "$event binding params must be compile-time literals — #{inspect(k)}: #{Macro.to_string(v)}"
    end

    v
  end

  defp literal?(v)
       when is_integer(v) or is_float(v) or is_binary(v) or is_boolean(v) or is_nil(v),
       do: true

  defp literal?(v) when is_list(v), do: Enum.all?(v, &literal?/1)

  defp literal?(v) when is_map(v),
    do: Enum.all?(v, fn {k, val} -> literal?(k) and literal?(val) end)

  defp literal?(_), do: false

  defp validate_action!(action, ctx) do
    unless MapSet.member?(ctx.actions, action) do
      raise CompileError,
        file: ctx.file,
        line: ctx.line || 0,
        description:
          "template binds unknown action #{inspect(action)} — declare " <>
            "`action #{inspect(action)}, fn state, params -> ... end` first"
    end
  end

  defp to_ast(expr, ctx) do
    case Code.string_to_quoted(expr) do
      {:ok, ast} ->
        ast

      {:error, {line, _, msg}} ->
        raise CompileError,
          file: ctx.file,
          line: line,
          description: "invalid template expression `#{expr}`: #{msg}"
    end
  end

  # Directive forms recognized in template expression position (lit-parity 1d).
  # `nothing` is the bare identifier (nil/atom context), never a call with args.
  defp directive_ast?({:class_map, _, [_]}), do: true
  defp directive_ast?({:style_map, _, [_]}), do: true
  defp directive_ast?({:if_defined, _, [_]}), do: true
  defp directive_ast?({:nothing, _, ctx}) when is_atom(ctx), do: true
  defp directive_ast?(_), do: false

  defp component_tag?(<<?_, _::binary>>), do: false

  defp component_tag?(<<first::utf8, _::binary>>), do: first >= ?A and first <= ?Z
  defp component_tag?(_), do: false

  defp escape_lit_text(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("`", "\\`")
    |> String.replace("${", "\\${")
  end

  defp escape_attr(s), do: String.replace(s, "\"", "&quot;")
end
