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
        |> Enum.reject(& &1[:inherited])
        |> Enum.map(&Atom.to_string(&1.name))
        |> MapSet.new(),
      regions: spec.region_overrides |> Enum.map(&Atom.to_string(&1)) |> MapSet.new()
    }

    key = {:tessera_takeover_layers, spec.tag}
    siblings = :persistent_term.get(key, [])

    for other <- siblings, other.depth == entry.depth, other.module != entry.module do
      warn_chain_conflict(spec, entry, other, env, "action(s)", MapSet.intersection(entry.actions, other.actions))
      warn_chain_conflict(spec, entry, other, env, "region(s)", MapSet.intersection(entry.regions, other.regions))
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
    if function_exported?(base_module, :__tessera_action__, 3) do
      clauses =
        Enum.map(action_names, fn name ->
          quote do
            def base_action(unquote(name), params, component),
              do: unquote(base_module).__tessera_action__(unquote(name), params, component)
          end
        end)

      [quote(do: (unquote_splicing(clauses)))]
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
