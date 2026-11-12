# Conformance fixture generator (brief 4b case-fill).
#
# Compiles the DSL fixture components in test/support/conformance/*.ex into
# the Tier-1 WTR fixture directory js/test/fixtures/conformance/, so the
# conformance lane (`cd js && npm run test:fast`) runs against REAL generated
# Lit elements without an Elixir compile step at test time.
#
# TESSER-019: the FromLitPanel spec module is NOT a hand-written DSL fixture —
# it is the real `mix tessera.from_lit` output for
# test/fixtures/from_lit/dashboard_panel.ts, regenerated below into the
# committed test/support/conformance/generated/conf_from_lit.generated.ex, so
# converter-rule changes are exercised by the live WTR render lane.
#
# The generated files are committed (reviewed artifacts, like the goldens):
# the element module's `@noizu/tessera-core` import is rewritten to a relative
# path into priv/js/src (js/ has no @noizu/tessera-core dependency — the core
# tests import the source directly), and the contract module is renamed
# `<snake>.contract.mjs` (the repo gitignores `*.contract.generated.mjs`).
#
# Regenerate after a DSL/codegen change, then REVIEW the diff:
#
#     MIX_ENV=test mix run test/conformance/support/generate_fixtures.exs
#
# Verify the committed fixtures are current (CI-style, no write):
#
#     MIX_ENV=test mix run test/conformance/support/generate_fixtures.exs -- --check

alias Noizu.Tessera.Codegen
alias Noizu.Tessera.Component.Extension
alias Noizu.Tessera.Component.LitCodegen
alias Noizu.Tessera.Spec
alias Noizu.Tessera.FromLit.Extractor
alias Noizu.Tessera.FromLit.Generator

check? = "--check" in System.argv()

# ---------------------------------------------------------------------------
# TESSER-019 (QA re-gate): the FromLitPanel fixture is CONVERTER-GENERATED.
#
# The spec module below is the real `mix tessera.from_lit` output —
# FromLit.Extractor.extract_file/1 + FromLit.Generator.generate/4, the exact
# modules the mix task runs — for test/fixtures/from_lit/dashboard_panel.ts,
# written to a COMMITTED path (so `-- --check` compares deterministic bytes)
# and compiled before the fixture list is evaluated. A converter-rule change
# (e.g. the ternary→{%if} lowering in FromLit.Render) therefore changes the
# committed fixture AND the live WTR render (js/test/from_lit_render.test.mjs).
# The hand-ported test/support/conformance/conf_from_lit.ex this replaces
# never touched the converter, which is why a converter mutation used to
# leave WTR green with byte-identical fixtures.
#
# Documented post-processing — convention-only, converter output otherwise
# verbatim; every replacement RAISES if its anchor disappears, so converter
# drift cannot silently produce a half-ported fixture:
#   * data-cy hooks — the conformance selector convention, absent from the
#     original Lit markup by design (matches the other conf_* fixtures);
#   * the `tick` action body — the converter deliberately emits a no-op stub
#     ("port the method body"); this fixture renders LIVE behavior, so the
#     stub is promoted to the real port of Lit tick() (state increment).
# ---------------------------------------------------------------------------

from_lit_module = Tessera.TestFixtures.Conformance.FromLitPanel

from_lit_path =
  Path.expand("test/support/conformance/generated/conf_from_lit.generated.ex", File.cwd!())

{:ok, from_lit_shape} = Extractor.extract_file("test/fixtures/from_lit/dashboard_panel.ts")
from_lit_shape = Map.put(from_lit_shape, "tag", "tsr-conf-from-lit-panel")

{from_lit_files, _from_lit_warnings} =
  Generator.generate(
    from_lit_shape,
    "Tessera.TestFixtures.Conformance.FromLitPanel",
    Path.join(System.tmp_dir!(), "tessera-fromlit-scratch")
  )

{_, from_lit_source} =
  Enum.find(from_lit_files, fn {path, _} -> String.ends_with?(path, ".ex") end)

# Each anchor must occur EXACTLY once: a missing anchor means the converter
# output drifted, and a repeated one means first-match replacement could hit
# the wrong node (robot review on #64).
sub! = fn source, pattern, replacement ->
  case length(String.split(source, pattern)) - 1 do
    1 ->
      String.replace(source, pattern, replacement, global: false)

    0 ->
      Mix.raise(
        "generate_fixtures: from_lit post-process anchor missing — converter output drifted:\n  #{pattern}"
      )

    n ->
      Mix.raise(
        "generate_fixtures: from_lit post-process anchor is ambiguous (#{n} matches):\n  #{pattern}"
      )
  end
end

from_lit_source =
  from_lit_source
  # Conformance data-cy hooks (see above): root + the elements the WTR test queries.
  |> sub!.(
    ~s|<section class="panel">|,
    ~s|<section class="panel" data-cy="tsr-conf-from-lit-panel-root">|
  )
  |> sub!.("<h3>{@panel_title}</h3>", ~s|<h3 data-cy="from-lit-title">{@panel_title}</h3>|)
  |> sub!.(~s|<p class="mode">|, ~s|<p class="mode" data-cy="from-lit-mode">|)
  |> sub!.("<ul>", ~s|<ul data-cy="from-lit-list">|)
  |> sub!.(
    ~s|<button type="button" $click={:tick}>tick</button>|,
    ~s|<button type="button" data-cy="from-lit-tick" $click={:tick}>tick</button>|
  )
  |> sub!.(~s|<span class="ticks">|, ~s|<span class="ticks" data-cy="from-lit-ticks">|)
  # Promote the converter's no-op action stub to the real port of Lit tick(),
  # and keep the retained converter comment truthful about it.
  |> sub!.(
    "port the method body (state/emit DSL); no-op stub.",
    "ported by generate_fixtures.exs post-processing (real port of Lit tick())."
  )
  |> sub!.(
    "action(:tick, fn state, _params -> state end)",
    "action(:tick, fn state, _params -> %{state | tick_count: state.tick_count + 1} end)"
  )
  # Provenance header (deterministic — part of the committed bytes).
  |> then(fn source ->
    header =
      "# GENERATED by test/conformance/support/generate_fixtures.exs — the real\n" <>
        "# `mix tessera.from_lit` output (FromLit.Extractor + FromLit.Generator) for\n" <>
        "# test/fixtures/from_lit/dashboard_panel.ts. Do not edit by hand; regenerate\n" <>
        "# and review. Documented post-processing (see generate_fixtures.exs):\n" <>
        "# data-cy conformance hooks + tick action promoted from the converter's\n" <>
        "# no-op stub to the real port of Lit tick().\n\n"

    header <> source
  end)

File.mkdir_p!(Path.dirname(from_lit_path))

# Run the converter output through the PROJECT formatter (.formatter.exs,
# incl. the DSL's locals_without_parens) so the committed artifact is
# byte-identical to what `mix format --check-formatted` expects. CI's format
# gate failed on raw converter output (PR #64, b274470).
from_lit_source =
  (fn source ->
     {formatter, _opts} = Mix.Tasks.Format.formatter_for_file(from_lit_path)
     formatter.(source)
   end).(from_lit_source)

cond do
  check? ->
    unless Code.ensure_loaded?(from_lit_module) do
      Mix.raise(
        "generate_fixtures: #{inspect(from_lit_module)} is not compiled — the committed " <>
          "converter-generated fixture is missing. Run without --check once:\n" <>
          "  MIX_ENV=test mix run test/conformance/support/generate_fixtures.exs"
      )
    end

  true ->
    File.write!(from_lit_path, from_lit_source)
    # Reload from the just-written source so __tessera_spec__/element/contract
    # emission below uses the converter's CURRENT output (the project compile
    # may have loaded a stale beam of the previously committed file).
    Code.compile_file(from_lit_path)
end

fixtures = [
  Tessera.TestFixtures.Conformance.State,
  Tessera.TestFixtures.Conformance.Template,
  Tessera.TestFixtures.Conformance.Styles,
  Tessera.TestFixtures.Conformance.Slots,
  Tessera.TestFixtures.Conformance.Directives,
  Tessera.TestFixtures.Conformance.Pipeline,
  # lit-parity #63 (keyed {%for} → repeat) — consumed by js/test/repeat.test.mjs.
  Tessera.TestFixtures.Conformance.Repeat,
  # lit-parity #67 (live + .prop bindings) — consumed by js/test/live.test.mjs.
  Tessera.TestFixtures.Conformance.Live,
  # lit-parity #71/#66 (unsafe_html, guard) — js/test/unsafe_guard.test.mjs.
  Tessera.TestFixtures.Conformance.UnsafeGuard,
  # lit-parity #96 (render_root: :light) — consumed by js/test/light_dom.test.mjs.
  Tessera.TestFixtures.Conformance.Light,
  # X-17 (brief 2d): the first DERIVED conformance pair — the vendor element
  # replaces the base's `:row` region via slot_template + {%super%}. Its
  # generated element imports the base element by relative path, which lands
  # correctly because both fixtures are emitted into the same directory.
  Tessera.TestFixtures.Conformance.RegionBase,
  Tessera.TestFixtures.Conformance.RegionVendor,
  # X-19 (brief 2e): the D1 tag-takeover chain. `Takeover` mirrors `Pipeline`
  # (same data-cy surface, so the base-suite bodies replay verbatim), and the
  # three `tag: :inherit` layers compile to registry MIXINS emitted under
  # suffixed stems (`<base-tag>__<module>`) — the harness imports the layers
  # BEFORE the base so defineOnce composes the whole chain at first define.
  Tessera.TestFixtures.Conformance.Takeover,
  Tessera.TestFixtures.Conformance.TakeoverExtAaa,
  Tessera.TestFixtures.Conformance.TakeoverExtBbb,
  Tessera.TestFixtures.Conformance.TakeoverExtCcc,
  # FM-01…FM-03 (brief 2f): the Tier-1 form fixture — declares
  # `form_associated: true`, so its generated element carries
  # `static formAssociated = true` and the manifest the `formAssociated` key.
  Tessera.TestFixtures.Conformance.Form,
  # TESSER-019: a `mix tessera.from_lit` conversion of
  # test/fixtures/from_lit/dashboard_panel.ts — the spec module is GENERATED
  # by the converter block above (never hand-ported), so converter-rule
  # changes bite this LIVE render: js/test/from_lit_render.test.mjs.
  Tessera.TestFixtures.Conformance.FromLitPanel
]

out_dir = Path.expand("js/test/fixtures/conformance", File.cwd!())
# Relative path from js/test/fixtures/conformance/ back to the repo root.
core_rel = "../../../../priv/js/src/index.mjs"

File.mkdir_p!(out_dir)

# X-15 (§9): the manifest side of the static/manifest/CEM agreement. Every
# fixture's `Spec.to_manifest_map/1` output, exported as one JS module the
# conformance case imports — the runtime statics MUST equal these entries.
manifests_path = Path.join(out_dir, "conformance_manifests.generated.mjs")

manifests_source =
  "// Generated by test/conformance/support/generate_fixtures.exs — do not edit.\n" <>
    "// X-15: tag -> Spec.to_manifest_map/1 output for every conformance fixture;\n" <>
    "// the conformance case asserts the runtime statics (tesseraExtensionApi,\n" <>
    "// tesseraActions) agree with these manifest entries. Tag-takeover LAYERS\n" <>
    "// are excluded: their specs key by the BASE tag (§5.8) and would collide\n" <>
    "// with the vendor entry — the base's own manifest row already covers them.\n" <>
    "export const manifests = " <>
    Jason.encode!(
      fixtures
      |> Enum.map(fn mod -> mod.__tessera_spec__() end)
      |> Enum.reject(&Extension.takeover?/1)
      |> Map.new(fn spec ->
        # Repo-relative `file` so the committed fixture is identical on every
        # checkout/worktree and never leaks a local home path (TESSER-003).
        manifest = Spec.to_manifest_map(spec)
        file = manifest["file"] && Path.relative_to(manifest["file"], File.cwd!())
        {spec.tag, Map.put(manifest, "file", file)}
      end),
      pretty: true
    ) <>
    ";\nexport default manifests;\n"

artifacts =
  for mod <- fixtures do
    unless Code.ensure_loaded?(mod) do
      Mix.raise(
        "generate_fixtures: #{inspect(mod)} is not compiled — fixtures live in " <>
          "test/support (test env only). Run: MIX_ENV=test mix run " <>
          "test/conformance/support/generate_fixtures.exs"
      )
    end

    spec = mod.__tessera_spec__()
    snake_stem = Extension.snake_stem(spec)

    # WTR-only tail swap (brief 2f): the shared emission auto-registers the
    # bare generated class on import; the harness's ConfFormRecording subclass
    # for <tsr-conf-form> must OWN the tag instead (else the bare class wins
    # the registry race and the FM push-per-render seam silently vanishes).
    # The harness seeds globalThis.__tesseraNoAutoRegister before importing;
    # the exported register() stays available for explicit registration.
    # Goldens/lib bytes untouched — this rewrite lives only in WTR fixtures.
    element =
      spec
      |> LitCodegen.element_module()
      |> String.replace(~s|from "@noizu/tessera-core"|, ~s|from "#{core_rel}"|)
      |> String.replace(
        ~s|from "./#{snake_stem}.contract.generated.mjs"|,
        ~s|from "./#{snake_stem}.contract.mjs"|
      )
      |> String.replace(
        "register();",
        """
        if (!(globalThis.__tesseraNoAutoRegister ?? []).includes("#{spec.tag}")) register();\
        """,
        global: false
      )

    contract = Codegen.contract_module(spec)

    %{
      element_path: LitCodegen.element_path(spec, out_dir),
      element: element,
      contract_path: Path.join(out_dir, "#{snake_stem}.contract.mjs"),
      contract: contract
    }
  end

expected_files =
  [
    # The converter-generated spec module itself is a committed artifact and
    # participates in the same check (TESSER-019).
    {from_lit_path, from_lit_source},
    {manifests_path, manifests_source}
  ] ++
    Enum.flat_map(artifacts, fn a ->
      [{a.element_path, a.element}, {a.contract_path, a.contract}]
    end)

if check? do
  stale =
    for {path, content} <- expected_files,
        not File.exists?(path) or File.read!(path) != content do
      path
    end

  if stale == [] do
    Mix.shell().info("generate_fixtures: #{length(artifacts)} fixtures current.")
  else
    Mix.raise(
      "generate_fixtures: STALE committed fixtures (regenerate + review):\n  " <>
        Enum.join(stale, "\n  ")
    )
  end
else
  for {path, content} <- expected_files do
    File.write!(path, content)
  end

  Mix.shell().info(
    "generate_fixtures: wrote #{length(artifacts)} fixtures to js/test/fixtures/conformance/ — " <>
      "REVIEW the diff before committing."
  )
end
