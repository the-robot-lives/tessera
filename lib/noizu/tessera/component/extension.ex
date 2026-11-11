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
    * chain construction (§5.9, brief 2e) — `takeover?/1`, `chain_depth/1`,
      `chain_order/1` (dependency depth → `priority:` → module name,
      innermost first — the mirror of the JS registry comparator),
      `record_takeover_layer!/2` (the app-wide sibling registry + the §5.7
      chain-conflict warning), and `artifact_stem/1` so sibling takeover
      layers never clobber each other's base-tag-keyed artifacts (§5.8);
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

  alias Noizu.Tessera.Component.Template
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
    # D1 tag takeover (§5.9): the extension registers under the BASE tag and
    # is a LAYER of it, never a replacement. Layers compose deterministically
    # (chain_depth → priority: → module name, `chain_order/1`); same-depth
    # conflicts on one action/region name get the §5.7 warning from
    # `record_takeover_layer!/2` (called by `Component.__before_compile__`),
    # and the runtime chain is composed by the JS registry at the tag's first
    # define (priv/js/src/extend.mjs). `priority:` orders same-depth siblings.
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

    # A takeover layer compiles to a registry MIXIN (no exported class,
    # §5.9/§5.8) — a fresh-tag derivation would emit an element module
    # importing a class that does not exist. Chain takeover layers through
    # `:inherit` (dependency order comes from the `use` spine, §5.9).
    if takeover?(base_spec) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera cannot mint a fresh tag from the tag-takeover layer " <>
            "#{inspect(base_spec.module)} (which takes over #{inspect(base_spec.tag)}) — " <>
            "takeover layers ship as mixins with no exported base class to extend " <>
            "(EXTENSION-CONTRACT.md §5.9); derive from the vendor base module instead"
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
  # own wrapper; a takeover (:inherit) registers under the BASE tag, so every
  # sibling's default would name the same file — suffix the declaring module
  # to keep one wrapper per layer (§5.8; same suffix rule as `artifact_stem/1`).
  defp resolve_js!(nil, tag, _base_spec, false, _caller),
    do: String.replace(tag, "-", "_") <> ".mjs"

  defp resolve_js!(nil, tag, _base_spec, true, caller),
    do: String.replace(tag, "-", "_") <> "_" <> module_slug(caller.module) <> ".mjs"

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
          Module.put_attribute(
            __MODULE__,
            :__props__,
            {unquote(name), unquote(type), unquote(opts)}
          )
        end
      end)
    else
      []
    end
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: opts ++ [{key, value}]

  # -- chain construction (brief 2e, EXTENSION-CONTRACT.md §5.9) ----------------

  @doc """
  True when `spec` is a `tag: :inherit` tag-takeover: it derives from another
  module AND registers under the BASE tag. Fresh tags MUST differ from the
  base tag (`resolve_tag!/3`), so `derived_from` + tag equality is exactly the
  takeover condition — no extra spec field, and goldens/manifests for
  fresh-tag specs are untouched.
  """
  @spec takeover?(Spec.t()) :: boolean()
  def takeover?(%Spec{derived_from: nil}), do: false

  def takeover?(%Spec{derived_from: mod, tag: tag}) when is_atom(mod) do
    mod.__tessera_spec__().tag == tag
  end

  @doc """
  Layers above the vendor base along the `derived_from` spine (§5.9 dependency
  order): `0` for a fresh component, `1` for the first `:inherit` layer, and so
  on. A cycle cannot reach here — `guard_cycle!/2` rejects it at expansion.
  """
  @spec chain_depth(Spec.t()) :: non_neg_integer()
  def chain_depth(%Spec{derived_from: nil}), do: 0

  def chain_depth(%Spec{derived_from: mod}) when is_atom(mod),
    do: 1 + chain_depth(mod.__tessera_spec__())

  @doc """
  Sorts takeover-chain layer descriptors INNERMOST → OUTERMOST per §5.9:
  dependency `depth` first, then `priority:` (higher sits further out), then
  module name ascending (alphabetically-first sits closer to the base). The
  outermost layer runs first and wins conflicts. Entries are maps with
  `:depth`, `:priority` and `:module` (string). This is the compile-time
  mirror of `priv/js/src/extend.mjs`'s comparator (which adds a
  first-registered-outermost fallback for unlabelled hand-written mixins).
  """
  @spec chain_order([map()]) :: [map()]
  def chain_order(entries),
    do: Enum.sort_by(entries, fn e -> {e.depth, e.priority, e.module} end)

  @doc """
  The artifact filename STEM for a spec. Fresh and fresh-tag-derived specs
  keep the plain tag (byte-stable goldens). A takeover layer registers under
  the BASE tag (§5.8), and sibling layers would otherwise clobber each other's
  base-tag-keyed element/contract files — so takeover artifacts carry the
  declaring module: `<base-tag>__<module_snake>`.
  """
  @spec artifact_stem(Spec.t()) :: String.t()
  def artifact_stem(%Spec{tag: tag} = spec) do
    if takeover?(spec), do: tag <> "__" <> module_slug(spec.module), else: tag
  end

  @doc "snake form of `artifact_stem/1` (contract filenames)."
  @spec snake_stem(Spec.t()) :: String.t()
  def snake_stem(%Spec{} = spec), do: String.replace(artifact_stem(spec), "-", "_")

  defp module_slug(mod) when is_atom(mod) do
    case Module.split(mod) do
      [] -> "ext"
      parts -> parts |> List.last() |> Macro.underscore()
    end
  end

  defp module_slug(_), do: "ext"

  defp module_label(mod) when is_atom(mod) do
    mod |> Module.split() |> Enum.join(".")
  end

  defp module_label(mod), do: inspect(mod)

  @doc """
  Records a compiled `tag: :inherit` layer in the app-wide sibling registry
  and emits the §5.7 CHAIN-CONFLICT warning for every same-depth sibling that
  overrides an action body or a template region this layer also overrides.
  Called from `Component.__before_compile__/1` once the merged spec exists:
  whichever sibling compiles SECOND sees the first and warns (compile order
  never hides the conflict). The chain itself needs no re-ordering here —
  depth/priority ride each spec + the JS registry entries, and the runtime
  composition IS `chain_order/1` at define time.

  The registry lives in `:persistent_term` keyed by the BASE TAG: it must
  outlive any single module's compile (siblings expand in separate rounds)
  and one re-compiling module never warns against itself.
  """
  @spec record_takeover_layer!(Spec.t(), Macro.Env.t()) :: :ok
  def record_takeover_layer!(%Spec{} = spec, %Macro.Env{} = env) do
    entry = %{
      module: module_label(spec.module),
      depth: chain_depth(spec),
      priority: spec.priority || 0,
      actions:
        spec.actions
        # an inherited entry the author's action/3 clauses override
        # (`overrides:` opt — Tier-2's counterpart of the Tier-1 DSL override
        # delta) counts as this layer's contested surface (§5.7)
        |> Enum.filter(&(!&1[:inherited] or &1[:override]))
        |> Enum.map(&Atom.to_string(&1.name))
        |> MapSet.new(),
      regions: spec.region_overrides |> Enum.map(&Atom.to_string(&1)) |> MapSet.new()
    }

    key = {:tessera_takeover_layers, spec.tag}
    siblings = :persistent_term.get(key, [])

    for other <- siblings, other.depth == entry.depth, other.module != entry.module do
      warn_chain_conflict(
        spec,
        entry,
        other,
        env,
        "action(s)",
        MapSet.intersection(entry.actions, other.actions)
      )

      warn_chain_conflict(
        spec,
        entry,
        other,
        env,
        "region(s)",
        MapSet.intersection(entry.regions, other.regions)
      )
    end

    :persistent_term.put(key, siblings ++ [entry])
    :ok
  end

  defp warn_chain_conflict(%Spec{tag: tag}, entry, other, env, label, names) do
    unless MapSet.size(names) == 0 do
      [inner, outer] = chain_order([entry, other])

      IO.warn(
        "[tessera] chain conflict on <#{tag}>: #{outer.module} and #{inner.module} (same depth " <>
          "#{entry.depth}) override the same #{label}: #{names |> MapSet.to_list() |> Enum.sort() |> Enum.join(", ")} — " <>
          "#{outer.module} sits outermost by §5.9 chain order and WINS; #{inner.module} stays " <>
          "silent until the dispatch goes down-chain (`base_action/3` / JS `super`) " <>
          "(EXTENSION-CONTRACT.md §5.7)",
        Macro.Env.location(env)
      )
    end

    :ok
  end

  # -- merged spec -------------------------------------------------------------

  @doc """
  Deep-copies the base spec's declarations and layers the derived module's
  `deltas` (a map of raw author entries keyed by kind). Returns a merged
  declaration map the caller feeds through `validate_all!` + the element
  translator. Inherited entries carry `inherited: true`.

  Rules (§5.5): additive new names append in declaration order; override-by-name
  replaces wholesale (events merge detail, keeping inherited keys); removal is
  forbidden; `required:` may relax not tighten; retyping an inherited
  attr/prop/state key the base READS is rejected (the type-change
  reference-graph guard). Duplicate AUTHOR declarations raise here (the merge
  would otherwise silently last-wins them).

  Event renames (§5.6, brief 2d): `event "new", renames: "inherited"` replaces
  the inherited name in place (detail inherited keys kept, `renamed_from`
  marker). The rename is then propagated over the merged emission points —
  inherited action/lifecycle JS that still emits the OLD event name is
  rewritten to the new one and marked `re_emit: true` so the derived class
  re-emits the method and shadows the base's (which would otherwise emit the
  dead name).
  """
  @spec merge_spec!(Spec.t(), map(), Macro.Env.t()) :: map()
  def merge_spec!(%Spec{} = base_spec, deltas, %Macro.Env{} = env) do
    author_events = Map.get(deltas, :events, [])
    renames = collect_renames!(base_spec, author_events, env)

    merged =
      Map.new(list_kinds(), fn kind ->
        base_entries =
          if kind == :events do
            apply_renames(Map.get(base_spec, kind, []), renames, env)
          else
            Map.get(base_spec, kind, [])
          end

        author_entries =
          if kind == :events,
            do: Enum.reject(author_events, & &1[:renames]),
            else: Map.get(deltas, kind, [])

        assert_author_duplicates!(kind, author_entries, env)
        {kind, merge_entries(kind, base_entries, author_entries, env)}
      end)

    merged =
      merged
      |> Map.put(:styles, mark_inherited(base_spec.styles) ++ Map.get(deltas, :styles, []))
      |> Map.put(:template, merge_template(base_spec, deltas))
      |> Map.put(:lifecycle, merge_lifecycle(base_spec, deltas))
      |> Map.put(:cy, Map.get(deltas, :cy) || base_spec.cy)

    assert_no_removal!(base_spec, merged, renames, env)
    assert_type_change!(base_spec, merged, env)

    merged
    |> Map.update!(:actions, &rewrite_emissions(&1, renames))
    |> Map.update!(:lifecycle, &rewrite_lifecycle_emissions(&1, renames))
  end

  # -- event renames (§5.6, brief 2d) ------------------------------------------

  # Collects author rename declarations (old_inherited_name => author entry).
  # Guards: the target must be an inherited event; renaming an already-renamed
  # event is forbidden (no rename chains); the new name must be fresh w.r.t.
  # the inherited surface; two renames may not share a target or a new name.
  defp collect_renames!(%Spec{} = base_spec, author_events, env) do
    renames = Enum.filter(author_events, & &1[:renames])

    by_old =
      Map.new(renames, fn e ->
        old = e[:renames]
        new = e.name

        unless is_binary(old) do
          raise CompileError,
            file: env.file,
            line: e.line || 0,
            description:
              "tessera event #{inspect(new)}: `renames:` must name the inherited event as a " <>
                "string, got: #{inspect(old)} (EXTENSION-CONTRACT.md §5.6)"
        end

        base_entry = Enum.find(base_spec.events, &(&1.name == old))

        cond do
          is_nil(base_entry) ->
            raise CompileError,
              file: env.file,
              line: e.line || 0,
              description:
                "broken rename chain: tessera event #{inspect(new)} renames #{inspect(old)}, " <>
                  "but #{inspect(old)} is not an inherited event of base " <>
                  "#{inspect(base_spec.module)} (EXTENSION-CONTRACT.md §5.6)"

          base_entry[:renamed_from] ->
            raise CompileError,
              file: env.file,
              line: e.line || 0,
              description:
                "broken rename chain: tessera event #{inspect(new)} renames #{inspect(old)}, " <>
                  "but #{inspect(old)} is itself already a rename of " <>
                  "#{inspect(base_entry[:renamed_from])} — renaming an already-renamed event " <>
                  "is forbidden (EXTENSION-CONTRACT.md §5.6)"

          new == old ->
            raise CompileError,
              file: env.file,
              line: e.line || 0,
              description:
                "tessera event #{inspect(new)} renames itself — drop the `renames:` option " <>
                  "(EXTENSION-CONTRACT.md §5.6)"

          Enum.any?(base_spec.events, &(&1.name == new)) ->
            raise CompileError,
              file: env.file,
              line: e.line || 0,
              description:
                "rename target conflict: tessera event #{inspect(new)} renames " <>
                  "#{inspect(old)}, but #{inspect(new)} is already an inherited event of " <>
                  "#{inspect(base_spec.module)} — a rename must produce a fresh name " <>
                  "(EXTENSION-CONTRACT.md §5.6)"

          true ->
            :ok
        end

        {old, e}
      end)

    dup_targets =
      renames
      |> Enum.map(& &1[:renames])
      |> Enum.frequencies()
      |> Enum.filter(fn {_k, c} -> c > 1 end)

    if dup_targets != [] do
      raise CompileError,
        file: env.file,
        line: env.line || 0,
        description:
          "two tessera events rename the same inherited event " <>
            "#{inspect(Enum.map(dup_targets, &elem(&1, 0)))} (EXTENSION-CONTRACT.md §5.6)"
    end

    dup_new_names =
      renames |> Enum.map(& &1.name) |> Enum.frequencies() |> Enum.filter(fn {_k, c} -> c > 1 end)

    if dup_new_names != [] do
      raise CompileError,
        file: env.file,
        line: env.line || 0,
        description:
          "two tessera renames land on the same new name " <>
            "#{inspect(Enum.map(dup_new_names, &elem(&1, 0)))} (EXTENSION-CONTRACT.md §5.6)"
    end

    by_old
  end

  defp apply_renames(base_events, renames, _env) when map_size(renames) == 0, do: base_events

  defp apply_renames(base_events, renames, env) do
    Enum.map(base_events, fn entry ->
      case Map.fetch(renames, entry.name) do
        {:ok, author} ->
          detail =
            merge_detail!(
              entry[:detail] || %{},
              author[:detail] || %{},
              author.name,
              author.line || 0,
              env
            )

          author
          |> Map.put(:detail, detail)
          |> Map.put(:renamed_from, entry.name)
          |> Map.delete(:renames)

        :error ->
          entry
      end
    end)
  end

  defp rewrite_emissions(entries, renames) when map_size(renames) == 0, do: entries

  defp rewrite_emissions(entries, renames) do
    Enum.map(entries, fn entry ->
      case rewrite_js(entry[:js], renames) do
        :unchanged ->
          entry

        {:changed, js} ->
          entry |> Map.put(:js, js) |> Map.put(:re_emit, true)
      end
    end)
  end

  defp rewrite_lifecycle_emissions(lifecycle, renames) when map_size(renames) == 0, do: lifecycle

  defp rewrite_lifecycle_emissions(lifecycle, renames) do
    Map.new(lifecycle, fn {hook, entry} ->
      case rewrite_js(entry[:js], renames) do
        :unchanged ->
          {hook, entry}

        {:changed, js} ->
          {hook, entry |> Map.put(:js, js) |> Map.put(:re_emit, true)}
      end
    end)
  end

  # The compiled emission point for an event is `emit(this, "name", …)` (see
  # Noizu.Tessera.Component.Expr's emit lowering) — rewriting the name literal
  # is the whole rename at the JS layer. A re-emitted inherited method shadows
  # the base's (which still emits the dead name on the class chain).
  defp rewrite_js(js, _renames) when not is_binary(js), do: :unchanged

  defp rewrite_js(js, renames) do
    {new_js, changed?} =
      Enum.reduce(renames, {js, false}, fn {old, author}, {acc, changed} ->
        pattern = "emit(this, \"#{old}\""
        replacement = "emit(this, \"#{author.name}\""
        rewritten = String.replace(acc, pattern, replacement)
        {rewritten, changed or rewritten != acc}
      end)

    if changed?, do: {:changed, new_js}, else: :unchanged
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
            replaced = merge_entry_detail(kind, base_index[entry.name], replaced, env)
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
  # detail-narrowing guard rejects RETYPING an inherited detail key (same key,
  # different type) — the CEM detail shape is a published surface, so a derived
  # element may add keys but never change an inherited key's type.
  defp merge_entry_detail(:events, %{detail: base_detail}, entry, env) do
    Map.put(
      entry,
      :detail,
      merge_detail!(base_detail || %{}, entry[:detail] || %{}, entry.name, entry.line || 0, env)
    )
  end

  defp merge_entry_detail(_kind, _base, entry, _env), do: entry

  # Merges an inherited event detail map with the author's, rejecting retypes
  # of keys present in both (§5.6 detail-narrowing guard).
  defp merge_detail!(base_detail, author_detail, event_name, line, env) do
    retypes =
      for {key, type} <- author_detail,
          Map.has_key?(base_detail, key),
          base_detail[key] != type,
          do: {key, base_detail[key], type}

    case retypes do
      [{key, base_type, author_type} | _] ->
        raise CompileError,
          file: env.file,
          line: line,
          description:
            "tessera event #{inspect(event_name)} narrows the inherited detail key " <>
              "#{inspect(key)} from #{inspect(base_type)} to #{inspect(author_type)} — " <>
              "event detail may be extended but never retyped (EXTENSION-CONTRACT.md §5.6)"

      [] ->
        Map.merge(base_detail, author_detail)
    end
  end

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
  # removal syntax ever drops a name. A base EVENT name renamed away via
  # `renames:` (§5.6) is the one allowed disappearance — its replacement (the
  # new name) is verified present in its stead.
  defp assert_no_removal!(base_spec, merged, renames, env) do
    Enum.each(list_kinds(), fn kind ->
      merged_names = MapSet.new(Enum.map(merged[kind], & &1.name))

      Enum.each(Map.get(base_spec, kind, []), fn entry ->
        renamed? = kind == :events and Map.has_key?(renames, entry.name)

        unless MapSet.member?(merged_names, entry.name) or renamed? do
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

  # Type-change reference-graph guard (§5.5, brief 2d): an override MAY retype
  # an inherited attr/prop/state key that the base never reads, but retyping a
  # REFERENCED key silently breaks the base's already-compiled JS (template
  # interpolations, `state.key` reads, action bodies compiled against the old
  # shape). The guard walks the BASE's compiled template tree and action
  # function ASTs to collect referenced keys, then rejects any author override
  # that changes the `:type` of one of those keys.
  defp assert_type_change!(%Spec{} = base_spec, merged, env) do
    referenced = referenced_keys(base_spec)

    if MapSet.size(referenced) > 0 do
      base_by_kind =
        Map.new([:attrs, :props, :state], fn kind ->
          {kind, Map.new(Map.get(base_spec, kind, []), &{&1.name, &1})}
        end)

      Enum.each([:attrs, :props, :state], fn kind ->
        Enum.each(merged[kind], fn entry ->
          # only AUTHOR (non-inherited) overrides can change a type
          if !entry[:inherited] and MapSet.member?(referenced, entry.name) do
            case base_by_kind[kind][entry.name] do
              %{type: base_type} when is_atom(base_type) and base_type != entry.type ->
                raise CompileError,
                  file: env.file,
                  line: entry[:line] || env.line || 0,
                  description:
                    "tessera type-change guard: derived #{inspect(env.module)} retypes " <>
                      "#{kind} #{inspect(entry.name)} from #{inspect(base_type)} to " <>
                      "#{inspect(entry.type)}, but #{inspect(base_spec.module)}'s compiled " <>
                      "template/actions READ that key — a referenced key's type is load-bearing " <>
                      "(EXTENSION-CONTRACT.md §5.5)"

              _ ->
                :ok
            end
          end
        end)
      end)
    end

    :ok
  end

  # Collects every state/attr/prop key the base references: `{@key}` reads in
  # the compiled template (both lexers) plus `state.key` / `@key` reads in the
  # base's action fn ASTs. (Lifecycle hooks are data-only in the spec — no
  # fn_ast survives to the base spec — so template + action reads are the
  # complete reference surface available at merge time.)
  defp referenced_keys(%Spec{} = base_spec) do
    template_keys =
      case base_spec.template do
        %{raw: raw} when is_binary(raw) ->
          case Template.parse(raw) do
            {:ok, tree} -> tree_referenced_keys(tree)
            {:error, _} -> MapSet.new()
          end

        _ ->
          MapSet.new()
      end

    action_keys =
      base_spec.actions
      |> Enum.flat_map(fn a -> if a[:fn_ast], do: ast_referenced_keys(a.fn_ast), else: [] end)
      |> MapSet.new()

    MapSet.union(template_keys, action_keys)
  end

  # Walks a parsed template tree, translating every {:expr, ast} and attribute
  # expression through the reference-key extractor.
  defp tree_referenced_keys(tree) do
    tree
    |> collect_exprs([])
    |> Enum.flat_map(&ast_referenced_keys/1)
    |> MapSet.new()
  end

  defp collect_exprs({:element, _tag, attrs, children}, acc) do
    attr_exprs = for {_k, {:parts, parts}} <- attrs, {:expr, e} <- parts, do: e
    acc = acc ++ attr_exprs
    Enum.reduce(children, acc, &collect_exprs/2)
  end

  defp collect_exprs({:fragment, children}, acc), do: Enum.reduce(children, acc, &collect_exprs/2)

  defp collect_exprs({:if, ast, then_c, else_c}, acc) do
    acc = acc ++ [ast]
    acc = Enum.reduce(then_c, acc, &collect_exprs/2)
    Enum.reduce(else_c, acc, &collect_exprs/2)
  end

  defp collect_exprs({:for, _var, coll, children}, acc) do
    acc = acc ++ [coll]
    Enum.reduce(children, acc, &collect_exprs/2)
  end

  defp collect_exprs({:region, _name, children}, acc),
    do: Enum.reduce(children, acc, &collect_exprs/2)

  defp collect_exprs({:expr, ast}, acc), do: acc ++ [ast]
  defp collect_exprs(_leaf, acc), do: acc

  # Extracts the state/attr/prop keys an expression AST reads: `@key` sigil
  # reads (attrs, props, state) and `state.key` accesses (state only).
  defp ast_referenced_keys(ast) do
    {_ast, keys} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:@, _meta, [{name, _, ctx}]} = node, acc
        when is_atom(name) and name != nil and ctx == nil ->
          {node, MapSet.put(acc, name)}

        {{:., _, [{:state, _, nil}, key]}, _, []} = node, acc when is_atom(key) ->
          {node, MapSet.put(acc, key)}

        node, acc ->
          {node, acc}
      end)

    MapSet.to_list(keys)
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
      description:
        "tessera extension_api pin must be a semver requirement string, got: #{inspect(other)}"
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
    cond do
      # The §5.3 contract entry point (preferred): a Tier-2 component that
      # declares the per-action literal `__tessera_action__/3` clauses.
      function_exported?(base_module, :__tessera_action__, 3) ->
        dispatch_clauses(base_module, :__tessera_action__, action_names)

      # Tier-2 fallback (brief 3f): a Hologram-runtime component exports its
      # real `action/3` callback — dispatch straight to it with the literal
      # name (static remote call, transpilable; the base's own clauses + any
      # parent chaining inside the base still apply).
      function_exported?(base_module, :action, 3) ->
        dispatch_clauses(base_module, :action, action_names)

      # Tier-1 fn-actions never compile to the BEAM — their down-call is real
      # ES `super` in the lowered JS, not a BEAM dispatcher.
      true ->
        []
    end
  end

  defp dispatch_clauses(base_module, entry, action_names) do
    clauses =
      Enum.map(action_names, fn name ->
        quote do
          def base_action(unquote(name), params, component),
            do: unquote(base_module).unquote(entry)(unquote(name), params, component)
        end
      end)

    [quote(do: (unquote_splicing(clauses)))]
  end

  # -- Tier-2 lowering (brief 3f, EXTENSION-CONTRACT.md §5.3/D4, T2-9) ---------

  @doc """
  The canonical Tier-2 element macro, invoked by a vendor module as
  `use Noizu.Tessera.Component.Extension, …` (D4: the vendor module IS the
  macro — the `__using__` its extenders consume is generated here, not
  hand-rolled). Options (compile-time literals):

    * `tag:` (required) — the vendor's element tag;
    * `actions:` — snake atoms in declaration order, the §6.1 OPEN surface
      (the runtime bodies are the vendor's own `def action/3` clauses —
      Hologram-transpilable Elixir, never fn-AST DSL bodies);
    * `props:` — `name: [type: :, default: :]` triples mirroring the
      vendor's Hologram `prop/2,3` declarations (re-emitted into extenders);
    * `regions:` — atoms naming the arity-1 template helper functions the
      markup calls (e.g. `[:row_label]`) — extenders get delegating
      `def name(arg), do: Vendor.name(arg)` + `defoverridable`;
    * `template:` — the markup string (the same markup the vendor's own
      `def template` renders) — rides `spec.template.raw` so extenders
      re-emit it and the T1-4/T2-7 reference-graph guard can walk it;
    * `extension_api:` — the §8 semver declaration (defaults to 1.0.0).

  The expansion splices the CONTRACT scaffold onto the vendor:
  `__tessera_spec__/0` + `__tessera_manifest__/0` (the minimal Tier-2 spec —
  the interface extenders merge against), the per-action literal
  `__tessera_action__/3` entry clauses (static calls into the vendor's own
  `action/3`; unknown names raise the boxed FunctionClauseError the §6.3
  unknown-action classification expects), and the generated `__using__/1`
  that drives `derive_tier2!/3` for every extender.
  """
  defmacro __using__(opts) do
    tier2_vendor!(opts, __CALLER__)
  end

  # Vendor-side expansion: minimal spec + contract entry + generated __using__.
  defp tier2_vendor!(opts, %Macro.Env{} = caller) do
    opts = eval_opts!(opts, caller)
    tag = Keyword.get(opts, :tag)
    Spec.validate!(:tag, tag, %{}, caller.file, caller.line)

    action_names = Keyword.get(opts, :actions, [])
    region_names = Keyword.get(opts, :regions, [])
    extension_api = Keyword.get(opts, :extension_api) || @default_extension_api
    markup = Keyword.get(opts, :template)

    unless is_binary(markup) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera Tier-2 `template:` must be the markup string the component renders " <>
            "(the same markup its bundle serves) — it rides spec.template.raw so extenders " <>
            "re-emit it (EXTENSION-CONTRACT.md §5.5)"
    end

    Enum.each(action_names, fn name ->
      unless is_atom(name) do
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description:
            "tessera Tier-2 `actions:` must be snake atoms in declaration order, got: " <>
              inspect(name)
      end
    end)

    props = parse_tier2_props!(opts, caller)

    # §6.7 (brief 2f parity): declared via `use …, form_associated: true`.
    form_associated = Keyword.get(opts, :form_associated) == true

    unless is_boolean(Keyword.get(opts, :form_associated, false)) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera Tier-2 `form_associated:` must be a boolean (§6.7), got: " <>
            inspect(Keyword.get(opts, :form_associated))
    end

    # D2/§10 internal annotation (advisory warn-once only): a subset of the
    # declared actions is `internal: true` on the spec entries.
    internal_actions = Keyword.get(opts, :internal_actions, [])

    Enum.each(internal_actions, fn name ->
      unless name in action_names do
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description:
            "tessera Tier-2 `internal_actions:` must be a subset of `actions:` — " <>
              inspect(name) <> " is not declared (D2/§10)"
      end
    end)

    spec = %Spec{
      version: 1,
      tag: tag,
      module: caller.module,
      file: caller.file,
      actions:
        Enum.map(action_names, fn name ->
          if name in internal_actions do
            %{name: name, line: caller.line, internal: true}
          else
            %{name: name, line: caller.line}
          end
        end),
      props: props,
      template: %{raw: markup, lexer: :hologram, line: caller.line},
      extension_api: extension_api,
      form_associated: form_associated
    }

    entry_asts = tier2_entry_asts(caller.module, action_names)
    region_asts = tier2_regions_decl_asts(region_names)

    template_ast =
      quote do
        @doc """
        The tessera template: generated from the `use Extension` `template:`
        markup (single source — the extender scaffold re-emits the same
        string from the merged spec). Generated — do not override.
        """
        def template do
          Hologram.Template.sigil_HOLO(unquote(markup), [])
        end
      end

    quote do
      @doc "Template helper functions this Tier-2 component's markup calls, with arities (§5.4)."
      unquote_splicing(region_asts)

      unquote_splicing(List.wrap(template_ast))

      @doc "The compiled `Noizu.Tessera.Spec` struct for this Tier-2 component."
      @spec __tessera_spec__() :: Noizu.Tessera.Spec.t()
      def __tessera_spec__, do: unquote(Macro.escape(spec))

      @doc "The tessera manifest entry (plain map) for this Tier-2 component."
      @spec __tessera_manifest__() :: map()
      def __tessera_manifest__, do: unquote(Macro.escape(Spec.to_manifest_map(spec)))

      unquote_splicing(entry_asts)

      # The canonical extension macro (§5.3/D4): `use ThisModule, tag: …`
      # expands through the shared derivation layer below.
      @doc false
      defmacro __using__(opts) do
        Noizu.Tessera.Component.Extension.derive_tier2!(
          unquote(caller.module),
          opts,
          __CALLER__
        )
      end
    end
  end

  # Regions ride the vendor as `__tessera_regions__/0` (keyword name → arity;
  # spec.ex carries no regions-of-this-shape field and the Tier-2 standalone
  # path needs the arities to generate delegating defs). Read at extender
  # expansion time — the vendor module is compiled and loaded by then.
  defp tier2_regions_decl_asts(regions) do
    normalized = Enum.map(regions, fn {name, arity} -> {Atom.to_string(name), arity} end)

    [
      quote do
        @doc false
        def __tessera_regions__, do: unquote(normalized)
      end
    ]
  end

  # The per-action literal `__tessera_action__/3` entry clauses — static calls
  # into the module's own `action/3`, transpilable by Hologram (dynamic
  # function application is not in its IR). NO catch-all: an unknown name
  # raises the boxed %FunctionClauseError{} the §6.3 unknown-action path
  # classifies (the StateProbe convention).
  defp tier2_entry_asts(_module, []), do: []

  defp tier2_entry_asts(_module, action_names) do
    clauses =
      Enum.map(action_names, fn name ->
        quote do
          def __tessera_action__(unquote(name), params, component),
            do: action(unquote(name), params, component)
        end
      end)

    [quote(do: (unquote_splicing(clauses)))]
  end

  @doc """
  The expansion of a Tier-2 vendor's generated `__using__/1`
  (`use Vendor, tag: …` — §5.3, D4). Runs the SAME shared layer Tier 1 uses —
  option guards, the §5.9 chain machinery, `merge_spec!/3` (hence the §5.5
  merge rules + the T1-4/T2-7 reference-graph type-change guard) and the §8
  pin check — then splices the Tier-2 lowering: a Hologram component whose
  inherited surface is reachable through the injected `base_action/3`
  dispatcher + `defoverridable` (Hologram's IR has no `super`; D4 forbids
  promising Elixir-level super).

  Multi-level chaining (T2-9 gap fix): the scaffold records the PARENT
  (the module the extender `use`d) and links through it — per-action
  `base_action/3` clauses dispatch to the parent's `__tessera_action__/3`
  entry, and the dynamic-name fallback dispatches the parent's `action/3`
  (whose clauses/catch-all continue down-chain), so A→B→C never re-includes
  the whole stack.
  """
  @spec derive_tier2!(module(), keyword(), Macro.Env.t()) :: Macro.t()
  def derive_tier2!(vendor_module, opts, %Macro.Env{} = caller) when is_atom(vendor_module) do
    vendor_spec = vendor_module.__tessera_spec__()

    opts = eval_opts!(opts, caller)

    guard_tier2_double_use!(caller)

    base = vendor_spec.module

    # Cycle guard walks the derived_from spine (a takeover layer deriving
    # from a takeover layer must not revisit the deriving module).
    spine =
      vendor_spec
      |> Stream.iterate(fn s -> s.derived_from && s.derived_from.__tessera_spec__() end)
      |> Enum.take_while(& &1)
      |> Enum.map(& &1.module)

    if caller.module in spine do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera derivation cycle: #{inspect(caller.module)} already appears in the " <>
            "extension chain of #{inspect(vendor_spec.module)} (EXTENSION-CONTRACT.md §5.9)"
    end

    guard_cross_runtime!(vendor_spec, caller)

    {tag, _inherit?} = resolve_tag!(Keyword.get(opts, :tag), vendor_spec, caller)
    priority = resolve_priority!(Keyword.get(opts, :priority, 0), caller)
    pin = Keyword.get(opts, :extension_api)
    base_api = vendor_spec.extension_api || @default_extension_api
    check_pin!(base_api, pin, caller)
    extension_api = pin || base_api

    author_actions = Keyword.get(opts, :actions, [])

    Enum.each(author_actions, fn name ->
      unless is_atom(name) do
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description:
            "tessera Tier-2 derivation `actions:` must be snake atoms (the NEW action " <>
              "names this module adds), got: #{inspect(name)}"
      end
    end)

    Module.put_attribute(caller.module, :tessera_tier2_derived_from, base)
    Module.put_attribute(caller.module, :tessera_tier2_tag, tag)

    deltas = %{
      actions: Enum.map(author_actions, &%{name: &1, line: caller.line}),
      # §5.5 on Tier 2 (brief 3f/T2-7): `props:` on a derive adds or
      # overrides-by-name through the SAME merge layer — a retype of a key
      # the base reads trips the shared type-change guard (assert_type_change!)
      # inside merge_spec!/3.
      props: parse_tier2_props!(opts, caller)
    }

    merged = merge_spec!(vendor_spec, deltas, caller)

    # §5.7 on Tier 2: the author's takeover `def action(:name, …)` clauses are
    # invisible to the merge (raw BEAM clauses, not spec deltas — Tier-1 sees
    # its DSL overrides as delta entries). `overrides:` is the explicit
    # declaration that feeds the chain-conflict warning AND stays on the
    # merged entry so the takeover registry counts it.
    overrides = Keyword.get(opts, :overrides, [])

    Enum.each(overrides, fn name ->
      unless is_atom(name) do
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description:
            "tessera Tier-2 `overrides:` must list snake atoms (the action names this " <>
              "module's action/3 clauses override), got: #{inspect(name)}"
      end

      merged_names = Enum.map(merged.actions, & &1.name)

      unless name in merged_names do
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description:
            "tessera Tier-2 `overrides:` names #{inspect(name)}, which the vendor does " <>
              "not declare — only inherited actions can be overridden (§5.7)"
      end
    end)

    merged =
      if overrides == [] do
        merged
      else
        override_set = MapSet.new(overrides)

        Map.update!(merged, :actions, fn entries ->
          Enum.map(entries, fn entry ->
            if entry.name in override_set and entry[:inherited] do
              Map.put(entry, :override, true)
            else
              entry
            end
          end)
        end)
      end

    # merge_spec!/3 returns a plain map (list_kinds rebuild) — re-wrap into a
    # real %Spec{} so the §5.9 chain helpers (takeover?/1, chain_depth/1,
    # record_takeover_layer!/2, __tessera_spec__/0 consumers) match.
    merged_spec =
      %Spec{
        version: vendor_spec.version,
        tag: tag,
        module: caller.module,
        file: caller.file,
        cy: merged.cy,
        attrs: merged.attrs,
        props: merged.props,
        events: merged.events,
        slots: merged.slots,
        css_properties: merged.css_properties,
        parts: merged.parts,
        state: merged.state,
        actions: merged.actions,
        # merge_spec!/3 reshapes template to its internal `%{line, markup}`
        # merge shape; the SPEC carries the contract template_entry shape —
        # restore raw + the base's lexer so to_manifest_map/1 stays uniform.
        template:
          merged.template &&
            %{
              raw: merged.template.markup,
              lexer: (vendor_spec.template && vendor_spec.template[:lexer]) || :hologram,
              line: merged.template.line
            },
        styles: merged.styles,
        lifecycle: merged.lifecycle,
        derived_from: base,
        priority: priority,
        extension_api: extension_api,
        # §6.7 additive inheritance: the layer participates if it declares
        # `form_associated: true` or its base already does.
        form_associated:
          Keyword.get(opts, :form_associated) == true or vendor_spec.form_associated == true
      }

    # §5.7 chain-conflict warning for a `tag: :inherit` layer (same sibling
    # registry the Tier-1 compiler feeds — compile order never hides it).
    if takeover?(merged_spec) do
      record_takeover_layer!(merged_spec, caller)
    end

    inherited_names = Enum.map(merged_spec.actions, & &1.name)

    regions =
      if function_exported?(vendor_spec.module, :__tessera_regions__, 0) do
        Enum.map(vendor_spec.module.__tessera_regions__(), fn {name, arity} ->
          {String.to_existing_atom(name), arity}
        end)
      else
        []
      end

    quote do
      use Hologram.Component
      use Hologram.JS

      # Inherited Hologram props re-emitted as prop declarations (the
      # extender is a full component: same props, fresh module).
      unquote_splicing(tier2_prop_asts(merged_spec))

      # Init down-chain (§5.3): the injected delegates reach the vendor's
      # `__tessera_init__/2,3` through `base_init/2,3` (T1-2 names); an
      # author override replaces the delegates wholesale (defoverridable).
      def init(props, component), do: __tessera_init__(props, component)

      def init(props, component, server), do: __tessera_init__(props, component, server)

      def __tessera_init__(props, component), do: base_init(props, component)

      def __tessera_init__(props, component, server), do: base_init(props, component, server)

      defoverridable init: 2, init: 3, __tessera_init__: 2, __tessera_init__: 3

      unquote_splicing(init_dispatcher_asts(vendor_spec.module))

      # Action down-chain (§5.3/T2-9): per-action `base_action/3` clauses
      # make STATIC literal remote calls into the parent's contract entry —
      # Hologram's IR has no dynamic function application, so the fallback
      # dispatch rides clause MATCHING on a local variable-name call instead
      # of a dynamic remote call. The author's override clauses come AFTER
      # this `use` and are just plain `action/3` clauses; the total chain
      # fallback is appended at `__before_compile__` (see
      # `__before_compile__/1`) so it can never shadow them.
      #
      # `__tessera_action__/3` entries follow for every merged action, so a
      # chained extender is itself a valid chain parent.
      unquote_splicing(action_dispatcher_asts(vendor_spec.module, inherited_names))

      unquote_splicing(tier2_entry_asts(caller.module, inherited_names))

      # NOTE: FUNCTION form — on Elixir 1.20.1 the tuple form
      # ({Module, :fun}) runs the hook but DISCARDS its returned quote.
      @before_compile Noizu.Tessera.Component.Extension

      # Named template regions (§5.4 Tier-2 analogue): delegating defs so an
      # unoverridden extender renders the vendor default and an override
      # replaces it (defoverridable); the re-emitted template calls resolve
      # to THIS module's definitions.
      unquote_splicing(tier2_region_asts(vendor_spec.module, regions))

      # The merged template markup (§5.5 — the spec is the interface between
      # definition and runtime): re-emitted verbatim, so region/helper calls
      # resolve locally and inherited `{@key}` reads keep their merged names.
      def template do
        Hologram.Template.sigil_HOLO(unquote(template_markup(merged_spec)), [])
      end

      @doc "The compiled `Noizu.Tessera.Spec` struct for this derived component."
      @spec __tessera_spec__() :: Noizu.Tessera.Spec.t()
      def __tessera_spec__, do: unquote(Macro.escape(merged_spec))

      @doc "The tessera manifest entry (plain map) for this derived component."
      @spec __tessera_manifest__() :: map()
      def __tessera_manifest__, do: unquote(Macro.escape(Spec.to_manifest_map(merged_spec)))

      # A chained extender is itself a vendor (§5.9 dependency order): the
      # next layer `use`s THIS module and rides the same derivation.
      @doc false
      defmacro __using__(opts) do
        Noizu.Tessera.Component.Extension.derive_tier2!(__MODULE__, opts, __CALLER__)
      end
    end
  end

  # Runs at the END of every Tier-2 extender's body (registered by the
  # derive_tier2! scaffold). Appends the TOTAL chain fallback `action/3`
  # clause AFTER the author's own clauses: clause order then gives the
  # §6.4 dispatch semantics — author overrides match first, every other
  # name falls through to the injected `base_action/3` chain (whose
  # per-action clauses are static; a name outside the merged surface finds
  # no clause and raises the boxed FunctionClauseError the §6.3
  # unknown-action classification expects). Appending here — not at `use` —
  # is what lets a Tier-2 author mirror the Tier-1 style and define ONLY
  # the clauses they override.
  defmacro __before_compile__(_env) do
    quote do
      def action(name, params, component), do: base_action(name, params, component)
    end
  end

  # T2-6 (§5.10, decision U4): cross-runtime derivation is a CompileError.
  # Same-runtime derivation is fully supported on both tiers. A base's
  # runtime is read off its compiled artifacts, never asserted:
  #   * a Hologram-runtime base exports `action/3` or `__tessera_action__/3`;
  #   * a Lit-lowered (Tier-1) base carries fn-AST actions with NO BEAM
  #     action entry — its bodies exist only as compiled Lit JS, which a
  #     Hologram host cannot reach, and vice versa.
  defp guard_cross_runtime!(%Spec{} = base_spec, caller) do
    host_tier2? = Noizu.Tessera.Hologram.Adapter.available?()
    base_tier2? = tier2_runtime?(base_spec)

    if host_tier2? != base_tier2? and cross_runtime_risk?(base_spec) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera cross-runtime derivation is not supported (T2-6): #{inspect(base_spec.module)} " <>
            "compiles for the #{if host_tier2?, do: "Lit", else: "Hologram"} runtime, but " <>
            "#{inspect(caller.module)} compiles under " <>
            "#{if host_tier2?, do: "Hologram", else: "Lit"} — derive within the same runtime " <>
            "(EXTENSION-CONTRACT.md §5.10); the base's action bodies are unreachable across runtimes"
    end

    :ok
  end

  defp tier2_runtime?(%Spec{module: mod}) do
    function_exported?(mod, :__tessera_action__, 3) or function_exported?(mod, :action, 3)
  end

  # Only a base whose action bodies would actually be stranded across the
  # runtime boundary trips the guard: fn-AST actions (Tier-1 bodies) with no
  # BEAM entry in a Hologram host, or Hologram action/3 bodies in a Lit host.
  # A base with no actions at all derives surface-only and passes either way.
  defp cross_runtime_risk?(%Spec{actions: actions, module: mod}) do
    has_beam_entry? =
      function_exported?(mod, :__tessera_action__, 3) or function_exported?(mod, :action, 3)

    Enum.any?(actions, & &1[:fn_ast]) or has_beam_entry? or actions == []
  end

  defp guard_tier2_double_use!(caller) do
    if Module.get_attribute(caller.module, :tessera_tier2_derived_from) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "tessera double use: #{inspect(caller.module)} already derived from " <>
            "#{inspect(Module.get_attribute(caller.module, :tessera_tier2_derived_from))} — " <>
            "`use Vendor, tag: …` once per module (EXTENSION-CONTRACT.md §5.1)"
    end

    :ok
  end

  defp tier2_prop_asts(%Spec{} = spec) do
    Enum.map(spec.props, fn p ->
      default = p[:default]
      type = p.type || :any

      if default == nil do
        quote do
          prop unquote(p.name), unquote(type)
        end
      else
        quote do
          prop unquote(p.name), unquote(type), default: unquote(default)
        end
      end
    end)
  end

  # `props:` opt shape shared by the vendor path and derive deltas (T2-7):
  # `prop_name: [type: :, default: :, json: :]` — the contract entries the
  # merge layer and the Hologram @__props__ accumulator both consume.
  defp parse_tier2_props!(opts, %Macro.Env{} = caller) do
    opts
    |> Keyword.get(:props, [])
    |> Enum.map(fn {name, defn} ->
      defn = defn || []

      %{
        name: name,
        type: Keyword.get(defn, :type, :any),
        default: Keyword.get(defn, :default),
        json: Keyword.get(defn, :json, false),
        line: caller.line
      }
    end)
  end

  defp tier2_region_asts(_vendor_module, []), do: []

  defp tier2_region_asts(vendor_module, regions) do
    Enum.map(regions, fn {name, arity} ->
      args = Enum.map(1..arity, &Macro.var(:"arg#{&1}", nil))

      delegate =
        quote do
          def unquote(name)(unquote_splicing(args)),
            do: unquote(vendor_module).unquote(name)(unquote_splicing(args))
        end

      overridable =
        quote do
          defoverridable [{unquote(name), unquote(arity)}]
        end

      [delegate, overridable]
    end)
    |> List.flatten()
  end

  # The merged template markup rides the struct in the contract shape
  # (`raw:` — restored from merge_spec!/3's internal `%{line, markup}` at
  # the %Spec re-wrap).
  defp template_markup(%Spec{template: %{raw: raw}}) when is_binary(raw), do: raw
  defp template_markup(%Spec{}), do: ""

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
