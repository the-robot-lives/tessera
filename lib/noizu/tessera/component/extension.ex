defmodule Noizu.Tessera.Component.Extension do
  @moduledoc """
  The shared Elixir derivation layer behind `use Vendor.Element, tag: …`
  (EXTENSION-CONTRACT.md §5). Runtime-agnostic on purpose: Tier 1 (compiled to
  Lit) uses it now, and Tier 2 (Hologram-in-element, brief 3f) reuses the same
  merge + dispatcher generation — the spec is the single interface between
  definition and runtime (§9).

  Responsibilities:

    * `derive!/3` — the expansion of the base module's generated `__using__/1`
      macro: option validation (`tag:` / `:inherit` / `priority:` /
      `extension_api:`), the double-`use` and cycle guards, and the AST that
      re-emits the inherited Hologram props and internally `use`s
      `Noizu.Tessera.Component` in derivation mode;
    * `merge_spec!/3` — deep-copy the base spec's declarations and layer the
      derived module's deltas: additive new names append in declaration order,
      override-by-name replaces wholesale, removal is forbidden, `required:`
      may relax not tighten, and the collision/duplicate/round-trip/reserved
      checks re-run over the MERGED spec (the caller runs `validate_all!`);
    * `check_pin!/3` — the §8 extension-api semver pin (major mismatch raises,
      minor-range mismatch warns);
    * dispatcher generation — `base_init/2,3` (init hooks) and the
      `base_action/3` scaffolding Tier 2 consumes. Hologram's IR has no
      `super`, so the Elixir down-call is an injected dispatcher, never
      language-level `super`. Tier-1 fn-actions never compile to the BEAM;
      their down-call is real ES `super` in the lowered JS (see
      `Noizu.Tessera.Component.Expr`), so no BEAM `base_action/3` is generated
      for them.

  Inherited entries in a merged spec carry `inherited: true`; the derived
  module's own (new or overriding) entries do not. The Lit lowering uses that
  marker to emit only new/overridden members and inherit the rest through the
  ES class chain.
  """

  alias Noizu.Tessera.Naming
  alias Noizu.Tessera.Spec

  @default_extension_api "1.0.0"

  # -- the __using__ expansion -------------------------------------------------

  @doc """
  Builds the AST spliced into a deriving module by the base module's generated
  `__using__/1`. `base_spec` is the base module's compiled spec; `opts` are the
  raw `use Base, …` options (AST); `caller` is the deriving module's env.

  Validates at expansion time (pointed `CompileError`s, §5.7) and returns code
  that flags the module as derived, internally `use`s
  `Noizu.Tessera.Component`, and re-emits the inherited Hologram props so the
  adapter's `@__props__` accumulator is complete before Hologram's
  `__before_compile__` runs.
  """
  @spec derive!(Spec.t(), keyword(), Macro.Env.t()) :: Macro.t()
  def derive!(%Spec{} = base_spec, opts, %Macro.Env{} = caller) do
    opts = eval_opts!(opts, caller)
    base = base_spec.module

    guard_double_use!(caller)
    guard_cycle!(base_spec, caller)

    {tag, inherit?} = resolve_tag!(Keyword.get(opts, :tag), base_spec, caller)
    priority = resolve_priority!(Keyword.get(opts, :priority, 0), caller)
    pin = Keyword.get(opts, :extension_api)
    base_api = base_spec.extension_api || @default_extension_api
    check_pin!(base_api, pin, caller)
    extension_api = pin || base_api

    js = resolve_js!(Keyword.get(opts, :js), tag, base_spec, inherit?, caller)

    # Set at EXPANSION time so the double-use guard in a later
    # `use Noizu.Tessera.Component` expansion sees the flag (quoted
    # Module.put_attribute calls evaluate only after nested macro expansion).
    Module.put_attribute(caller.module, :tessera_derived_from, base)
    Module.put_attribute(caller.module, :tessera_derived_priority, priority)
    Module.put_attribute(caller.module, :tessera_extension_api, extension_api)

    quote do
      # Internally a normal component in derivation mode. The private
      # `__derived__` opt lifts the double-use guard for THIS use only — an
      # author-written `use Noizu.Tessera.Component` still trips it.
      use Noizu.Tessera.Component,
        tag: unquote(tag),
        js: unquote(js),
        __derived__: true

      unquote_splicing(hologram_reemit_asts(base_spec))
    end
  end

  # The author already `use Noizu.Tessera.Component` (tag accumulator present)
  # before `use Base` — §5.1 forbids repeating the compiler.
  defp guard_double_use!(caller) do
    if Module.has_attribute?(caller.module, :tessera_tag) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera double use: #{inspect(caller.module)} already used " <>
            "Noizu.Tessera.Component — a deriving module must not repeat it " <>
            "(EXTENSION-CONTRACT.md §5.1); `use Base, tag: …` IS the compiler"
    end

    :ok
  end

  # An :inherit chain (or any derivation) that revisits the deriving module is
  # a cycle (§5.9). Single-level derivation walks the base's derived_from spine.
  defp guard_cycle!(%Spec{} = base_spec, caller) do
    spine =
      base_spec
      |> Stream.iterate(fn s -> s.derived_from && s.derived_from.__tessera_spec__() end)
      |> Enum.take_while(& &1)
      |> Enum.map(& &1.module)

    if caller.module in spine do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera derivation cycle: #{inspect(caller.module)} already appears in the " <>
            "extension chain of #{inspect(base_spec.module)} (EXTENSION-CONTRACT.md §5.9)"
    end

    :ok
  end

  defp resolve_tag!(nil, _base_spec, caller) do
    raise CompileError,
      file: caller.file,
      line: caller.line,
      description:
        "tessera derivation requires `tag:` — a fresh tag literal " <>
          "(matching #{inspect(Naming.tag_regex())} and differing from the base tag) " <>
          "or `tag: :inherit` for a tag takeover (EXTENSION-CONTRACT.md §5.9)"
  end

  defp resolve_tag!(:inherit, base_spec, caller) do
    # Single-level takeover: register under the base tag in the extending app.
    # The full multi-layer chain (priority order, conflict warnings) is brief 2e.
    guard_inherit_location!(base_spec, caller)
    {base_spec.tag, true}
  end

  defp resolve_tag!(tag, base_spec, caller) when is_binary(tag) do
    Spec.validate!(:tag, tag, %{}, caller.file, caller.line)

    if tag == base_spec.tag do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera derived tag #{inspect(tag)} equals the base tag — a fresh tag must " <>
            "differ from the base (EXTENSION-CONTRACT.md §5.9); use `tag: :inherit` " <>
            "for a tag takeover"
    end

    {tag, false}
  end

  defp resolve_tag!(other, _base_spec, caller) do
    raise CompileError,
      file: caller.file,
      line: caller.line,
      description:
        "tessera derivation `tag:` must be a fresh tag literal or :inherit, got: " <>
          inspect(other)
  end

  # `tag: :inherit` emits the merged spec under the BASE tag. Writing those
  # artifacts into the base's own directory would clobber the vendor's files —
  # the extending app must live elsewhere (§5.8: vendor artifacts untouched).
  defp guard_inherit_location!(%Spec{file: base_file}, caller) when is_binary(base_file) do
    if Path.expand(Path.dirname(base_file)) == Path.expand(Path.dirname(caller.file)) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera `tag: :inherit` in the base module's own directory would overwrite " <>
            "the vendor's generated artifacts — move the extension into the extending " <>
            "app (EXTENSION-CONTRACT.md §5.8)"
    end

    :ok
  end

  defp guard_inherit_location!(_base_spec, _caller), do: :ok

  defp resolve_priority!(priority, _caller) when is_integer(priority), do: priority

  defp resolve_priority!(other, caller) do
    raise CompileError,
      file: caller.file,
      line: caller.line,
      description:
        "tessera derivation `priority:` must be an integer (higher sits further out " <>
          "in the §5.9 chain), got: #{inspect(other)}"
  end

  # js defaults to the derived tag's snake wrapper. A fresh tag always gets its
  # own wrapper; :inherit reuses the base tag's naming in the extending app.
  defp resolve_js!(nil, tag, _base_spec, _inherit?, _caller),
    do: String.replace(tag, "-", "_") <> ".mjs"

  defp resolve_js!(js, _tag, _base_spec, _inherit?, caller) when is_binary(js) do
    unless Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9._-]*\.mjs$/, js) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera :js option must be a plain colocated filename ending in .mjs " <>
            "(e.g. \"persona_card.mjs\"), got: #{inspect(js)}"
    end

    js
  end

  defp resolve_js!(other, _tag, _base_spec, _inherit?, caller) do
    raise CompileError,
      file: caller.file,
      line: caller.line,
      description: "tessera :js option must be a string filename, got: #{inspect(other)}"
  end

  # In Hologram mode the inherited attrs/props/binding-props must reach
  # Hologram's @__props__ accumulator during body expansion (before its
  # __before_compile__). Inherited props carry `tessera_origin: :inherited` so
  # the compiler's prop_entries/1 excludes them from the AUTHOR deltas (they
  # come from the base spec in the merge) while Hologram still sees them.
  defp hologram_reemit_asts(%Spec{} = base_spec) do
    if Noizu.Tessera.Hologram.Adapter.available?() do
      entries =
        Enum.map(base_spec.attrs, fn a ->
          opts = [tessera_origin: :attr, required: !!a[:required], default: a[:default]]
          opts = put_opt(opts, :attribute, a[:attribute])
          opts = put_opt(opts, :reflect, a[:reflect])
          {a.name, a.type, opts}
        end) ++
          Enum.map(base_spec.props, fn p ->
            opts = [tessera_origin: :inherited, json: !!p[:json], default: p[:default]]
            opts = put_opt(opts, :attribute, p[:attribute])
            opts = put_opt(opts, :reflect, p[:reflect])
            {p.name, p.type, opts}
          end) ++
          Enum.map(base_spec.events, fn e ->
            {Naming.event_binding_prop(e.name), :any, [tessera_origin: :binding, default: nil]}
          end)

      Enum.map(entries, fn {name, type, opts} ->
        quote do
          Module.put_attribute(__MODULE__, :__props__, {unquote(name), unquote(type), unquote(opts)})
        end
      end)
    else
      []
    end
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: opts ++ [{key, value}]

  # -- merged spec -------------------------------------------------------------

  @doc """
  Deep-copies the base spec's declarations and layers the derived module's
  `deltas` (a map of raw author entries keyed by kind). Returns a merged
  declaration map the caller feeds through `validate_all!` + the element
  translator. Inherited entries carry `inherited: true`.

  Rules (§5.5): additive new names append in declaration order; override-by-name
  replaces wholesale (events merge detail, keeping inherited keys); removal is
  forbidden; `required:` may relax not tighten. Duplicate AUTHOR declarations
  raise here (the merge would otherwise silently last-wins them).
  """
  @spec merge_spec!(Spec.t(), map(), Macro.Env.t()) :: map()
  def merge_spec!(%Spec{} = base_spec, deltas, %Macro.Env{} = env) do
    merged =
      Map.new(list_kinds(), fn kind ->
        base_entries = Map.get(base_spec, kind, [])
        author_entries = Map.get(deltas, kind, [])
        assert_author_duplicates!(kind, author_entries, env)
        {kind, merge_entries(kind, base_entries, author_entries, env)}
      end)

    merged =
      merged
      |> Map.put(:styles, mark_inherited(base_spec.styles) ++ Map.get(deltas, :styles, []))
      |> Map.put(:template, merge_template(base_spec, deltas))
      |> Map.put(:lifecycle, merge_lifecycle(base_spec, deltas))
      |> Map.put(:cy, Map.get(deltas, :cy) || base_spec.cy)

    assert_no_removal!(base_spec, merged, env)
    merged
  end

  defp list_kinds,
    do: [:attrs, :props, :events, :slots, :css_properties, :parts, :state, :actions]

  defp mark_inherited(entries), do: Enum.map(entries, &Map.put(&1, :inherited, true))

  defp merge_entries(kind, base_entries, author_entries, env) do
    base_index = Map.new(base_entries, &{&1.name, &1})
    base_names = MapSet.new(Map.keys(base_index))

    # Inherited entries first (declaration order), then layer author deltas.
    initial = mark_inherited(base_entries)

    {merged, _seen} =
      Enum.reduce(author_entries, {initial, base_names}, fn entry, {acc, seen} ->
        cond do
          MapSet.member?(seen, entry.name) ->
            # override-by-name: replace the inherited entry in place
            replaced = maybe_guard_required!(kind, base_index[entry.name], entry, env)
            replaced = merge_entry_detail(kind, base_index[entry.name], replaced)
            {replace_by_name(acc, entry.name, replaced), seen}

          true ->
            # additive new name (a second author declaration of a NEW name is
            # caught by assert_author_duplicates! above)
            {acc ++ [entry], MapSet.put(seen, entry.name)}
        end
      end)

    merged
  end

  defp replace_by_name(entries, name, replacement),
    do: Enum.map(entries, fn e -> if e.name == name, do: replacement, else: e end)

  # `required:` may relax (true → false) not tighten (false → true) — §5.5.
  defp maybe_guard_required!(:attrs, %{required: false}, %{required: true} = entry, env) do
    raise CompileError,
      file: env.file,
      line: entry.line || 0,
      description:
        "tessera derived attr #{inspect(entry.name)} tightens `required:` from false to " <>
          "true — inherited required may only relax (EXTENSION-CONTRACT.md §5.5)"
  end

  defp maybe_guard_required!(_kind, _base, entry, _env), do: entry

  # Events keep inherited detail keys; the author may extend (§5.6). The
  # narrowing/retype guard is brief 2d — merging inherited keys back in means a
  # redeclare cannot drop them by construction.
  defp merge_entry_detail(:events, %{detail: base_detail}, entry) do
    Map.put(entry, :detail, Map.merge(base_detail || %{}, entry[:detail] || %{}))
  end

  defp merge_entry_detail(_kind, _base, entry), do: entry

  defp merge_template(base_spec, deltas) do
    case Map.get(deltas, :template) do
      nil ->
        base_spec.template && %{line: base_spec.template.line, markup: base_spec.template.raw}

      %{line: line, markup: markup} ->
        %{line: line, markup: markup}
    end
  end

  defp merge_lifecycle(base_spec, deltas) do
    base = Map.new(base_spec.lifecycle, fn {hook, e} -> {hook, Map.put(e, :inherited, true)} end)
    author = Map.get(deltas, :lifecycle, %{})
    Map.merge(base, author)
  end

  defp assert_author_duplicates!(kind, entries, env) do
    entries
    |> Enum.group_by(& &1.name)
    |> Enum.each(fn {name, group} ->
      if length(group) > 1 do
        raise CompileError,
          file: env.file,
          line: hd(Enum.map(group, &(&1.line || 0))),
          description:
            "duplicate tessera #{kind} #{inspect(name)} in the deriving module " <>
              "(declared at lines #{inspect(Enum.map(group, &(&1.line || 0)))})"
      end
    end)
  end

  # Removal is forbidden (§5.5): every inherited name must persist. The merge
  # only adds/replaces, so this is an invariant guard — it fires if a future
  # removal syntax ever drops a name.
  defp assert_no_removal!(base_spec, merged, env) do
    Enum.each(list_kinds(), fn kind ->
      merged_names = MapSet.new(Enum.map(merged[kind], & &1.name))

      Enum.each(Map.get(base_spec, kind, []), fn entry ->
        unless MapSet.member?(merged_names, entry.name) do
          raise CompileError,
            file: env.file,
            line: 0,
            description:
              "tessera derived spec dropped inherited #{kind} #{inspect(entry.name)} — " <>
                "removal of inherited surface is forbidden (EXTENSION-CONTRACT.md §5.5)"
        end
      end)
    end)
  end

  # -- extension-api pin (§8) --------------------------------------------------

  @doc """
  Checks a derived `extension_api:` pin against the base's declared version.
  Unsatisfied MAJOR raises `CompileError`; an unsatisfied minor range warns
  (host policy decides whether to fail). `nil` requirement is a no-op. A base
  that declares no version is treated as the first stable `1.0.0`.
  """
  @spec check_pin!(String.t() | nil, String.t() | nil, Macro.Env.t()) :: :ok
  def check_pin!(_base_version, nil, _env), do: :ok

  def check_pin!(base_version, requirement, env) when is_binary(requirement) do
    base = base_version || @default_extension_api
    normalized = normalize_requirement!(requirement, env)

    unless Version.match?(base, normalized) do
      base_major = major_of(base)
      req_major = major_of_requirement(requirement)

      if base_major != req_major do
        raise CompileError,
          file: env.file,
          line: env.line,
          description:
            "tessera extension_api pin #{inspect(requirement)} is not satisfied by the " <>
              "base's #{inspect(base)} — MAJOR mismatch is a breaking change " <>
              "(EXTENSION-CONTRACT.md §8.4)"
      else
        IO.warn(
          "tessera extension_api pin #{inspect(requirement)} is not satisfied by the " <>
            "base's #{inspect(base)} (minor range) — the base declares #{inspect(base)}; " <>
            "review compatibility (EXTENSION-CONTRACT.md §8.4)",
          file: env.file,
          line: env.line
        )
      end
    end

    :ok
  end

  def check_pin!(_base_version, other, env) do
    raise CompileError,
      file: env.file,
      line: env.line,
      description: "tessera extension_api pin must be a semver requirement string, got: #{inspect(other)}"
  end

  # Elixir's Version understands "~> x.y" / exact, not npm's caret. "^x.y.z"
  # (>= x.y.z, < (x+1).0.0) normalizes to "~> x.y".
  defp normalize_requirement!("^" <> rest, env) do
    case String.split(rest, ".") do
      [major, minor | _] -> "~> #{major}.#{minor}"
      _ -> raise_bad_requirement!(rest, env)
    end
  end

  defp normalize_requirement!(requirement, env) do
    case Version.parse_requirement(requirement) do
      {:ok, _} -> requirement
      :error -> raise_bad_requirement!(requirement, env)
    end
  end

  defp raise_bad_requirement!(requirement, env) do
    raise CompileError,
      file: env.file,
      line: env.line,
      description:
        "tessera extension_api pin #{inspect(requirement)} is not a valid semver " <>
          "requirement (use \"~> 1.0\", \"^1.0.0\" or an exact version)"
  end

  defp major_of(version) do
    version |> String.split(".") |> hd() |> String.to_integer()
  end

  defp major_of_requirement(requirement) do
    case Regex.run(~r/\d+/, requirement) do
      [digits] -> String.to_integer(digits)
      _ -> 0
    end
  end

  # -- dispatcher generation ---------------------------------------------------

  @doc """
  Injected init-hook dispatchers for a deriving module: `base_init/2` and
  `base_init/3` reach the base module's (possibly overridden)
  `__tessera_init__/2,3`. The derived module's own `__tessera_init__` defaults
  dispatch through these, so an unoverridden hook still runs the base's init
  (§5.3). Names mirror `base_action/3` (T1-2 resolved).
  """
  @spec init_dispatcher_asts(module()) :: [Macro.t()]
  def init_dispatcher_asts(base_module) do
    [
      quote do
        @doc false
        def base_init(props, component),
          do: unquote(base_module).__tessera_init__(props, component)

        @doc false
        def base_init(props, component, server),
          do: unquote(base_module).__tessera_init__(props, component, server)
      end
    ]
  end

  @doc """
  Tier-2 `base_action/3` dispatcher scaffolding (brief 3f): one clause per
  inherited action, dispatching to the base module's `__tessera_action__/3`
  entry point. Generated ONLY when the base actually exports that entry point
  (a Hologram-runtime component). Tier-1 fn-actions never compile to the BEAM
  and have no `__tessera_action__/3`, so this returns `[]` for them — their
  down-call is real ES `super` in the lowered JS, not a BEAM dispatcher.
  """
  @spec action_dispatcher_asts(module(), [atom()]) :: [Macro.t()]
  def action_dispatcher_asts(base_module, action_names) do
    if function_exported?(base_module, :__tessera_action__, 3) do
      clauses =
        Enum.map(action_names, fn name ->
          quote do
            def base_action(unquote(name), params, component),
              do: unquote(base_module).__tessera_action__(unquote(name), params, component)
          end
        end)

      [quote do: (unquote_splicing(clauses))]
    else
      []
    end
  end

  # -- option evaluation -------------------------------------------------------

  defp eval_opts!(opts, caller) do
    {value, _binding} = Code.eval_quoted(opts, [], file: caller.file, line: caller.line)

    unless Keyword.keyword?(value) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera derivation options must be a keyword list of compile-time literals, " <>
            "got: #{inspect(value)}"
    end

    value
  rescue
    e ->
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera derivation options must be compile-time literals " <>
            "(no variables or module attributes) — #{Exception.message(e)}"
  end
end