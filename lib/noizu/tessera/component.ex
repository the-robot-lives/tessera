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
      css "--persona-card-accent", default: "#6366f1"
      part "select-button"
      cy "persona-card-root"

      styles ~CSS":host { border-color: var(--tsr-persona-card-accent, #6cf); }"

  Element DSL (template-bearing components): `state`, `action`, the lifecycle
  hooks `should_update` / `will_update` / `first_updated` / `updated` (each
  `fn state, changed -> ... end`), and `?attr={expr}` boolean attribute
  bindings in the template. `attr`/`prop`/`state` accept Lit property options
  `attribute: "custom-name" | false` and `reflect: true`; `:list` types emit
  Lit's `Array` converter.

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
  alias Noizu.Tessera.Component.Extension
  alias Noizu.Tessera.Component.LitCodegen
  alias Noizu.Tessera.Component.Styles
  alias Noizu.Tessera.Component.Template
  alias Noizu.Tessera.Hologram.Adapter
  alias Noizu.Tessera.Naming
  alias Noizu.Tessera.Spec

  @contract_version 1

  # -- use -------------------------------------------------------------------

  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    caller = __CALLER__
    {derived?, opts} = Keyword.pop(opts, :__derived__, false)
    tag = Keyword.get(opts, :tag)
    js = Keyword.get(opts, :js)
    extension_api = Keyword.get(opts, :extension_api)
    validate_extension_api_option!(extension_api, caller.file, caller.line)
    form_associated = Keyword.get(opts, :form_associated)
    validate_form_associated_option!(form_associated, caller.file, caller.line)

    # Set at EXPANSION time (not in the quoted output) so a later `use Base`
    # expansion can see it for the reverse double-use guard — quoted
    # Module.put_attribute calls only evaluate after nested macro expansion.
    Module.put_attribute(caller.module, :tessera_tag, tag)

    # §8.3 declaration lane — only set when the author declared one, so a
    # deriving module's concrete version (placed by Extension.derive!/3 before
    # this internal `use`) is not clobbered. Absent ⇒ __before_compile__
    # defaults to the first stable 1.0.0.
    if extension_api do
      Module.put_attribute(caller.module, :tessera_extension_api, extension_api)
    end

    # §6.7 declaration lane (brief 2f) — only `true` sets the attribute; the
    # struct defaults to false and a deriving module inherits the base's value
    # in __before_compile__ (participation is additive, never silently dropped).
    if form_associated == true do
      Module.put_attribute(caller.module, :tessera_form_associated, true)
    end

    # §5.1: a deriving module (`use Base, tag: …`) must not repeat the
    # compiler. The internal use from Extension.derive!/3 carries __derived__
    # to lift the guard for itself only.
    if not derived? and Module.get_attribute(caller.module, :tessera_derived_from) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera double use: #{inspect(caller.module)} derives from " <>
            "#{inspect(Module.get_attribute(caller.module, :tessera_derived_from))} — " <>
            "do not also `use Noizu.Tessera.Component` (EXTENSION-CONTRACT.md §5.1)"
    end

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
      Module.register_attribute(__MODULE__, :tessera_css_properties, accumulate: true)
      Module.register_attribute(__MODULE__, :tessera_parts, accumulate: true)
      Module.register_attribute(__MODULE__, :tessera_cy, accumulate: true)

      # SPIKE (spike/elixir-to-lit): element-DSL accumulators — `state`,
      # `action` and the single `template ~TSR` declaration.
      Module.register_attribute(__MODULE__, :tessera_state, accumulate: true)
      Module.register_attribute(__MODULE__, :tessera_actions, accumulate: true)
      Module.register_attribute(__MODULE__, :tessera_template, accumulate: true)

      # Template region overrides (brief 2d, EXTENSION-CONTRACT.md §5.4):
      # `slot_template :name, ~TSR"""…"""` — derived modules only; a fresh
      # component declaring one fails compilation.
      Module.register_attribute(__MODULE__, :tessera_slot_templates, accumulate: true)

      # Styles DSL: `styles` declarations accumulate in order (css blocks,
      # plain strings and {:shared, path} entries compose into the element's
      # static styles array).
      Module.register_attribute(__MODULE__, :tessera_styles, accumulate: true)

      # Lifecycle DSL (lit-parity 1c): one map keyed by hook — each hook may be
      # declared at most once (duplicate → CompileError at record time).
      Module.register_attribute(__MODULE__, :tessera_lifecycle, accumulate: false)

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
      css: 1,
      css: 2,
      part: 1,
      cy: 1,
      state: 2,
      state: 3,
      template: 1,
      slot_template: 2,
      action: 2,
      action: 3,
      should_update: 1,
      will_update: 1,
      first_updated: 1,
      updated: 1,
      styles: 1,
      sigil_TSR: 2,
      sigil_CSS: 2
    ]

  defp import_list(true),
    # prop/2-3 come from Hologram.Component's import when Hologram is loaded.
    do: [
      attr: 2,
      attr: 3,
      event: 1,
      event: 2,
      slot: 1,
      css: 1,
      css: 2,
      part: 1,
      cy: 1,
      state: 2,
      state: 3,
      template: 1,
      slot_template: 2,
      action: 2,
      action: 3,
      should_update: 1,
      will_update: 1,
      first_updated: 1,
      updated: 1,
      styles: 1,
      sigil_TSR: 2,
      sigil_CSS: 2
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
  @spec css(Macro.t(), Macro.t()) :: Macro.t()
  defmacro css(name, opts \\ []) do
    record_ast(:css, name, nil, opts, __CALLER__)
  end

  @doc false
  @spec part(Macro.t()) :: Macro.t()
  defmacro part(name) do
    record_ast(:part, name, nil, [], __CALLER__)
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
    quote bind_quoted: [
            consumer: caller.module,
            markup: markup,
            line: caller.line,
            file: caller.file
          ] do
      Noizu.Tessera.Component.record(consumer, :template, markup, nil, [], line, file, false)
    end
  end

  @doc false
  # `slot_template :name, ~TSR"""…"""` — a region override (brief 2d,
  # EXTENSION-CONTRACT.md §5.4). Derived modules only: it replaces the default
  # body of the base region `:name`; `{%super%}` inside the body composes the
  # base fragment at that point. Validation against the base's declared
  # regions happens at __before_compile__ (the base spec is only readable
  # then).
  @spec slot_template(Macro.t(), Macro.t()) :: Macro.t()
  defmacro slot_template(name, {:sigil_TSR, _, [{:<<>>, _, [markup]}, modifiers]})
           when is_binary(markup) and modifiers == [],
           do: slot_template_record_ast(__CALLER__, name, markup)

  defmacro slot_template(name, markup) when is_binary(markup),
    do: slot_template_record_ast(__CALLER__, name, markup)

  defmacro slot_template(name, {:<<>>, _meta, [markup]}) when is_binary(markup),
    do: slot_template_record_ast(__CALLER__, name, markup)

  defmacro slot_template(name, other) do
    caller = __CALLER__

    raise CompileError,
      file: caller.file,
      line: caller.line,
      description:
        "tessera slot_template #{inspect(name)} must be a ~TSR literal (or plain string " <>
          "literal), got: " <> Macro.to_string(other)
  end

  defp slot_template_record_ast(%Macro.Env{} = caller, name, markup) when is_binary(markup) do
    quote bind_quoted: [
            consumer: caller.module,
            name: name,
            markup: markup,
            line: caller.line,
            file: caller.file
          ] do
      Noizu.Tessera.Component.record(
        consumer,
        :slot_template,
        name,
        markup,
        [],
        line,
        file,
        false
      )
    end
  end

  @doc false
  # The fn AST is escaped as DATA (Macro.escape) — at __before_compile__ it is
  # translated to JS by Noizu.Tessera.Component.Expr, never evaluated.
  #
  # `internal: true` is the EXTENSION-CONTRACT.md §5.3 ADVISORY annotation —
  # it groups the action under internal docs in the CEM and makes the runtime
  # warn once when an interceptor registers against it. It NEVER restricts
  # dispatch or interception (open surface, D2/§10).
  @spec action(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro action(name, fn_ast, opts \\ []) do
    caller = __CALLER__

    quote bind_quoted: [
            consumer: caller.module,
            name: name,
            fn_ast: Macro.escape(fn_ast),
            opts: opts,
            line: caller.line,
            file: caller.file
          ] do
      Noizu.Tessera.Component.record(consumer, :action, name, fn_ast, opts, line, file, false)
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

  # -- lifecycle DSL (lit-parity 1c) -------------------------------------------
  #
  # `should_update` / `will_update` / `first_updated` / `updated` each take a
  # restricted-subset `fn state, changed -> ... end` (same shape as action/2).
  # `changed` is a plain-object snapshot of Lit's changedProperties Map — keys
  # are property names (camelCase attrs/props, snake state), values are the OLD
  # values (undefined on the first update). The second argument must be named
  # `changed` (or `_` / `_changed`): the generated method declares that exact
  # binding. The fn AST is recorded as DATA and translated to JS at
  # __before_compile__.

  @doc false
  @spec should_update(Macro.t()) :: Macro.t()
  defmacro should_update(fn_ast), do: lifecycle_record_ast(:should_update, fn_ast, __CALLER__)

  @doc false
  @spec will_update(Macro.t()) :: Macro.t()
  defmacro will_update(fn_ast), do: lifecycle_record_ast(:will_update, fn_ast, __CALLER__)

  @doc false
  @spec first_updated(Macro.t()) :: Macro.t()
  defmacro first_updated(fn_ast), do: lifecycle_record_ast(:first_updated, fn_ast, __CALLER__)

  @doc false
  @spec updated(Macro.t()) :: Macro.t()
  defmacro updated(fn_ast), do: lifecycle_record_ast(:updated, fn_ast, __CALLER__)

  defp lifecycle_record_ast(hook, fn_ast, %Macro.Env{} = caller) do
    quote bind_quoted: [
            consumer: caller.module,
            hook: hook,
            fn_ast: Macro.escape(fn_ast),
            line: caller.line,
            file: caller.file
          ] do
      Noizu.Tessera.Component.record(consumer, :lifecycle, hook, fn_ast, [], line, file, false)
    end
  end

  # -- styles DSL ----------------------------------------------------------------
  #
  # `styles` declares author CSS for the generated Lit element (lit-parity
  # §2.5). Entries are compile-time literals — a ~CSS sigil block, a plain
  # string, or a {:shared, "path.mjs"} tuple pointing at a Lit shared-styles
  # module (`export const styles = css`…``). A single entry or a static list
  # composes; repeated declarations append in order. The CSS text is recorded
  # as DATA and emitted into the element's `static styles = [baseStyles, …]`
  # array — Lit validates it at runtime, tessera does not parse it.

  @doc false
  @spec styles(Macro.t()) :: Macro.t()
  defmacro styles(entries) when is_list(entries) do
    caller = __CALLER__

    if entries == [] do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera styles list is empty — declare at least one ~CSS literal, " <>
            "string or {:shared, \"path.mjs\"} entry"
    end

    styles_record_ast(caller, Enum.map(entries, &normalize_style_entry!(&1, caller)))
  end

  defmacro styles(entry) do
    caller = __CALLER__
    styles_record_ast(caller, [normalize_style_entry!(entry, caller)])
  end

  defp normalize_style_entry!({:sigil_CSS, _, [{:<<>>, _, [css]}, modifiers]}, _caller)
       when is_binary(css) and modifiers == [],
       do: %{kind: :css, value: css}

  defp normalize_style_entry!({:<<>>, _, [css]}, _caller) when is_binary(css),
    do: %{kind: :css, value: css}

  defp normalize_style_entry!(css, _caller) when is_binary(css),
    do: %{kind: :css, value: css}

  # A 2-tuple literal is its own AST ({:shared, path}, not {:{}, _, […]}).
  defp normalize_style_entry!({:shared, path}, _caller) when is_binary(path),
    do: %{kind: :shared, value: path}

  defp normalize_style_entry!(other, caller) do
    raise CompileError,
      file: caller.file,
      line: caller.line,
      description:
        "tessera styles entries must be ~CSS literals, plain strings or " <>
          "{:shared, \"path.mjs\"} tuples (compile-time literals), got: " <>
          Macro.to_string(other)
  end

  defp styles_record_ast(%Macro.Env{} = caller, entries) do
    quote bind_quoted: [
            consumer: caller.module,
            entries: Macro.escape(entries),
            line: caller.line,
            file: caller.file
          ] do
      Noizu.Tessera.Component.record(consumer, :styles, entries, nil, [], line, file, false)
    end
  end

  # The scanner raises ArgumentError on malformed var() — surface it as a
  # line-accurate CompileError like every other DSL violation.
  defp missing_fallbacks!(css, tag, file, line) do
    Styles.missing_fallbacks(css, tag)
  rescue
    e in ArgumentError ->
      raise CompileError,
        file: file,
        line: line,
        description: "tessera styles: " <> Exception.message(e)
  end

  @doc false
  # `~CSS"""…"""` — raw author CSS, passed through verbatim to `styles/1`.
  # Mirrors sigil_TSR: the macro receives the sigil's UNEXPANDED call AST.
  @spec sigil_CSS({:<<>>, list(), [String.t()]}, list()) :: Macro.t()
  defmacro sigil_CSS({:<<>>, _meta, [css]}, _modifiers) when is_binary(css), do: css
  defmacro sigil_CSS(css, _modifiers) when is_binary(css), do: css

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

    Spec.validate!(
      :attr,
      name,
      %{type: type, attribute: opts[:attribute], reflect: opts[:reflect]},
      file,
      line
    )

    entry =
      %{
        name: name,
        type: type,
        required: !!opts[:required],
        default: opts[:default],
        line: line
      }
      |> put_property_opts(opts)

    Module.put_attribute(consumer, :tessera_attrs, {line, entry})

    if hologram? do
      Module.put_attribute(consumer, :__props__, {name, type, [tessera_origin: :attr] ++ opts})
    end

    :ok
  end

  def record(consumer, :prop, name, type, opts, line, file, _hologram?) do
    opts = eval_opts!(opts, :prop, name, file, line)

    Spec.validate!(
      :prop,
      name,
      %{type: type, attribute: opts[:attribute], reflect: opts[:reflect]},
      file,
      line
    )

    entry =
      %{
        name: name,
        type: type,
        json: !!opts[:json],
        default: opts[:default],
        line: line
      }
      |> put_property_opts(opts)

    Module.put_attribute(consumer, :tessera_props, {line, entry})
    :ok
  end

  def record(consumer, :event, name, _type, opts, line, file, hologram?) do
    opts = eval_opts!(opts, :event, name, file, line)
    detail = opts[:detail] || %{}
    Spec.validate!(:event, name, detail, file, line)

    entry = %{name: name, detail: detail, line: line}
    # `renames:` (§5.6, brief 2d) — carried only when set so the common entry
    # shape stays byte-identical for goldens. The rename rewrite + guards run
    # in the merge (Extension.merge_spec!/3).
    entry = if opts[:renames], do: Map.put(entry, :renames, opts[:renames]), else: entry

    Module.put_attribute(consumer, :tessera_events, {line, entry})

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

  def record(consumer, :css, name, _type, opts, line, file, _hologram?) do
    opts = eval_opts!(opts, :css, name, file, line)
    Spec.validate!(:css, name, opts, file, line)

    Module.put_attribute(
      consumer,
      :tessera_css_properties,
      {line, %{name: name, default: opts[:default], line: line}}
    )

    :ok
  end

  def record(consumer, :part, name, _type, _opts, line, file, _hologram?) do
    Spec.validate!(:part, name, %{}, file, line)
    Module.put_attribute(consumer, :tessera_parts, {line, %{name: to_string(name), line: line}})
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

    Spec.validate!(
      :state,
      name,
      %{type: type, attribute: opts[:attribute], reflect: opts[:reflect]},
      file,
      line
    )

    assert_json_safe_default!(opts[:default], :state, name, file, line)

    entry =
      %{name: name, type: type, default: opts[:default], line: line}
      |> put_property_opts(opts)

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

  def record(consumer, :slot_template, name, markup, _opts, line, file, _hologram?) do
    unless is_atom(name) and Regex.match?(Naming.snake_regex(), Atom.to_string(name)) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera slot_template name #{inspect(name)} must be a snake_case atom " <>
            "(e.g. slot_template :row, …) (EXTENSION-CONTRACT.md §5.4)"
    end

    unless is_binary(markup) and markup != "" do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera slot_template #{inspect(name)} body must be a non-empty ~TSR literal string"
    end

    Module.put_attribute(
      consumer,
      :tessera_slot_templates,
      {line, %{name: name, markup: markup, line: line}}
    )

    :ok
  end

  def record(consumer, :action, name, fn_ast, opts, line, file, _hologram?) do
    opts = eval_opts!(opts, :action, name, file, line)

    unless is_atom(name) and Regex.match?(Naming.snake_regex(), Atom.to_string(name)) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera action name #{inspect(name)} must be a snake_case atom (e.g. :increment)"
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

    entry = %{name: name, fn_ast: fn_ast, line: line}
    # `internal:` annotation (EXTENSION-CONTRACT.md §5.3) — carried only when
    # set, so the common entry shape stays byte-identical for goldens.
    entry = if opts[:internal], do: Map.put(entry, :internal, true), else: entry

    Module.put_attribute(consumer, :tessera_actions, {line, entry})

    :ok
  end

  def record(consumer, :lifecycle, hook, fn_ast, _opts, line, file, _hologram?) do
    unless hook in [:should_update, :will_update, :first_updated, :updated] do
      raise CompileError,
        file: file,
        line: line,
        description: "unknown tessera lifecycle hook: #{inspect(hook)}"
    end

    unless match?({:fn, _, [{:->, _, [args, _body]}]} when length(args) == 2, fn_ast) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera #{hook} hook must be a single-clause fn with exactly two arguments — " <>
            "`fn state, changed -> ... end` (the restricted subset, " <>
            "docs/notes/spike-elixir-to-lit.md)"
    end

    {:fn, _, [{:->, _, [[_first, second], _body]}]} = fn_ast

    # The generated method declares `const changed = Object.fromEntries(...)`,
    # so the fn must bind that exact name (or an underscore-prefixed unused
    # variant: `_`, `_changed`). A var AST is a 3-tuple with an atom context —
    # patterns like %{count: c} carry a list there.
    unless match?({name, _, ctx} when is_atom(name) and is_atom(ctx), second) and
             (elem(second, 0) == :changed or
                String.starts_with?(Atom.to_string(elem(second, 0)), "_")) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera #{hook} hook's second argument must be named `changed` (or `_` / " <>
            "`_changed`) — `fn state, changed -> ... end`; it binds the changedProperties " <>
            "snapshot (patterns and other names are outside the subset)"
    end

    current = Module.get_attribute(consumer, :tessera_lifecycle) || %{}

    if Map.has_key?(current, hook) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "duplicate tessera lifecycle hook #{inspect(hook)} (already declared at line " <>
            "#{current[hook].line}) — a component declares each hook once"
    end

    Module.put_attribute(
      consumer,
      :tessera_lifecycle,
      Map.put(current, hook, %{hook: hook, fn_ast: fn_ast, line: line})
    )

    :ok
  end

  def record(consumer, :styles, entries, _type, _opts, line, file, _hologram?) do
    tag = Module.get_attribute(consumer, :tessera_tag)

    Enum.each(entries, fn
      %{kind: :css, value: css} ->
        unless is_binary(css) and css != "" do
          raise CompileError,
            file: file,
            line: line,
            description: "tessera styles css entry must be a non-empty string"
        end

        case missing_fallbacks!(css, tag, file, line) do
          [] ->
            :ok

          missing ->
            raise CompileError,
              file: file,
              line: line,
              description:
                "tessera styles: var() reads of #{Enum.join(missing, ", ")} must carry a " <>
                  "fallback so an unthemed element renders correctly " <>
                  "(EXTENSION-CONTRACT.md §7) — e.g. var(#{hd(missing)}, 8px)"
        end

        Module.put_attribute(
          consumer,
          :tessera_styles,
          {line, %{kind: :css, value: css, line: line}}
        )

      %{kind: :shared, value: path} ->
        unless is_binary(path) and path != "" do
          raise CompileError,
            file: file,
            line: line,
            description:
              "tessera styles {:shared, path} entry must carry a non-empty module path string"
        end

        Module.put_attribute(
          consumer,
          :tessera_styles,
          {line, %{kind: :shared, value: path, line: line}}
        )
    end)

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
    derived_from = Module.get_attribute(env.module, :tessera_derived_from)

    {attrs, props, events, slots, css_properties, parts, cy, lit, styles} =
      if derived_from do
        compile_derived!(env, derived_from)
      else
        compile_fresh!(env)
      end

    spec = %Spec{
      version: @contract_version,
      tag: Module.get_attribute(env.module, :tessera_tag),
      module: env.module,
      file: env.file,
      js: Module.get_attribute(env.module, :tessera_js),
      cy: cy,
      attrs: attrs,
      props: props,
      events: events,
      slots: slots,
      css_properties: css_properties,
      parts: parts,
      state: lit.state,
      actions: lit.actions,
      template: lit.template,
      styles: styles,
      lifecycle: lit.lifecycle,
      derived_from: derived_from,
      priority: Module.get_attribute(env.module, :tessera_derived_priority) || 0,
      # §8.3: element components ship 1.0.0 when neither the author declared
      # one nor a base supplied it — the first stable extension_api.
      extension_api:
        Module.get_attribute(env.module, :tessera_extension_api) ||
          Spec.default_extension_api(),
      # Template regions ride the compiled template entry (§5.4, brief 2d):
      # `regions` = what the template declares, `region_overrides` = what this
      # module replaces via slot_template.
      regions: (lit.template && lit.template[:regions]) || [],
      region_overrides: (lit.template && lit.template[:region_overrides]) || [],
      # §6.7 (brief 2f): declared via `use …, form_associated: true`; a derived
      # spec inherits the base's participation unless it declares its own
      # (additive — see validate_form_associated_option!/4).
      form_associated:
        Module.get_attribute(env.module, :tessera_form_associated) == true or
          (not is_nil(derived_from) and derived_from.__tessera_spec__().form_associated == true)
    }

    # Chain-conflict warning (§5.7, brief 2e): record this `tag: :inherit`
    # layer beside its already-compiled same-tag siblings; a same-depth
    # sibling overriding one of the same action bodies or template regions
    # warns naming both modules and the §5.9 winner. Second sibling warns;
    # compile order never hides the conflict.
    if Extension.takeover?(spec) do
      Extension.record_takeover_layer!(spec, env)
    end

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

    # Injected down-chain dispatchers (§5.3). base_init/2,3 reach the base's
    # init hooks; base_action/3 only exists for a Tier-2 base (fn-actions
    # dispatch via ES super in the lowered JS, never the BEAM).
    dispatchers =
      if derived_from do
        Extension.init_dispatcher_asts(derived_from) ++
          Extension.action_dispatcher_asts(derived_from, Enum.map(spec.actions, & &1.name))
      else
        []
      end

    quote do
      @tessera_compiled_spec unquote(Macro.escape(spec))
      unquote(body)
      unquote_splicing(dispatchers)

      # The canonical extension macro (EXTENSION-CONTRACT.md §5.3, D4): the
      # vendor module IS the macro. `use ThisModule, tag: …` expands through the
      # shared derivation layer — option validation, double-use/cycle guards,
      # inherited-prop re-emission and the internal derivation-mode use.
      @doc false
      defmacro __using__(opts) do
        Noizu.Tessera.Component.Extension.derive!(__tessera_spec__(), opts, __CALLER__)
      end
    end
  end

  # Fresh component: the author's accumulators are the whole spec.
  defp compile_fresh!(env) do
    attrs = attr_entries(env)
    props = prop_entries(env)
    events = event_entries(env)
    slots = slot_entries(env)

    css_properties =
      accumulated(env.module, :tessera_css_properties) |> Enum.map(fn {_l, e} -> e end)

    parts = accumulated(env.module, :tessera_parts) |> Enum.map(fn {_l, e} -> e end)
    cys = accumulated(env.module, :tessera_cy)

    validate_all!(attrs, props, events, slots, css_properties, parts, cys, env)

    state = accumulated(env.module, :tessera_state) |> Enum.map(fn {_l, e} -> e end)
    actions_raw = accumulated(env.module, :tessera_actions) |> Enum.map(fn {_l, e} -> e end)
    templates = accumulated(env.module, :tessera_template)
    lifecycle_raw = Module.get_attribute(env.module, :tessera_lifecycle) || %{}
    template = assert_single_template!(templates, state, actions_raw, lifecycle_raw, env)

    assert_no_slot_templates_on_fresh!(accumulated(env.module, :tessera_slot_templates), env)

    lit =
      lit_compile!(
        attrs,
        props,
        events,
        state,
        actions_raw,
        template,
        lifecycle_raw,
        env,
        false,
        MapSet.new(),
        [],
        []
      )

    styles = accumulated(env.module, :tessera_styles) |> Enum.map(fn {_l, e} -> e end)

    cy = cys != [] && elem(List.last(cys), 1)
    {attrs, props, events, slots, css_properties, parts, cy, lit, styles}
  end

  # Derived component (`use Base, tag: …`): merge the base spec with the
  # author's deltas, then validate + translate the MERGED declarations so
  # inherited keys resolve in the derived template/actions (§5.5).
  defp compile_derived!(env, base_module) do
    base_spec = base_module.__tessera_spec__()

    attrs = attr_entries(env)
    props = prop_entries(env)
    events = event_entries(env)
    slots = slot_entries(env)

    css_properties =
      accumulated(env.module, :tessera_css_properties) |> Enum.map(fn {_l, e} -> e end)

    parts = accumulated(env.module, :tessera_parts) |> Enum.map(fn {_l, e} -> e end)
    cys = accumulated(env.module, :tessera_cy)

    state = accumulated(env.module, :tessera_state) |> Enum.map(fn {_l, e} -> e end)
    actions_raw = accumulated(env.module, :tessera_actions) |> Enum.map(fn {_l, e} -> e end)
    lifecycle_raw = Module.get_attribute(env.module, :tessera_lifecycle) || %{}
    styles = accumulated(env.module, :tessera_styles) |> Enum.map(fn {_l, e} -> e end)
    template = author_template!(accumulated(env.module, :tessera_template), env)

    deltas = %{
      attrs: attrs,
      props: props,
      events: events,
      slots: slots,
      css_properties: css_properties,
      parts: parts,
      state: state,
      actions: actions_raw,
      template: template,
      lifecycle: lifecycle_raw,
      styles: styles,
      cy: cys != [] && elem(List.last(cys), 1)
    }

    merged = Extension.merge_spec!(base_spec, deltas, env)

    validate_all!(
      merged.attrs,
      merged.props,
      merged.events,
      merged.slots,
      merged.css_properties,
      merged.parts,
      cys,
      env
    )

    slot_templates =
      accumulated(env.module, :tessera_slot_templates) |> Enum.map(fn {_l, e} -> e end)

    validate_region_overrides!(base_spec, slot_templates, merged.template, env)

    lit =
      lit_compile!(
        merged.attrs,
        merged.props,
        merged.events,
        merged.state,
        merged.actions,
        merged.template,
        merged.lifecycle,
        env,
        true,
        MapSet.new(Enum.map(base_spec.actions, & &1.name)),
        slot_templates,
        base_spec.regions
      )

    {merged.attrs, merged.props, merged.events, merged.slots, merged.css_properties, merged.parts,
     merged.cy, lit, merged.styles}
  end

  # The author's own template (0 or 1). A derived module may omit it and inherit
  # the base's; the all-or-nothing element check is satisfied by the merge.
  defp author_template!(templates, env) do
    case templates do
      [] ->
        nil

      [{line, markup}] ->
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
        |> put_property_opts(opts)
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

  # Translate state/action/template declarations into their spec shapes: action
  # fn ASTs become JS bodies (restricted subset — anything outside raises
  # CompileError naming the construct), the template markup becomes the
  # pre-rendered lit-html render() string. `derived?` enables the base_action
  # down-call + state rebinding subset forms; inherited entries (marked by the
  # merge) pass their already-translated JS through untouched.
  #
  # `region_overrides` (slot_template payloads) + `base_regions` drive the
  # region method assembly (brief 2d, §5.4): a fresh component compiles all
  # default region bodies; a derived one compiles its overrides plus any
  # newly-declared regions, letting the rest ride the ES class chain.
  defp lit_compile!(
         attrs,
         props,
         events,
         state,
         actions_raw,
         template,
         lifecycle_raw,
         env,
         derived?,
         base_action_names,
         region_overrides,
         base_regions
       ) do
    assert_no_duplicates!(:state, state, env)
    assert_no_action_duplicates!(actions_raw, env)

    ctx = %Expr{
      state_keys: MapSet.new(Enum.map(state, & &1.name)),
      attrs: Map.new(attrs, &{&1.name, &1.type}),
      props: Map.new(props, &{&1.name, &1.type}),
      events: MapSet.new(Enum.map(events, & &1.name)),
      actions: MapSet.new(Enum.map(actions_raw, & &1.name)),
      derived?: derived?,
      inherited_actions: base_action_names,
      module: env.module,
      file: env.file,
      line: 0
    }

    actions =
      Enum.map(actions_raw, fn entry ->
        js =
          if entry[:inherited] do
            entry.js
          else
            Expr.translate_action(entry.fn_ast, %{ctx | line: entry.line || 0})
          end

        # `internal:` rides the translated entry (advisory CEM grouping + the
        # runtime's warn-on-interception); carried from inherited entries so a
        # redeclaration MAY flip it (§5.3, §8.2). `re_emit:` (§5.6 rename) is
        # carried too — without it the derived class would skip shadowing the
        # base action whose rewritten JS lives in this very entry.
        %{name: entry.name, js: js, fn_ast: entry[:fn_ast], line: entry.line}
        |> then(fn e -> if entry[:internal], do: Map.put(e, :internal, true), else: e end)
        |> then(fn e -> if entry[:inherited], do: Map.put(e, :inherited, true), else: e end)
        |> then(fn e -> if entry[:re_emit], do: Map.put(e, :re_emit, true), else: e end)
      end)

    lifecycle =
      Map.new(lifecycle_raw, fn {hook, entry} ->
        js =
          if entry[:inherited] do
            entry.js
          else
            lifecycle_js(entry, %{ctx | line: entry.line || 0})
          end

        {hook,
         %{js: js, line: entry.line}
         |> then(fn e -> if entry[:inherited], do: Map.put(e, :inherited, true), else: e end)
         |> then(fn e -> if entry[:re_emit], do: Map.put(e, :re_emit, true), else: e end)}
      end)

    template_entry =
      template &&
        with {:ok, tree} <- Template.parse(template.markup) do
          rctx = %{ctx | line: template.line}

          %{
            raw: template.markup,
            lexer: Template.lexer_for(template.markup),
            render_js: Template.to_lit_render(tree, rctx),
            regions: Template.regions(tree),
            line: template.line
          }
          |> Map.put(
            :region_methods,
            compile_region_payload(tree, rctx, derived?, region_overrides, base_regions)
          )
          |> Map.put(:region_overrides, Enum.map(region_overrides, & &1.name))
        else
          {:error, msg} ->
            raise CompileError,
              file: env.file,
              line: template.line,
              description: "tessera template: " <> msg
        end

    %{state: state, actions: actions, template: template_entry, lifecycle: lifecycle}
  end

  # Region method assembly (§5.4, brief 2d).
  #
  #   * Fresh: every declared region's default body compiles into a method on
  #     the element class.
  #   * Derived: only slot_template overrides plus any region newly declared by
  #     an author-replaced template are emitted — every other region rides the
  #     ES class chain (the base already defines `__region_<name>()`). The
  #     dedup keeps the LAST definition, so an explicit `slot_template :cell`
  #     wins over a same-named nested region inside another override body.
  defp compile_region_payload(tree, ctx, false, _overrides, _base_regions) do
    Template.compile_region_methods(tree, ctx)
  end

  defp compile_region_payload(tree, ctx, true, overrides, base_regions) do
    override_methods =
      Enum.flat_map(overrides, fn %{name: name, markup: markup, line: line} ->
        # validate_region_overrides!/4 already parsed the body (unknown-region +
        # nested-set guards); this re-parse carries the override's line for
        # emission-time CompileErrors (unknown keys, stray {%super%}…).
        case Template.parse(markup) do
          {:ok, body} ->
            octx = %{ctx | line: line}

            Template.compile_region_methods(body, octx) ++
              [Template.compile_region_override(name, body, octx)]

          {:error, msg} ->
            raise CompileError,
              file: ctx.file,
              line: line,
              description: "tessera slot_template #{inspect(name)}: " <> msg
        end
      end)

    base_names = MapSet.new(Enum.map(base_regions, & &1.name))
    overridden = MapSet.new(Enum.map(overrides, & &1.name))

    new_defaults =
      tree
      |> Template.compile_region_methods(ctx)
      |> Enum.reject(fn m ->
        MapSet.member?(base_names, m.name) or MapSet.member?(overridden, m.name)
      end)

    (new_defaults ++ override_methods)
    |> Enum.reverse()
    |> Enum.uniq_by(& &1.name)
    |> Enum.reverse()
  end

  defp assert_no_slot_templates_on_fresh!([], _env), do: :ok

  defp assert_no_slot_templates_on_fresh!([{line, %{name: name}} | _], env) do
    raise CompileError,
      file: env.file,
      line: line,
      description:
        "tessera slot_template #{inspect(name)} on a fresh component — region overrides " <>
          "require a base (`use Base, tag: …`); a fresh template declares regions with " <>
          "{%region :name}…{%endregion} (EXTENSION-CONTRACT.md §5.4)"
  end

  # slot_template validation against the base's compiled regions (§5.7):
  #   * the base declares no regions at all → CompileError (use the base's own
  #     templates, not region overrides);
  #   * unknown region name → CompileError naming the base's declared regions;
  #   * the override body changes the nested region set → region mismatch
  #     CompileError;
  #   * a region declared twice in the same derived module → CompileError.
  defp validate_region_overrides!(base_spec, overrides, merged_template, env) do
    unless overrides == [] do
      base_regions = base_spec.regions

      if base_regions == [] do
        raise CompileError,
          file: env.file,
          line: env.line,
          description:
            "tessera slot_template used, but base #{inspect(base_spec.module)} declares no " <>
              "template regions — the base template must opt in with {%region :name}…{%endregion} " <>
              "(EXTENSION-CONTRACT.md §5.4)"
      end

      dups =
        overrides
        |> Enum.map(& &1.name)
        |> Enum.frequencies()
        |> Enum.filter(fn {_n, c} -> c > 1 end)

      if dups != [] do
        raise CompileError,
          file: env.file,
          line: env.line,
          description:
            "duplicate tessera slot_template override(s) #{inspect(Enum.map(dups, &elem(&1, 0)))} — " <>
              "a region is overridden once (EXTENSION-CONTRACT.md §5.4)"
      end

      base_by_name = Map.new(base_regions, &{&1.name, &1})

      Enum.each(overrides, fn %{name: name, markup: markup, line: line} ->
        case Map.fetch(base_by_name, name) do
          :error ->
            raise CompileError,
              file: env.file,
              line: line,
              description:
                "unknown override: tessera slot_template #{inspect(name)} — base " <>
                  "#{inspect(base_spec.module)} declares no region #{inspect(name)} " <>
                  "(its regions: #{inspect(Enum.map(base_regions, & &1.name))}) " <>
                  "(EXTENSION-CONTRACT.md §5.7)"

          {:ok, base_region} ->
            case Template.parse(markup) do
              {:error, msg} ->
                raise CompileError,
                  file: env.file,
                  line: line,
                  description: "tessera slot_template #{inspect(name)}: " <> msg

              {:ok, body} ->
                got = body |> Template.regions() |> Enum.map(& &1.name) |> Enum.sort()
                want = base_region.nested |> Enum.sort()

                if got != want do
                  raise CompileError,
                    file: env.file,
                    line: line,
                    description:
                      "region mismatch: the override of #{inspect(name)} changes the nested " <>
                        "region set — base declares #{inspect(want)}, the override declares " <>
                        "#{inspect(got)} (EXTENSION-CONTRACT.md §5.7)"
                end
            end
        end
      end)
    end

    warn_dead_regions!(base_spec, merged_template, env)
    :ok
  end

  # Whole-template replacement discards the base's region structure (§5.4 gotcha):
  # warn once per dropped region name. `nil` merged template ⇒ the base template
  # is inherited byte-identically — nothing dead.
  defp warn_dead_regions!(_base_spec, nil, _env), do: :ok

  defp warn_dead_regions!(base_spec, merged_template, env) do
    if base_spec.regions != [] and merged_template.markup != base_spec.template.raw do
      new_region_names =
        case Template.parse(merged_template.markup) do
          {:ok, tree} -> MapSet.new(Enum.map(Template.regions(tree), & &1.name))
          {:error, _} -> MapSet.new()
        end

      dead =
        base_spec.regions
        |> Enum.reject(fn r -> MapSet.member?(new_region_names, r.name) end)
        |> Enum.map(& &1.name)

      if dead != [] do
        IO.warn(
          "tessera derived #{inspect(env.module)} replaces the base template — inherited " <>
            "regions #{inspect(dead)} no longer render and any slot_template overrides for " <>
            "them are dead surface (the derived CEM keeps the inherited event surface, " <>
            "EXTENSION-CONTRACT.md §5.4)",
          file: env.file,
          line: env.line
        )
      end
    end

    :ok
  end

  # Lifecycle hooks reuse the action subset. The second fn argument is
  # normalized to `changed` (the record guard admits `changed`, `_` and
  # underscore-prefixed variants) — the generated method declares
  # `const changed = Object.fromEntries(...)`, so the translated body reads
  # that exact binding.
  defp lifecycle_js(%{fn_ast: {:fn, meta, [{:->, arrow_meta, [[first, second], body]}]}}, ctx) do
    normalized =
      {:fn, meta, [{:->, arrow_meta, [[first, {:changed, elem(second, 1), nil}], body]}]}

    Expr.translate_action(normalized, ctx)
  end

  # Property options (attribute rename/disable, reflect) ride the entry maps
  # only when declared — absent opts keep the pre-1c entry shapes byte-stable.
  defp put_property_opts(entry, opts) do
    entry
    |> then(fn e ->
      if Keyword.has_key?(opts, :attribute), do: Map.put(e, :attribute, opts[:attribute]), else: e
    end)
    |> then(fn e ->
      if Keyword.has_key?(opts, :reflect), do: Map.put(e, :reflect, opts[:reflect]), else: e
    end)
  end

  defp assert_single_template!(templates, state, actions_raw, lifecycle_raw, env) do
    case templates do
      [] ->
        if state != [] or actions_raw != [] or lifecycle_raw != %{} do
          raise CompileError,
            file: env.file,
            line: 0,
            description:
              "tessera state/action/lifecycle declarations require a matching template ~TSR " <>
                "declaration (the element DSL is all-or-nothing: state + actions + template)"
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
        IO.warn(
          "[tessera] could not write #{spec.tag}.element.generated.mjs: #{inspect(reason)}",
          []
        )

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

  defp validate_all!(attrs, props, events, slots, css_properties, parts, cys, env) do
    # Full contract re-validation over the final entries. The DSL macros
    # validate at record time, but in Hologram mode `prop` lines go through
    # Hologram's own macro and only land here.
    Enum.each(attrs, fn entry ->
      Spec.validate!(
        :attr,
        entry.name,
        %{type: entry.type, attribute: entry[:attribute], reflect: entry[:reflect]},
        env.file,
        entry.line
      )
    end)

    Enum.each(props, fn entry ->
      Spec.validate!(
        :prop,
        entry.name,
        %{type: entry.type, attribute: entry[:attribute], reflect: entry[:reflect]},
        env.file,
        entry.line || 0
      )
    end)

    Enum.each(css_properties, fn entry ->
      Spec.validate!(:css, entry.name, [default: entry[:default]], env.file, entry.line || 0)
    end)

    Enum.each(parts, fn entry ->
      Spec.validate!(:part, entry.name, %{}, env.file, entry.line || 0)
    end)

    assert_no_duplicates!(:attr, attrs, env)
    assert_no_duplicates!(:prop, props, env)
    assert_no_duplicates!(:event, events, env)
    assert_no_duplicates!(:slot, slots, env)
    assert_no_duplicates!(:css, css_properties, env)
    assert_no_duplicates!(:part, parts, env)

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

    # Each event generates an `on_<event>` binding prop (CONTRACT.md §1). An
    # author-declared prop — or attr, which becomes a Hologram prop too —
    # with that same name would silently share the wire slot, so reject the
    # collision at compile time with the component + name pointed out.
    author_names = MapSet.union(prop_names, attr_names)

    Enum.each(events, fn event ->
      binding = Naming.event_binding_prop(event.name)

      if MapSet.member?(author_names, binding) do
        entry = Enum.find(attrs ++ props, fn e -> e.name == binding end)

        line =
          case entry do
            %{line: l} when is_integer(l) and l > 0 -> l
            _ -> event.line || 0
          end

        raise CompileError,
          file: env.file,
          line: line,
          description:
            "tessera component #{inspect(env.module)}: event #{inspect(event.name)} generates " <>
              "binding prop #{inspect(binding)}, which collides with the author-declared " <>
              "prop/attr of the same name — rename the prop/attr or the event (CONTRACT.md §1)"
      end
    end)

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

  # §8.3 declaration lane: `use Noizu.Tessera.Component, extension_api: "1.0.0"`
  # must be an EXACT literal semver version — the version this element PROVIDES.
  # Requirement ranges (`~> 1.0`, `^1.0.0`) are PINS and belong on the
  # derivation `use Base, extension_api:` (Extension.check_pin!/3).
  defp validate_extension_api_option!(nil, _file, _line), do: :ok

  defp validate_extension_api_option!(value, file, line) do
    unless is_binary(value) and match?({:ok, _}, Version.parse(value)) do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera :extension_api option must be an exact literal semver version " <>
            "(e.g. \"1.0.0\") — requirement ranges like \"~> 1.0\" are pins and belong " <>
            "on `use Base, extension_api:` (EXTENSION-CONTRACT.md §8.3/§8.4), got: " <>
            "#{inspect(value)}"
    end
  end

  # §6.7 declaration lane (brief 2f): `use Noizu.Tessera.Component,
  # form_associated: true` opts the element into form participation. Only
  # `true` is meaningful (the default is false and participation is additive —
  # a deriving module cannot silently UN-declare its base's participation), so
  # `false` is accepted and treated as unset; anything else fails compilation.
  defp validate_form_associated_option!(nil, _file, _line), do: :ok
  defp validate_form_associated_option!(false, _file, _line), do: :ok

  defp validate_form_associated_option!(value, file, line) do
    unless value == true do
      raise CompileError,
        file: file,
        line: line,
        description:
          "tessera :form_associated option must be a boolean (true to declare form " <>
            "participation per EXTENSION-CONTRACT.md §6.7), got: #{inspect(value)}"
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
