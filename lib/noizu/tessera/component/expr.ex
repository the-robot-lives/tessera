defmodule Noizu.Tessera.Component.Expr do
  @moduledoc """
  SPIKE (`spike/elixir-to-lit`): translator for the restricted Elixir subset
  accepted inside tessera element `action/2` bodies and `~TSR` template
  expressions (see docs/notes/spike-elixir-to-lit.md §subset).

  Everything in the subset compiles to a plain JavaScript expression string;
  anything outside it raises `CompileError` NAMING the rejected construct
  (that is the contract: no silent mistranslation).

  ## In the subset

    * literals — integers, floats, strings (with `#{}` interpolation),
      booleans, `nil`, lists, keyword lists, atom-keyed/string-keyed maps,
      map update `%{state | key: value}`
    * reads — `state.<key>` (declared keys only), `params.<key>`, bound
      pattern variables, `map.key` / `map[:key]` access
    * arithmetic `+ - * /` (+ `div/2`, `rem/2`, `trunc/1`), comparison
      `== != < <= > >=`, boolean `and or not`
    * `if cond do .. else .. end` (expression form)
    * `emit(event, detail)` for declared events (detail atom keys are
      camelCased at this boundary — the JS wire convention, CONTRACT.md §1)
    * the high-value Lit directives (lit-parity 1d): `class_map(map)`,
      `style_map(map)`, `if_defined(expr)` and the bare `nothing` sentinel —
      lowered to `classMap`/`styleMap`/`ifDefined`/`nothing` (the element
      codegen adds the matching `lit` / `lit/directives/*` imports)
    * allowlisted `Kernel` / `String` / `Enum` calls (see the maps below)
      plus `|>` into any of them
    * single-clause single-argument anonymous `fn` — only as the callback of
      `Enum.map` / `Enum.filter`

  ## Not in the subset (each rejected by name at compile time)

    `case`, `cond`, `with`, comprehensions in actions, multi-clause `fn`s,
    captures `&f/1`, module calls outside the allowlist, structs, tuples,
    charlists, `++`, blocks, `try`, `receive`.
  """

  alias Noizu.Tessera.Naming

  defstruct state_keys: MapSet.new(),
            attrs: %{},
            props: %{},
            events: MapSet.new(),
            actions: MapSet.new(),
            vars: MapSet.new(),
            callback?: false,
            camel_map_keys?: false,
            # Derivation subset (§5.3): `derived?` admits the base_action/3
            # down-call and `state = …` rebinding inside derived action bodies;
            # `inherited_actions` are the names a down-call may target.
            derived?: false,
            inherited_actions: MapSet.new(),
            module: nil,
            file: nil,
            line: nil

  @type t :: %__MODULE__{}

  # Kernel: name => {js, arity}; js is either a prefix function call
  # ("Math.abs") or a special form tagged below.
  @kernel_allowlist %{
    abs: {:prefix, "Math.abs", 1},
    round: {:prefix, "Math.round", 1},
    floor: {:prefix, "Math.floor", 1},
    ceil: {:prefix, "Math.ceil", 1},
    min: {:prefix, "Math.min", 2},
    max: {:prefix, "Math.max", 2},
    div: {:div, nil, 2},
    rem: {:rem, nil, 2},
    trunc: {:prefix, "Math.trunc", 1},
    to_string: {:to_string, nil, 1}
  }

  @string_allowlist %{
    upcase: {:method1, ".toUpperCase"},
    downcase: {:method1, ".toLowerCase"},
    trim: {:method1, ".trim"},
    capitalize: {:capitalize, nil},
    length: {:property, ".length"},
    split: {:split, :variadic},
    replace: {:replace, 3},
    starts_with?: {:method2, ".startsWith"},
    ends_with?: {:method2, ".endsWith"},
    contains?: {:method2, ".includes"},
    to_integer: {:parse_int, nil}
  }

  @enum_allowlist %{
    map: {:callback, 2},
    filter: {:callback, 2},
    count: {:count, :variadic},
    at: {:at, :variadic},
    join: {:join, :variadic},
    sum: {:sum, 1},
    reverse: {:reverse, 1},
    empty?: {:empty, 1}
  }

  @callback_funs [:map, :filter]

  # -- public API ------------------------------------------------------------

  @doc """
  Translate a restricted-subset Elixir AST into a JavaScript expression.
  Raises `CompileError` naming any construct outside the subset.
  """
  @spec translate(Macro.t(), t()) :: String.t()
  def translate(ast, %__MODULE__{} = ctx) do
    translate_expr(ast, ctx)
  end

  @doc """
  Validate + translate an action body: `fn state, params -> expr end`.
  Returns the JavaScript expression for the NEXT state. Emits compile errors
  for wrong arity, multiple clauses or non-subset bodies.
  """
  @spec translate_action(Macro.t(), t()) :: String.t()
  def translate_action({:fn, _, [{:->, _, [args, body]}]}, %__MODULE__{} = ctx)
      when length(args) == 2 do
    action_body(body, bind_action_params(args, ctx))
  end

  def translate_action({:fn, meta, [{:->, _, [args, _body]}]}, %__MODULE__{} = ctx)
      when length(args) != 2 do
    error!(
      ctx,
      meta,
      "tessera action fn must take exactly 2 arguments (state, params) — got #{length(args)}"
    )
  end

  def translate_action({:fn, meta, clauses}, %__MODULE__{} = ctx) when length(clauses) > 1 do
    error!(
      ctx,
      meta,
      "multi-clause fn is outside the tessera element subset — an action is one `fn state, params -> ... end`"
    )
  end

  def translate_action(other, %__MODULE__{} = ctx) do
    error!(
      ctx,
      elem(other, 1),
      "tessera action must be `fn state, params -> ... end`, got: #{snippet(other)}"
    )
  end

  # A multi-expression action body becomes a JS IIFE: every statement except
  # the last is evaluated for side effects (emit/2), the LAST expression is
  # the returned next state. A single expression stays inline (no IIFE).
  # Arrow IIFEs do not bind `this`, so `emit(this, ...)` still resolves to
  # the element inside the generated method.
  defp action_body({:__block__, _, exprs}, ctx) when length(exprs) > 1 do
    js = Enum.map(exprs, &translate_expr(&1, ctx))
    {stmts, [last]} = Enum.split(js, -1)

    "(() => { " <>
      Enum.map_join(stmts, "; ", & &1) <>
      "; return " <>
      last <>
      "; })()"
  end

  defp action_body(expr, ctx), do: translate_expr(expr, ctx)

  # -- expressions -----------------------------------------------------------

  # blocks
  defp translate_expr({:__block__, _, [expr]}, ctx), do: translate_expr(expr, ctx)

  defp translate_expr({:__block__, meta, _many}, ctx) do
    error!(
      ctx,
      meta,
      "block expressions (multiple statements) are outside the tessera element subset"
    )
  end

  # literals
  defp translate_expr(v, _ctx) when is_integer(v) or is_float(v), do: to_string(v)
  defp translate_expr(true, _ctx), do: "true"
  defp translate_expr(false, _ctx), do: "false"
  defp translate_expr(nil, _ctx), do: "null"

  defp translate_expr(s, _ctx) when is_binary(s), do: js_string(s)

  # string interpolation
  defp translate_expr({:<<>>, meta, parts}, ctx) when is_list(parts) do
    if Enum.all?(parts, &binary_part?/1) do
      inner =
        Enum.map_join(parts, "", fn
          binary when is_binary(binary) -> escape_template_literal(binary)
          {:"::", _, [inner, _modifier]} -> "${" <> translate_expr(inner, ctx) <> "}"
        end)

      "`" <> inner <> "`"
    else
      error!(ctx, meta, "string interpolation is only supported over the tessera element subset")
    end
  end

  # tuples are not in the subset (JS has no tuple literal)
  defp translate_expr({a, b}, ctx) when not is_atom(a),
    do:
      error!(
        ctx,
        nil,
        "tuple {#{snippet(a)}, #{snippet(b)}} is outside the tessera element subset"
      )

  # -- Lit directives (lit-parity 1d) ----------------------------------------
  # class_map/style_map take a MAP LITERAL (atom keys → JS object keys via
  # js_object_key; style_map keeps camelCase keys as written — the map-literal
  # clause does not camelCase). if_defined takes any subset expression. The
  # bare `nothing` identifier is the Lit sentinel (NOT nil — nil lowers to
  # null, which __t maps to undefined; nothing must pass through untouched).
  # These emit the directive NAME only; lit_codegen adds the imports.
  # Placed before the variables clause so bare `nothing` is not read as a var.
  defp translate_expr({:class_map, meta, [arg]}, ctx),
    do: "classMap(" <> directive_map!(arg, meta, ctx, "class_map") <> ")"

  defp translate_expr({:style_map, meta, [arg]}, ctx),
    do: "styleMap(" <> directive_map!(arg, meta, ctx, "style_map") <> ")"

  defp translate_expr({:if_defined, _meta, [arg]}, ctx),
    do: "ifDefined(" <> translate_expr(arg, ctx) <> ")"

  # live(expr) (lit-parity #67, BoE need #3): Lit's `live` directive — the
  # binding is checked against the LIVE DOM value, not the last rendered one,
  # so an input the user edited is still reset when state re-renders it.
  defp translate_expr({:live, _meta, [arg]}, ctx),
    do: "live(" <> translate_expr(arg, ctx) <> ")"

  # unsafe_html(expr) (lit-parity #71, BoE need #4): Lit `unsafeHTML` renders
  # the string as HTML WITHOUT escaping. The name is deliberately loud: only
  # bind trusted, sanitized markup — it is an XSS sink by design.
  defp translate_expr({:unsafe_html, _meta, [arg]}, ctx),
    do: "unsafeHTML(" <> translate_expr(arg, ctx) <> ")"

  # guard([deps], expr) (lit-parity #66, BoE need #4): Lit `guard` re-evaluates
  # `expr` only when a dependency changes (identity check), so an expensive
  # sub-template is skipped on unrelated re-renders.
  defp translate_expr({:guard, meta, [deps, body]}, ctx) do
    unless is_list(deps) do
      raise CompileError,
        file: ctx.file,
        line: meta[:line] || ctx.line || 0,
        description:
          "tessera guard/2 takes a dependency LIST literal first: guard([@a, @b], expr)"
    end

    "guard(" <> translate_expr(deps, ctx) <> ", () => " <> translate_expr(body, ctx) <> ")"
  end

  defp translate_expr({:nothing, _meta, atom_ctx}, _ctx) when is_atom(atom_ctx), do: "nothing"

  # variables
  defp translate_expr({name, _meta, var_ctx}, _ctx)
       when name in [:state, :params] and is_atom(var_ctx),
       do: Atom.to_string(name)

  defp translate_expr({name, _meta, var_ctx}, %__MODULE__{} = ctx) when is_atom(var_ctx) do
    if MapSet.member?(ctx.vars, name) do
      Atom.to_string(name)
    else
      error!(
        ctx,
        nil,
        "variable #{inspect(name)} is outside the tessera element subset — only `state`, " <>
          "`params` and pattern-bound names (#{inspect(Enum.sort(MapSet.to_list(ctx.vars)))}) may be referenced"
      )
    end
  end

  # module-attribute reads (template scope): @count / @display_name
  defp translate_expr({:@, _meta, [{name, _, _attr_ctx}]}, %__MODULE__{} = ctx) do
    component_read(name, ctx)
  end

  # map[key] access — must come before the general remote-call clause
  defp translate_expr({{:., _, [Access, :get]}, _meta, [map, key]}, ctx) do
    js_map = translate_expr(map, ctx)

    case key do
      k when is_atom(k) -> "#{js_map}.#{js_identifier(k)}"
      k when is_binary(k) -> "#{js_map}[#{js_string(k)}]"
      k -> "#{js_map}[#{translate_expr(k, ctx)}]"
    end
  end

  # quote-form field access: `state.count` written in an action arrives as
  # {{:., _, [left, right]}, _, []} (a zero-arg remote call); string-parsed
  # template expressions produce the bare {:., _, [left, right]} form below.
  defp translate_expr({{:., _, [left, right]}, _, []}, ctx) when is_atom(right),
    do: field_access(left, right, ctx)

  # remote calls: String.upcase(x), Enum.map(..), Kernel.abs(..). Module may
  # be a bare atom (string-parsed) or a single-segment __aliases__ node
  # (quote-parsed actions); multi-segment aliases are never in the subset.
  # NOTE: alias PATTERNS in case clauses never match atoms (Kernel -> is an
  # alias pattern, not the atom), so each branch compares in a guard.
  defp translate_expr({{:., _, [module, fun]}, meta, args}, ctx)
       when is_atom(fun) and is_list(args) do
    case resolve_module(module) do
      mod when mod == Kernel ->
        translate_kernel(fun, args, meta, ctx)

      mod when mod == String ->
        translate_string(fun, args, meta, ctx)

      mod when mod == Enum ->
        translate_enum(fun, args, meta, ctx)

      _ ->
        error!(
          ctx,
          meta,
          "#{Macro.to_string(module)}.#{fun} is not in the tessera element subset — only Kernel, " <>
            "String and Enum allowlisted functions"
        )
    end
  end

  # dot access: state.count / params.x / map.key
  defp translate_expr({:., _meta, [left, right]}, ctx) when is_atom(right),
    do: field_access(left, right, ctx)

  # map update %{state | key: value}
  defp translate_expr({:%{}, _meta, [{:|, _, [target, updates]}]}, ctx) do
    js_target = translate_expr(target, ctx)
    pairs = Enum.map_join(updates, ", ", &translate_kv(&1, ctx))
    "({ ...#{js_target}, #{pairs} })"
  end

  # map literal
  defp translate_expr({:%{}, _meta, pairs}, ctx) do
    "{" <> Enum.map_join(pairs || [], ", ", &translate_kv(&1, ctx)) <> "}"
  end

  # struct literal — explicitly rejected by name
  defp translate_expr({:%, meta, [module, _]}, ctx) do
    error!(
      ctx,
      meta,
      "struct %#{inspect(module)}{} is outside the tessera element subset " <>
        "(state is a plain map of declared keys)"
    )
  end

  # list literal
  defp translate_expr(list, ctx) when is_list(list) do
    "[" <> Enum.map_join(list, ", ", &translate_expr(&1, ctx)) <> "]"
  end

  # 2-tuples are keyword-pair entries ([a: 1] elements) — object sugar
  defp translate_expr({a, b}, ctx), do: translate_kv({a, b}, ctx)

  # bare tuples of other arities — rejected
  defp translate_expr({:{}, meta, _args}, ctx) do
    error!(ctx, meta, "tuples are outside the tessera element subset")
  end

  # anonymous fn (callback position only)
  defp translate_expr({:fn, meta, [{:->, _, [[{arg, _, _cb_ctx}], body]}]}, %__MODULE__{} = ctx) do
    if ctx.callback? do
      inner = translate_expr(body, %{ctx | callback?: false, vars: MapSet.put(ctx.vars, arg)})
      "(#{arg}) => #{inner}"
    else
      error!(
        ctx,
        meta,
        "anonymous fn is only allowed as the callback of #{inspect(@callback_funs)} — " <>
          "outside that it is not in the tessera element subset"
      )
    end
  end

  defp translate_expr({:fn, meta, _}, ctx) do
    error!(
      ctx,
      meta,
      "fn with multiple clauses or a multi-argument body is outside the tessera element subset"
    )
  end

  # capture — rejected by name
  defp translate_expr({:&, meta, _}, ctx) do
    error!(ctx, meta, "capture syntax &f/n is outside the tessera element subset")
  end

  # if / else (expression form)
  defp translate_expr({:if, _meta, [cond, [do: body]]}, ctx) do
    "(#{translate_expr(cond, ctx)} ? (#{translate_expr(body, ctx)}) : (null))"
  end

  defp translate_expr({:if, _meta, [cond, [do: body, else: alt]]}, ctx) do
    "(#{translate_expr(cond, ctx)} ? (#{translate_expr(body, ctx)}) : (#{translate_expr(alt, ctx)}))"
  end

  # pipe — desugared once per node into the piped-into call
  defp translate_expr({:|>, meta, [left, right]}, ctx) do
    translate_expr(desugar_pipe(left, right, meta, ctx), ctx)
  end

  # operators
  defp translate_expr({op, _meta, [l, r]}, ctx) when op in [:+, :-, :*, :/],
    do: "(#{translate_expr(l, ctx)} #{op} #{translate_expr(r, ctx)})"

  defp translate_expr({:==, _meta, [l, r]}, ctx),
    do: "(#{translate_expr(l, ctx)} === #{translate_expr(r, ctx)})"

  defp translate_expr({:!=, _meta, [l, r]}, ctx),
    do: "(#{translate_expr(l, ctx)} !== #{translate_expr(r, ctx)})"

  defp translate_expr({op, _meta, [l, r]}, ctx) when op in [:<, :<=, :>, :>=],
    do: "(#{translate_expr(l, ctx)} #{op} #{translate_expr(r, ctx)})"

  defp translate_expr({:and, _meta, [l, r]}, ctx),
    do: "(#{translate_expr(l, ctx)} && #{translate_expr(r, ctx)})"

  defp translate_expr({:or, _meta, [l, r]}, ctx),
    do: "(#{translate_expr(l, ctx)} || #{translate_expr(r, ctx)})"

  defp translate_expr({:not, _meta, [e]}, ctx), do: "(!#{translate_expr(e, ctx)})"
  defp translate_expr({:-, _meta, [e]}, ctx), do: "(-#{translate_expr(e, ctx)})"
  defp translate_expr({:+, _meta, [e]}, ctx), do: "(+#{translate_expr(e, ctx)})"

  defp translate_expr({:++, meta, _}, ctx) do
    error!(ctx, meta, "list concatenation ++ is outside the tessera element subset")
  end

  # base_action/3 — the derivation down-call (§5.3). In a derived action body,
  # `base_action(:name, state, params)` lowers to a real ES `super` call on the
  # inherited action method: `super.__action_<name>(params, ev)`. The `state`
  # argument is dropped (the JS base method reads `this` via __tesseraState);
  # `ev` is the generated method's event binding. Valid only in a derived body
  # and only against an INHERITED action — there is nothing below a new action.
  defp translate_expr({:base_action, meta, [name, _state, params]}, ctx) when is_atom(name) do
    unless ctx.derived? do
      error!(
        ctx,
        meta,
        "base_action/3 is only available in a derived action body (`use Base, tag: …`) — " <>
          "a fresh component has no base to dispatch to (EXTENSION-CONTRACT.md §5.3)"
      )
    end

    unless MapSet.member?(ctx.inherited_actions, name) do
      error!(
        ctx,
        meta,
        "base_action(#{inspect(name)}, …) — #{inspect(name)} is not an inherited action; " <>
          "the down-call must target an action the base declares"
      )
    end

    "super.__action_#{name}(#{translate_expr(params, ctx)}, ev)"
  end

  defp translate_expr({:base_action, meta, _args}, ctx) do
    error!(
      ctx,
      meta,
      "base_action/3 takes a literal action name, state and params — " <>
        "`base_action(:name, state, params)`"
    )
  end

  # `state = …` rebinding inside a derived action body: threads the next-state
  # object returned by a down-call (or any expression) back into `state`. The
  # generated derived method declares `let state`, so the assignment is legal.
  defp translate_expr({:=, meta, [{:state, _, var_ctx}, rhs]}, ctx) when is_atom(var_ctx) do
    unless ctx.derived? do
      error!(
        ctx,
        meta,
        "`state = …` rebinding is only available in a derived action body " <>
          "(EXTENSION-CONTRACT.md §5.3)"
      )
    end

    "(state = #{translate_expr(rhs, ctx)})"
  end

  # emit/2 — routed through @noizu/tessera-core emit (CONTRACT.md §4)
  defp translate_expr({:emit, meta, [event, detail]}, ctx) when is_binary(event) do
    unless MapSet.member?(ctx.events, event) do
      error!(
        ctx,
        meta,
        "emit(#{inspect(event)}, ...) — event is not declared; declare it with " <>
          "`event #{inspect(event)}` in the component"
      )
    end

    "emit(this, #{js_string(event)}, #{translate_expr(detail, %{ctx | camel_map_keys?: true})})"
  end

  defp translate_expr({:emit, meta, _}, ctx) do
    error!(
      ctx,
      meta,
      "emit/2 with a non-literal event name is outside the tessera element subset"
    )
  end

  # local (bare) calls — only the Kernel allowlist
  defp translate_expr({fun, meta, args}, ctx) when is_atom(fun) and is_list(args) do
    case @kernel_allowlist do
      %{^fun => {_, _, arity}} when arity == length(args) ->
        translate_kernel(fun, args, meta, ctx)

      %{^fun => _} ->
        error!(
          ctx,
          meta,
          "Kernel.#{fun}/#{length(args)} is not in the tessera element subset (wrong arity)"
        )

      _ ->
        error!(
          ctx,
          meta,
          "local call #{fun}/#{length(args)} is outside the tessera element subset — only " <>
            "allowlisted Kernel/String/Enum functions, emit/2 and the directive forms " <>
            "(class_map/1, style_map/1, if_defined/1, live/1, unsafe_html/1, guard/2, nothing) are in the subset"
        )
    end
  end

  defp translate_expr(other, ctx) do
    meta =
      if is_tuple(other) and tuple_size(other) == 3 and is_list(elem(other, 1)),
        do: elem(other, 1),
        else: nil

    error!(ctx, meta, "#{describe_construct(other)} is outside the tessera element subset")
  end

  # state.<key> is validated against the declared state keys (a typo'd read
  # must fail at compile time, not render `undefined` at runtime).
  defp field_access({:state, _, var_ctx}, right, ctx) when is_atom(var_ctx) do
    unless MapSet.member?(ctx.state_keys, right) do
      error!(
        ctx,
        nil,
        "state.#{right} — `#{inspect(right)}` is not a declared state key " <>
          "(declare it with `state #{inspect(right)}, <type>, ...`)"
      )
    end

    "state." <> js_identifier(right)
  end

  defp field_access(left, right, ctx) when is_atom(right),
    do: translate_expr(left, ctx) <> "." <> js_identifier(right)

  # -- call translation ------------------------------------------------------

  defp translate_kernel(fun, args, meta, ctx) do
    case @kernel_allowlist[fun] do
      {:prefix, js, arity} when arity == length(args) ->
        "#{js}(#{translate_args(args, ctx)})"

      {:div, _, 2} when length(args) == 2 ->
        [a, b] = translate_expr_list(args, ctx)
        "Math.trunc(#{a} / #{b})"

      {:rem, _, 2} when length(args) == 2 ->
        [a, b] = translate_expr_list(args, ctx)
        "(#{a} % #{b})"

      {:to_string, _, 1} when length(args) == 1 ->
        # the parser injects Kernel.to_string/1 (from_interpolation: true) around
        # every `#{...}` part; inside a `${}` template interpolation JS already
        # coerces, so unwrap the injected wrapper (an explicit call keeps String())
        if Keyword.get(meta, :from_interpolation, false) do
          translate_expr(hd(args), ctx)
        else
          "String(#{translate_args(args, ctx)})"
        end

      _ ->
        error!(
          ctx,
          meta,
          "Kernel.#{fun}/#{length(args)} is not in the tessera element subset — allowlist: " <>
            inspect(Enum.sort(Map.keys(@kernel_allowlist)))
        )
    end
  end

  defp translate_string(fun, args, meta, ctx) do
    case @string_allowlist[fun] do
      nil ->
        error!(
          ctx,
          meta,
          "String.#{fun} is not in the tessera element subset — allowlist: " <>
            inspect(Enum.sort(Map.keys(@string_allowlist)))
        )

      {:method1, method} ->
        "#{translate_expr(hd(args), ctx)}#{method}()"

      {:method2, method} ->
        [a, b] = translate_expr_list(args, ctx)
        "#{a}#{method}(#{b})"

      {:property, prop} ->
        "#{translate_expr(hd(args), ctx)}#{prop}"

      {:capitalize, _} ->
        "((s) => s.charAt(0).toUpperCase() + s.slice(1).toLowerCase())(#{translate_args(args, ctx)})"

      {:split, :variadic} ->
        case args do
          [s] ->
            "#{translate_expr(s, ctx)}.trim().split(/\\s+/)"

          [s, sep] ->
            "#{translate_expr(s, ctx)}.split(#{translate_expr(sep, ctx)})"

          _ ->
            error!(ctx, meta, "String.split/#{length(args)} is not in the tessera element subset")
        end

      {:replace, 3} ->
        [s, pat, rep] = translate_expr_list(args, ctx)
        "#{s}.replaceAll(#{pat}, #{rep})"

      {:parse_int, _} ->
        "parseInt(#{translate_args(args, ctx)}, 10)"
    end
  end

  defp translate_enum(fun, args, meta, ctx) do
    case @enum_allowlist[fun] do
      nil ->
        error!(
          ctx,
          meta,
          "Enum.#{fun} is not in the tessera element subset — allowlist: " <>
            inspect(Enum.sort(Map.keys(@enum_allowlist)))
        )

      {:callback, 2} ->
        [coll, cb] = args
        "#{translate_expr(coll, ctx)}.map(#{translate_expr(cb, %{ctx | callback?: true})})"

      {:count, :variadic} ->
        case args do
          [coll] ->
            "#{translate_expr(coll, ctx)}.length"

          [coll, cb] ->
            "#{translate_expr(coll, ctx)}.filter(#{translate_expr(cb, %{ctx | callback?: true})}).length"
        end

      {:at, :variadic} ->
        case args do
          [_coll, _i] ->
            "((c, i) => (i >= 0 && i < c.length ? c[i] : null))(#{translate_args(args, ctx)})"

          [_coll, _i, _default] ->
            "((c, i, d) => (i >= 0 && i < c.length ? c[i] : d))(#{translate_args(args, ctx)})"
        end

      {:join, :variadic} ->
        case args do
          [coll] -> "#{translate_expr(coll, ctx)}.join(\"\")"
          [coll, sep] -> "#{translate_expr(coll, ctx)}.join(#{translate_expr(sep, ctx)})"
        end

      {:sum, 1} ->
        "#{translate_expr(hd(args), ctx)}.reduce(((a, b) => a + b), 0)"

      {:reverse, 1} ->
        "#{translate_expr(hd(args), ctx)}.slice().reverse()"

      {:empty, 1} ->
        "(#{translate_expr(hd(args), ctx)}.length === 0)"
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp bind_action_params([{_state, _, _st_ctx}, {params, _, _pa_ctx}], ctx) do
    name = if params == :_, do: :params, else: params
    %{ctx | vars: MapSet.new([:state, name])}
  end

  defp bind_action_params(args, ctx),
    do: %{ctx | vars: MapSet.new([:state | Enum.map(args, &elem(&1, 0))])}

  defp component_read(name, %__MODULE__{} = ctx) do
    cond do
      MapSet.member?(ctx.state_keys, name) ->
        "this." <> Atom.to_string(name)

      Map.has_key?(ctx.attrs, name) ->
        "this." <> Naming.snake_to_camel(name)

      Map.has_key?(ctx.props, name) ->
        "this." <> Naming.snake_to_camel(name)

      true ->
        error!(
          ctx,
          nil,
          "template expression @#{name} does not resolve — declare `state #{inspect(name)}, ...`, " <>
            "`attr #{inspect(name)}, ...` or `prop #{inspect(name)}, ...` first"
        )
    end
  end

  # Kernel/String/Enum may appear as bare atoms (string-parsed template
  # expressions) or single-segment __aliases__ nodes (quote-parsed actions).
  # Anything else is not in the subset.
  # NOTE: a single-segment alias evaluates to the QUALIFIED module atom
  # (Enum == :"Elixir.Enum"), so Module.concat/1 — returning the bare
  # segment atom would never equal the alias in comparisons.
  defp resolve_module({:__aliases__, _, [name]}) when is_atom(name), do: Module.concat([name])
  defp resolve_module(name) when is_atom(name), do: name
  defp resolve_module(_), do: nil

  defp desugar_pipe(left, right, meta, ctx) do
    case right do
      {fun, m, args} when is_atom(fun) and is_list(args) ->
        {fun, m, args ++ [left]}

      {{:., dm, [module, fun]}, m, args} when is_list(args) ->
        {{:., dm, [module, fun]}, m, args ++ [left]}

      _ ->
        error!(ctx, meta, "pipe into #{snippet(right)} is outside the tessera element subset")
    end
  end

  # class_map/style_map argument: a map LITERAL only. A map update
  # (%{base | …}) or any non-map expression is rejected by name — the
  # directives take a plain object of keys, not a spread.
  defp directive_map!({:%{}, _m, [{:|, _, _}]}, meta, ctx, name) do
    error!(ctx, meta, "#{name}/1 requires a map literal, not a map update (%{... | ...})")
  end

  defp directive_map!({:%{}, _m, pairs}, _meta, ctx, _name) when is_list(pairs) do
    translate_expr({:%{}, [], pairs}, ctx)
  end

  defp directive_map!(other, meta, ctx, name) do
    error!(ctx, meta, "#{name}/1 requires a map literal argument — got: #{snippet(other)}")
  end

  defp translate_kv({k, v}, ctx) do
    key_js =
      case k do
        atom when is_atom(atom) ->
          name = if ctx.camel_map_keys?, do: Naming.snake_to_camel(atom), else: atom
          js_object_key(name)

        bin when is_binary(bin) ->
          js_string(bin)
      end

    "#{key_js}: #{translate_expr(v, ctx)}"
  end

  defp binary_part?(binary) when is_binary(binary), do: true
  defp binary_part?({:"::", _, [_, _]}), do: true
  defp binary_part?(_), do: false

  defp translate_args(args, ctx, joiner \\ ", "),
    do: Enum.map_join(args, joiner, &translate_expr(&1, ctx))

  defp translate_expr_list(args, ctx), do: Enum.map(args, &translate_expr(&1, ctx))

  defp js_identifier(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp js_object_key(name) do
    s = to_string(name)

    if Regex.match?(~r/^[A-Za-z_$][A-Za-z0-9_$]*$/, s) do
      s
    else
      js_string(s)
    end
  end

  defp js_string(s), do: "\"" <> String.replace(s, "\"", "\\\"") <> "\""

  defp escape_template_literal(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("`", "\\`")
    |> String.replace("${", "\\${")
  end

  defp describe_construct({form, _, _})
       when form in [:case, :cond, :with, :for, :try, :receive, :fn],
       do: "`#{form}`"

  defp describe_construct(other), do: "`#{snippet(other)}`"

  defp snippet(ast), do: ast |> Macro.to_string() |> String.slice(0, 60)

  defp error!(%__MODULE__{} = ctx, meta, description) do
    line = (is_list(meta) && Keyword.get(meta, :line)) || ctx.line || 0

    raise CompileError, file: ctx.file, line: line, description: description
  end
end
