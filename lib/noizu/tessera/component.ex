defmodule Noizu.Tessera.Component do
  @moduledoc """
  `use Noizu.Tessera.Component, tag: "persona-card", js: "persona_card.mjs"`

  Turns a module into a tessera component:

    * the `attr` / `prop` / `event` / `slot` / `cy` DSL declares the wire
      contract (CONTRACT.md §1); everything is validated at compile time and
      raises `CompileError` with a pointed message;
    * the module gains `__tessera_spec__/0` (a `Noizu.Tessera.Spec` struct)
      and `__tessera_manifest__/0` (a plain map);
    * at compile time the generated JS contract module
      (`<snake_tag>.contract.generated.mjs`, CONTRACT.md §2) is written next
      to the component's `.mjs` — only when its content changed; the `.mjs` is
      an `@external_resource`, so touching it recompiles and regenerates;
    * when Hologram is available (`Code.ensure_loaded?(Hologram.Component)`)
      the same module becomes a Hologram component via
      `Noizu.Tessera.Hologram.Adapter` (CONTRACT.md §3/§5). Without Hologram
      the module stays spec-only (the JS contract still generates).

  ## DSL

      use Noizu.Tessera.Component, tag: "persona-card", js: "persona_card.mjs"

      attr :display_name, :string, required: true
      attr :disabled, :boolean, default: false
      prop :tag_list, :list, json: true, default: []
      prop :filters, :map, json: true
      event "persona-select", detail: %{persona_id: :string, click_count: :integer}
      slot "header"
      cy "persona-card-root"

  Naming rules (CONTRACT.md §1): attr/prop/detail names are snake_case atoms;
  `attr` names reach the DOM kebab-cased, `prop` names camelCased; event
  names are kebab-case strings matching `^[a-z][a-z0-9]*(-[a-z0-9]+)+$`. Each
  event also gets a binding prop `on_<event>` (e.g. `on_persona_select`)
  whose value is `:action` (target `page`) or `{:action, target: "layout" |
  cid}`.

  When Hologram is loaded, `prop` is Hologram's own `prop/2,3` macro (imported
  by `use Hologram.Component`); tessera opts `json:` and `default:` ride along
  and are interpreted by this module's compiler. The `attr` macro additionally
  declares the Hologram prop behind the scenes, and each `event` declares its
  `on_<event>` binding prop — all during module-body expansion, so Hologram's
  `@__props__` accumulator is complete before Hologram's `__before_compile__`
  runs (hooks run in registration order, hologram's first).

  Reserved names: the generated component defines `__tessera_*__` helpers and
  `template/0` — do not define them by hand.
  """

  alias Noizu.Tessera.Component.Expr
  alias Noizu.Tessera.Component.LitCodegen
  alias Noizu.Tessera.Component.Template
  alias Noizu.Tessera.Hologram.Adapter
  alias Noizu.Tessera.Naming
  alias Noizu.Tessera.Spec

  @contract_version 1

  # -- use -------------------------------------------------------------------

  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    caller = __CALLER__
    tag = Keyword.get(opts, :tag)
    js = Keyword.get(opts, :js)

    Spec.validate!(:tag, tag, %{}, caller.file, caller.line)
    validate_js_option!(js, caller.file, caller.line)

    hologram? = Adapter.available?()
    mjs_path = hologram? && js && Adapter.mjs_path(caller.file, js)

    quote do
      Module.put_attribute(__MODULE__, :tessera_tag, unquote(tag))
      Module.put_attribute(__MODULE__, :tessera_js, unquote(js))

      # DSL accumulators. In Hologram mode `prop` entries accumulate through
      # Hologram's own @__props__ (use Hologram.Component, below, registers
      # it); in spec-only mode they land in :tessera_props.
      Module.register_attribute(__MODULE__, :tessera_attrs, accumulate: true)
      Module.register_attribute(__MODULE__, :tessera_events, accumulate: true)
      Module.register_attribute(__MODULE__, :tessera_slots, accumulate: true)
      Module.register_attribute(__MODULE__, :tessera_props, accumulate: true)
      Module.register_attribute(__MODULE__, :tessera_cy, accumulate: true)

      # SPIKE (spike/elixir-to-lit): element-DSL accumulators — `state`,
      # `action` and the single `template ~TSR` declaration.
      Module.register_attribute(__MODULE__, :tessera_state, accumulate: true)
      Module.register_attribute(__MODULE__, :tessera_actions, accumulate: true)
      Module.register_attribute(__MODULE__, :tessera_template, accumulate: true)

      # Hologram component plumbing (hologram mode only): `use Hologram.JS`
      # registers the @__js_imports__ accumulator; the import RESTATES
      # js_import/1-2 alongside call/2 because a second only-import of the
      # same module replaces, not merges (CONTRACT.md §5).
      unquote_splicing(hologram_asts(hologram?, mjs_path))

      import Noizu.Tessera.Component, only: unquote(import_list(hologram?))

      @before_compile Noizu.Tessera.Component
      @after_compile Noizu.Tessera.Component
    end
  end

  defp import_list(false),
    do: [
      attr: 2,
      attr: 3,
      prop: 2,
      prop: 3,
      event: 1,
      event: 2,
      slot: 1,
      cy: 1,
      state: 2,
      state: 3,
      template: 1,
      action: 2,
      sigil_TSR: 2
    ]

  defp import_list(true),
    # prop/2-3 come from Hologram.Component's import when Hologram is loaded.
    do: [
      attr: 2,
      attr: 3,
      event: 1,
      event: 2,
      slot: 1,
      cy: 1,
      state: 2,
      state: 3,
      template: 1,
      action: 2,
      sigil_TSR: 2
    ]

  defp hologram_asts(false, _mjs_path), do: []

  defp hologram_asts(true, mjs_path) do
    [
      quote do
        use Hologram.Component
        use Hologram.JS
        import Hologram.JS, only: [call: 2, js_import: 1, js_import: 2]
      end
      | Adapter.js_import_asts(mjs_path)
    ]
  end

  # -- DSL -------------------------------------------------------------------

  @doc false
  @spec attr(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro attr(name, type, opts \\ []) do
    record_ast(:attr, name, type, opts, __CALLER__)
  end

  # In Hologram mode the author-facing `prop` is Hologram.Component's macro
  # (delegation by import); this module's own prop macro is imported only in
  # spec-only mode (see import_list/1).
  @doc false
  @spec prop(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro prop(name, type, opts \\ []) do
    record_ast(:prop, name, type, opts, __CALLER__)
  end

  @doc false
  @spec event(Macro.t(), Macro.t()) :: Macro.t()
  defmacro event(name, opts \\ []) do
    record_ast(:event, name, nil, opts, __CALLER__)
  end

  @doc false
  @spec slot(Macro.t()) :: Macro.t()
  defmacro slot(name) do
    record_ast(:slot, name, nil, [], __CALLER__)
  end

  @doc false
  @spec cy(Macro.t()) :: Macro.t()
  defmacro cy(hook) do
    record_ast(:cy, hook, nil, [], __CALLER__)
  end

  # -- SPIKE element DSL (spike/elixir-to-lit) ---------------------------------
  #
  # `state` / `template ~TSR` / `action` extend the wire-contract DSL into a
  # full element definition: state keys become reactive properties, the
  # template compiles to a lit-html `render()`, and actions are translated
  # from a restricted Elixir subset to JS at compile time (never compiled
  # into the BEAM — Hologram's call-graph transpiler never sees them).
  # docs/notes/spike-elixir-to-lit.md.

  @doc false
  @spec state(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro state(name, type, opts \\ []) do
    record_ast(:state, name, type, opts, __CALLER__)
  end

  @doc false
  # Accepts a ~TSR sigil call (macros receive the sigil's UNEXPANDED call
  # AST), a plain string literal or a bare binary (literals are their own
  # AST). The markup is recorded as DATA, unescaped: it is parsed at
  # __before_compile__, never evaluated.
  #
  # `~TSR"""..."""` arrives in macro arguments as the UNEXPANDED
  # `sigil_TSR/2` call AST whose binary arg is a {:<<>>, _, [s]} node (the
  # ~ sigil sugar desugars before expansion). The shared body lives in
  # template_record_ast/2, a plain defp that BUILDS the quote — a defmacrop
  # called from another macro's body would expand at definition time
  # instead of invocation time.
  @spec template(Macro.t()) :: Macro.t()
  defmacro template({:sigil_TSR, _, [{:<<>>, _, [markup]}, modifiers]})
           when is_binary(markup) and modifiers == [],
           do: template_record_ast(__CALLER__, markup)

  defmacro template(markup) when is_binary(markup),
    do: template_record_ast(__CALLER__, markup)

  defmacro template({:<<>>, _meta, [markup]}) when is_binary(markup),
    do: template_record_ast(__CALLER__, markup)

  defmacro template(other) do
    caller = __CALLER__

    raise CompileError,
      file: caller.file,
      line: caller.line,
      description:
        "tessera template must be a ~TSR literal (or plain string literal), got: " <>
          Macro.to_string(other)
  end

  defp template_record_ast(%Macro.Env{} = caller, markup) when is_binary(markup) do
    quote bind_quoted: [consumer: caller.module, markup: markup, line: caller.line, file: caller.file] do
      Noizu.Tessera.Component.record(consumer, :template, markup, nil, [], line, file, false)
    end
  end

  @doc false
  # The fn AST is escaped as DATA (Macro.escape) — at __before_compile__ it is
  # translated to JS by Noizu.Tessera.Component.Expr, never evaluated.
  @spec action(Macro.t(), Macro.t()) :: Macro.t()
  defmacro action(name, fn_ast) do
    caller = __CALLER__

    quote bind_quoted: [
            consumer: caller.module,
            name: name,
            fn_ast: Macro.escape(fn_ast),
            line: caller.line,
            file: caller.file
          ] do
      Noizu.Tessera.Component.record(consumer, :action, name, fn_ast, [], line, file, false)
    end
  end

  @doc false
  # `~TSR"""..."""` — raw tessera template markup (HOLO-like `{expr}` /
  # `{%if}` / `{%for}` / `$event={:action}`), passed through verbatim to
  # `template/1`. Deliberately NOT `~HOLO`: that sigil is imported by
  # `use Hologram.Component` for the page-level Hologram template, and a
  # second import of the same name in a component module would collide.
  @spec sigil_TSR({:<<>>, list(), [String.t()]}, list()) :: Macro.t()
  defmacro sigil_TSR({:<<>>, _meta, [markup]}, _modifiers) when is_binary(markup), do: markup
  defmacro sigil_TSR(markup, _modifiers) when is_binary(markup), do: markup

  # Expansion-time builder shared by the DSL macros. A plain function (not a
  # defmacrop) so the AST arguments are ordinary call arguments. Returns code
  # that calls record/8 while the consumer module body runs — that is when
  # Module.put_attribute applies to the consumer (line-accurate CompileError,
  # Hologram's @__props__ fed before its __before_compile__ hook runs).
  defp record_ast(kind, name, type, opts, %Macro.Env{} = caller) do
    quote bind_quoted: [
            consumer: caller.module,
            kind: kind,
            name: name,
            type: type,
            opts: Macro.escape(opts),
            line: caller.line,
            file: caller.file,
            hologram?: Adapter.available?()
          ] do
      Noizu.Tessera.Component.record(consumer, kind, name, type, opts, line, file, hologram?)
    end
  end

  @doc false
  # Compile-time sink for the DSL macros — runs during the consumer module's
  # body expansion, with the consumer module passed explicitly. Validates the
  # entry immediately (line-accurate CompileError) and, in Hologram mode,
  # feeds Hologram's @__props__ accumulator with the props the generated
  # component needs (attrs and on_<event> binding props). Body-time (not
  # __before_compile__) on purpose: @before_compile hooks run in registration
  # order and Hologram's hook reads @__props__ first.
  def record(consumer, :attr, name, type, opts, line, file, hologram?) do
    opts = eval_opts!(opts, :attr, name, file, line)
    Spec.validate!(:attr, name, %{type: type}, file, line)

    entry = %{
      name: name,
      type: type,
      required: !!opts[:required],
      default: opts[:default],
      line: line
    }

    Module.put_attribute(consumer, :tessera_attrs, {line, entry})

    if hologram? do
      Module.put_attribute(consumer, :__props__, {name, type, [tessera_origin: :attr] ++ opts})
    end

    :ok
  end

  def record(consumer, :prop, name, type, opts, line, file, _hologram?) do
    opts = eval_opts!(opts, :prop, name, file, line)
    Spec.validate!(:prop, name, %{type: type}, file, line)

    entry = %{
      name: name,
      type: type,
      json: !!opts[:json],
      default: opts[:default],
      line: line
    }

    Module.put_attribute(consumer, :tessera_props, {line, entry})
    :ok
  end

  def record(consumer, :event, name, _type, opts, line, file, hologram?) do
    opts = eval_opts!(opts, :event, name, file, line)
    detail = opts[:detail] || %{}
    Spec.validate!(:event, name, detail, file, line)

    Module.put_attribute(
      consumer,
      :tessera_events,
      {line, %{name: name, detail: detail, line: line}}
    )

    if hologram? do
      binding = Naming.event_binding_prop(name)

      Module.put_attribute(
        consumer,
        :__props__,
        {binding, :any, [tessera_origin: :binding, default: nil]}
      )
    end

    :ok
  end

  def record(consumer, :slot, name, _type, _opts, line, file, _hologram?) do
    Spec.validate!(:slot, name, %{}, file, line)
    Module.put_attribute(consumer, :tessera_slots, {line, %{name: to_string(name), line: line}})
    :ok
  end

  def record(consumer, :cy, hook, _type, _opts, line, file, _hologram?) do
    unless is_binary(hook) do
      raise CompileError,
        file: file,
        line: line,
        description: "tessera cy hook must be a string, got: #{inspect(hook)}"
    end

    Module.put_attribute(consumer, :tessera_cy, {line, hook})
    :ok
  end

  # SPIKE (spike/elixir-to-lit): element-DSL sinks. `state` validates like an
  # attr (snake_case atom + known type, JSON-safe default); `template` /
  # `action` only record their payload here — translation happens in
  # __before_compile__ so errors carry the declaration's line.
  def record(consumer, :state, name, type, opts, line, file, _hologram?) do
    opts = eval_opts!(opts, :state, name, file, line)
    Spec.validate!(:state, name, %{type: type}, file, line)
    assert_json_safe_default!(opts[:default], :state, name, file, line)

    entry = %{name: name, type: type, default: opts[:default], line: line}
    Module.put_attribute(consumer, :tessera_state, {line, entry})
    :ok
  end

  def record(consumer, :template, markup, _type, _opts, line, file, _hologram?) do
    unless is_binary(markup) and markup != "" do
      raise CompileError,
        file: file,
        line: line,
        description: "tessera template must be a non-empty ~TSR literal string"
    end

    Module.put_attribute(consumer, :tessera_template, {line, markup})
    :ok
  end

  def record(consumer, :action, name, fn_ast, _opts, line, file, _hologram?) do
    unless is_atom(name) and Regex.match?(Naming.snake_regex(), Atom.to_string(name)) do
      raise CompileError,
        file: file,
        line: line,
        description: "tessera action name #{inspect(name)} must be a snake_case atom (e.g. :increment)"
    end

    unless match?({:fn, _, [{:->, _, [args, _body]}]} when length(args) == 2, fn_ast) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera action #{inspect(name)} must be a single-clause fn with exactly two " <>
            "arguments — `fn state, params -> ... end` (the restricted subset, " <>
            "docs/notes/spike-elixir-to-lit.md)"
    end

    Module.put_attribute(consumer, :tessera_actions, {line, %{name: name, fn_ast: fn_ast, line: line}})
    :ok
  end

  def record(_consumer, kind, _name, _type, _opts, line, file, _hologram?) do
    raise CompileError,
      file: file,
      line: line,
      description: "unknown tessera DSL entry: #{inspect(kind)}"
  end

  # -- compile hooks ---------------------------------------------------------

  @doc false
  @spec __before_compile__(Macro.Env.t()) :: Macro.t()
  defmacro __before_compile__(env) do
    attrs = attr_entries(env)
    props = prop_entries(env)
    events = event_entries(env)
    slots = slot_entries(env)
    cys = accumulated(env.module, :tessera_cy)

    validate_all!(attrs, props, events, slots, cys, env)

    # SPIKE: translate state/actions/template into the spec (JS strings + the
    # pre-rendered lit-html render()). Raises CompileError with the DSL
    # declaration's line on any subset violation.
    lit = lit_compile!(attrs, props, events, env)

    spec = %Spec{
      version: @contract_version,
      tag: Module.get_attribute(env.module, :tessera_tag),
      module: env.module,
      file: env.file,
      js: Module.get_attribute(env.module, :tessera_js),
      cy: cys != [] && elem(List.last(cys), 1),
      attrs: attrs,
      props: props,
      events: events,
      slots: slots,
      state: lit.state,
      actions: lit.actions,
      template: lit.template
    }

    body =
      if Adapter.available?() do
        Adapter.body_ast(spec, Path.dirname(env.file))
      else
        quote do
          @doc "The compiled `Noizu.Tessera.Spec` struct for this component."
          @spec __tessera_spec__() :: Noizu.Tessera.Spec.t()
          def __tessera_spec__, do: @tessera_compiled_spec

          @doc "The tessera manifest entry (plain map) for this component."
          @spec __tessera_manifest__() :: map()
          def __tessera_manifest__, do: unquote(Macro.escape(Spec.to_manifest_map(spec)))
        end
      end

    quote do
      @tessera_compiled_spec unquote(Macro.escape(spec))
      unquote(body)
    end
  end

  # Runs at expansion: the spec attribute is readable here, and the write
  # side-effect happens once, after the module body is fully compiled.
  @doc false
  defmacro __after_compile__(env, _beam) do
    case Module.get_attribute(env.module, :tessera_compiled_spec) do
      nil ->
        :ok

      %Spec{} = spec ->
        Adapter.write_contract_next_to_mjs(spec)
        write_lit_modules!(spec, Path.dirname(env.file))
    end

    quote(do: :ok)
  end

  # -- spec assembly ---------------------------------------------------------

  defp attr_entries(env) do
    accumulated(env.module, :tessera_attrs) |> Enum.map(fn {_line, entry} -> entry end)
  end

  # In Hologram mode the author's `prop` DSL went through Hologram's prop
  # macro into Hologram's accumulator ({name, type, opts}); entries carrying a
  # :tessera_origin opt are the attr/binding-prop declarations tessera itself
  # made and are excluded. In spec-only mode the author's prop DSL went
  # through this module's prop macro into :tessera_props.
  defp prop_entries(env) do
    if Adapter.available?() do
      accumulated(env.module, :__props__)
      |> Enum.reject(fn {_name, _type, opts} -> opts[:tessera_origin] end)
      |> Enum.map(fn {name, type, opts} ->
        %{name: name, type: type, json: !!opts[:json], default: opts[:default], line: 0}
      end)
    else
      accumulated(env.module, :tessera_props)
      |> Enum.map(fn {_line, entry} -> entry end)
    end
  end

  defp event_entries(env) do
    accumulated(env.module, :tessera_events) |> Enum.map(fn {_line, entry} -> entry end)
  end

  defp slot_entries(env) do
    accumulated(env.module, :tessera_slots) |> Enum.map(fn {_line, entry} -> entry end)
  end

  # -- SPIKE lit assembly (spike/elixir-to-lit) --------------------------------

  # Translate the recorded state/action/template declarations into their spec
  # shapes: action fn ASTs become JS bodies (restricted subset — anything
  # outside raises CompileError naming the construct), the template markup
  # becomes the pre-rendered lit-html render() string.
  defp lit_compile!(attrs, props, events, env) do
    state =
      accumulated(env.module, :tessera_state) |> Enum.map(fn {_line, entry} -> entry end)

    actions_raw =
      accumulated(env.module, :tessera_actions) |> Enum.map(fn {_line, entry} -> entry end)

    templates = accumulated(env.module, :tessera_template)

    assert_no_duplicates!(:state, state, env)
    assert_no_action_duplicates!(actions_raw, env)

    template = assert_single_template!(templates, state, actions_raw, env)

    ctx = %Expr{
      state_keys: MapSet.new(Enum.map(state, & &1.name)),
      attrs: Map.new(attrs, &{&1.name, &1.type}),
      props: Map.new(props, &{&1.name, &1.type}),
      events: MapSet.new(Enum.map(events, & &1.name)),
      actions: MapSet.new(Enum.map(actions_raw, & &1.name)),
      module: env.module,
      file: env.file,
      line: 0
    }

    actions =
      Enum.map(actions_raw, fn entry ->
        js = Expr.translate_action(entry.fn_ast, %{ctx | line: entry.line || 0})
        %{name: entry.name, js: js, line: entry.line}
      end)

    template_entry =
      template &&
        (with {:ok, tree} <- Template.parse(template.markup) do
           %{
             raw: template.markup,
             lexer: Template.lexer(),
             render_js: Template.to_lit_render(tree, %{ctx | line: template.line}),
             line: template.line
           }
         else
           {:error, msg} ->
             raise CompileError,
               file: env.file,
               line: template.line,
               description: "tessera template: " <> msg
         end)

    %{state: state, actions: actions, template: template_entry}
  end

  defp assert_single_template!(templates, state, actions_raw, env) do
    case templates do
      [] ->
        if state != [] or actions_raw != [] do
          raise CompileError,
            file: env.file,
            line: 0,
            description:
              "tessera state/action declarations require a matching template ~TSR declaration " <>
                "(the element DSL is all-or-nothing: state + actions + template)"
        end

        nil

      [{line, markup}] ->
        js = Module.get_attribute(env.module, :tessera_js)

        if is_nil(js) do
          raise CompileError,
            file: env.file,
            line: line,
            description:
              "tessera template requires the :js option (the generated wrapper entry that " <>
                "bundles the Lit element into Hologram page bundles)"
        end

        %{line: line, markup: markup}

      many ->
        raise CompileError,
          file: env.file,
          line: elem(hd(many), 0),
          description:
            "duplicate tessera template declaration (#{length(many)} times) — " <>
              "a component has one template"
    end
  end

  defp assert_no_action_duplicates!(actions_raw, env) do
    actions_raw
    |> Enum.group_by(& &1.name)
    |> Enum.each(fn {name, group} ->
      if length(group) > 1 do
        raise CompileError,
          file: env.file,
          line: hd(Enum.map(group, & &1.line)),
          description:
            "duplicate tessera action #{inspect(name)} (declared at lines " <>
              "#{inspect(Enum.map(group, & &1.line))})"
      end
    end)
  end

  # The generated Lit element + its :js entry wrapper, next to the component's
  # .ex (and contract module). Failures warn (same posture as the contract
  # write) — a broken write should not kill the compile of unrelated hosts.
  defp write_lit_modules!(%Spec{template: nil}, _dir), do: :ok

  defp write_lit_modules!(%Spec{} = spec, dir) do
    case LitCodegen.write_element_module(spec, dir) do
      {:error, reason} ->
        IO.warn("[tessera] could not write #{spec.tag}.element.generated.mjs: #{inspect(reason)}", [])

      _ ->
        :ok
    end

    case LitCodegen.write_wrapper_module(spec, dir) do
      {:error, reason} ->
        IO.warn("[tessera] could not write #{spec.js}: #{inspect(reason)}", [])

      _ ->
        :ok
    end
  end

  defp assert_json_safe_default!(default, kind, name, file, line) do
    Spec.json_literal(default)
  rescue
    e ->
      raise CompileError,
        file: file,
        line: line,
        description: "tessera #{kind} #{inspect(name)} default: #{Exception.message(e)}"
  end

  # Accumulate attributes come out newest-first; reverse so spec entries keep
  # DSL declaration order (hologram does the same for @__props__).
  defp accumulated(module, attribute) when is_atom(module) do
    case Module.get_attribute(module, attribute) do
      nil -> []
      value when is_list(value) -> Enum.reverse(value)
      other -> List.wrap(other)
    end
  end

  # -- validation ------------------------------------------------------------

  defp validate_all!(attrs, props, events, slots, cys, env) do
    # Full contract re-validation over the final entries. The DSL macros
    # validate at record time, but in Hologram mode `prop` lines go through
    # Hologram's own macro and only land here.
    Enum.each(attrs, fn entry ->
      Spec.validate!(:attr, entry.name, %{type: entry.type}, env.file, entry.line)
    end)

    Enum.each(props, fn entry ->
      Spec.validate!(:prop, entry.name, %{type: entry.type}, env.file, entry.line || 0)
    end)

    assert_no_duplicates!(:attr, attrs, env)
    assert_no_duplicates!(:prop, props, env)
    assert_no_duplicates!(:event, events, env)
    assert_no_duplicates!(:slot, slots, env)

    if length(cys) > 1 do
      raise CompileError,
        file: env.file,
        line: elem(hd(cys), 0),
        description:
          "duplicate tessera cy declaration (#{length(cys)} times) — a component has one data-cy hook"
    end

    prop_names = MapSet.new(Enum.map(props, & &1.name))
    attr_names = MapSet.new(Enum.map(attrs, & &1.name))
    collision = MapSet.to_list(MapSet.intersection(attr_names, prop_names))

    unless collision == [] do
      entry = Enum.find(attrs ++ props, fn e -> e.name in collision end)

      raise CompileError,
        file: env.file,
        line: entry.line || 0,
        description:
          "tessera attr/prop name collision on #{inspect(hd(collision))} — an attr " <>
            "(DOM attribute) and a prop (DOM property) cannot share a name"
    end

    :ok
  end

  defp assert_no_duplicates!(kind, entries, env) do
    entries
    |> Enum.group_by(& &1.name)
    |> Enum.each(fn {name, group} ->
      if length(group) > 1 do
        lines = Enum.map(group, fn e -> e.line || 0 end)

        raise CompileError,
          file: env.file,
          line: hd(lines),
          description:
            "duplicate tessera #{kind} #{inspect(name)} (declared at lines #{inspect(lines)})"
      end
    end)
  end

  # -- option validation -----------------------------------------------------

  defp validate_js_option!(nil, _file, _line), do: :ok

  defp validate_js_option!(js, file, line) do
    unless is_binary(js) and Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9._-]*\.mjs$/, js) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera :js option must be a plain colocated filename ending in .mjs " <>
            "(e.g. \"persona_card.mjs\"), got: #{inspect(js)}"
    end
  end

  # DSL opts arrive as the caller's AST (record_ast escapes it for the
  # compile-time sink). Turn it into runtime values so defaults/detail maps
  # are real literals — and reject anything that needs bindings, since the
  # wire contract must be known at compile time.
  defp eval_opts!(opts, kind, name, file, line) do
    {value, _binding} = Code.eval_quoted(opts, [], file: file, line: line)

    unless is_nil(value) or Keyword.keyword?(value) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera #{kind} #{inspect(name)} options must be a keyword list of " <>
            "compile-time literals, got: #{inspect(value)}"
    end

    value || []
  rescue
    e ->
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera #{kind} #{inspect(name)} options must be compile-time literals " <>
            "(no variables or module attributes) — #{Exception.message(e)}"
  end
end
