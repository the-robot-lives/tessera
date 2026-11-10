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
    do: [attr: 2, attr: 3, prop: 2, prop: 3, event: 1, event: 2, slot: 1, cy: 1]

  defp import_list(true),
    # prop/2-3 come from Hologram.Component's import when Hologram is loaded.
    do: [attr: 2, attr: 3, event: 1, event: 2, slot: 1, cy: 1]

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
      slots: slots
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
      nil -> :ok
      %Spec{} = spec -> Adapter.write_contract_next_to_mjs(spec)
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
