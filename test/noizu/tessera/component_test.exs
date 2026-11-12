defmodule Noizu.Tessera.ComponentTest do
  use ExUnit.Case, async: false

  alias Noizu.Tessera.Spec

  @tmp_dir System.tmp_dir!()

  # Compiles `source` as a module whose file lives in a throwaway directory —
  # generated contract modules land there, never in the repo. Unique module
  # names per call so recompiles never collide.
  defp compile_source(body) do
    id = :erlang.unique_integer([:positive])
    mod = "Tessera.Inline.N#{id}"
    path = Path.join(@tmp_dir, "tessera_inline_#{id}.ex")

    source = """
    defmodule #{mod} do
      use Noizu.Tessera.Component, tag: "inline-#{id}", js: "inline_#{id}.mjs"
      #{body}
    end
    """

    Code.compile_string(source, path)
    String.to_atom("Elixir." <> mod)
  end

  defp compile_source(tagged_opts, body) do
    id = :erlang.unique_integer([:positive])
    mod = "Tessera.Inline.N#{id}"
    path = Path.join(@tmp_dir, "tessera_inline_#{id}.ex")

    source = """
    defmodule #{mod} do
      use Noizu.Tessera.Component, #{tagged_opts}
      #{body}
    end
    """

    Code.compile_string(source, path)
    String.to_atom("Elixir." <> mod)
  end

  describe "compiled spec" do
    test "exposes the spec + manifest and keeps DSL order" do
      mod =
        compile_source("""
        attr :display_name, :string, required: true
        attr :disabled, :boolean, default: false
        prop :tag_list, :list, json: true, default: []
        event "persona-select", detail: %{persona_id: :string}
        slot "header"
        cy "inline-root"
        """)

      spec = mod.__tessera_spec__()
      assert %Spec{} = spec
      assert Regex.match?(~r/^inline-\d+$/, spec.tag)
      assert Enum.map(spec.attrs, & &1.name) == [:display_name, :disabled]
      assert Enum.map(spec.props, & &1.name) == [:tag_list]
      assert Enum.map(spec.events, & &1.name) == ["persona-select"]
      assert Enum.map(spec.slots, & &1.name) == ["header"]
      assert spec.cy == "inline-root"
      assert hd(spec.attrs).required == true
      assert List.last(spec.attrs).default == false
      assert hd(spec.props)[:json] == true

      manifest = mod.__tessera_manifest__()
      assert manifest["tag"] == spec.tag
      assert manifest["attrs"] |> hd() |> Map.get("name") == "display-name"
      assert manifest["props"] |> hd() |> Map.get("name") == "tagList"
      assert manifest["events"] |> hd() |> Map.get("name") == "persona-select"
    end

    test "a component with no DSL entries still compiles with an empty spec" do
      mod = compile_source("")
      spec = mod.__tessera_spec__()
      assert spec.attrs == [] and spec.props == [] and spec.events == [] and spec.slots == []
      assert spec.cy == false
    end
  end

  describe "DSL compile-time validation" do
    test "invalid tag option raises with a pointed message" do
      assert_raise CompileError, ~r/invalid tessera tag/, fn ->
        compile_source("tag: \"BadTag\", js: \"x.mjs\"", "")
      end
    end

    test "missing tag option raises" do
      id = :erlang.unique_integer([:positive])
      path = Path.join(@tmp_dir, "tessera_inline_#{id}.ex")

      assert_raise CompileError, fn ->
        Code.compile_string(
          "defmodule Tessera.Inline.M#{id} do\n  use Noizu.Tessera.Component, js: \"x.mjs\"\nend\n",
          path
        )
      end
    end

    test "invalid event grammar raises" do
      assert_raise CompileError, ~r/invalid tessera event/, fn ->
        compile_source("event \"personaselect\"")
      end
    end

    test "event names containing reserved wire characters (`:` `@` `;` whitespace) raise with a pointed message" do
      # These characters delimit the `event:action@target;…` bridge grammar
      # (CONTRACT.md §3) — rejected at compile time, before the generic
      # grammar error, so the author learns WHY the name is unusable.
      for bad <- ["persona@select", "persona:select", "persona;select", "persona select"] do
        assert_raise CompileError, ~r/reserved data-tsr-on character/, fn ->
          compile_source(~s(event "#{bad}"))
        end
      end
    end

    test "tag names containing reserved wire characters raise with a pointed message" do
      assert_raise CompileError, ~r/reserved data-tsr-on character/, fn ->
        compile_source("tag: \"bad@tag-name\", js: \"x.mjs\"", "")
      end
    end

    test "duplicate attr raises with both lines" do
      assert_raise CompileError, ~r/duplicate tessera attr :x/, fn ->
        compile_source("""
        attr :x, :string
        attr :x, :integer
        """)
      end
    end

    test "duplicate prop raises" do
      assert_raise CompileError, ~r/duplicate tessera prop :p/, fn ->
        compile_source("""
        prop :p, :string
        prop :p, :string
        """)
      end
    end

    test "duplicate event raises" do
      assert_raise CompileError, ~r/duplicate tessera event/, fn ->
        compile_source("""
        event "a-b"
        event "a-b"
        """)
      end
    end

    test "duplicate slot raises" do
      assert_raise CompileError, ~r/duplicate tessera slot/, fn ->
        compile_source("""
        slot "header"
        slot "header"
        """)
      end
    end

    test "duplicate cy raises" do
      assert_raise CompileError, ~r/duplicate tessera cy declaration/, fn ->
        compile_source("""
        cy "a-root"
        cy "b-root"
        """)
      end
    end

    test "unknown attr type raises" do
      assert_raise CompileError, ~r/unknown type :datetime/, fn ->
        compile_source("attr :when, :datetime")
      end
    end

    test "unknown prop type raises" do
      assert_raise CompileError, ~r/unknown type :tensor/, fn ->
        compile_source("prop :tensor, :tensor")
      end
    end

    test "attr/prop name collision raises" do
      assert_raise CompileError, ~r/attr\/prop name collision on :x/, fn ->
        compile_source("""
        attr :x, :string
        prop :x, :string
        """)
      end
    end

    test "event binding prop colliding with an author prop raises, naming component + name (F-08)" do
      err =
        assert_raise CompileError, fn ->
          compile_source("""
          prop :on_persona_select, :string
          event "persona-select"
          """)
        end

      assert err.description =~ "binding prop :on_persona_select"
      assert err.description =~ "collides"
      # The pointed message must name the component being compiled.
      assert err.description =~ ~r/Tessera\.Inline\.N\d+/
    end

    test "binding-prop collision raises regardless of declaration order (F-08)" do
      assert_raise CompileError, ~r/binding prop :on_persona_select.*collides/s, fn ->
        compile_source("""
        event "persona-select"
        prop :on_persona_select, :string
        """)
      end
    end

    test "binding-prop collision with an author ATTR raises too (attrs become props) (F-08)" do
      assert_raise CompileError, ~r/binding prop :on_persona_select.*collides/s, fn ->
        compile_source("""
        attr :on_persona_select, :string
        event "persona-select"
        """)
      end
    end

    test "binding-prop collision uses the kebab→snake binding name for multi-word events (F-08)" do
      assert_raise CompileError, ~r/binding prop :on_persona_picked.*collides/s, fn ->
        compile_source("""
        prop :on_persona_picked, :string
        event "persona-picked"
        """)
      end
    end

    test "near-miss prop names do NOT collide with event binding props (F-08)" do
      mod =
        compile_source("""
        prop :persona_select, :string
        prop :on_persona_selected, :string
        event "persona-select"
        """)

      assert Enum.map(mod.__tessera_spec__().props, & &1.name) ==
               [:persona_select, :on_persona_selected]
    end

    test "non-round-tripping attr name raises suggesting a rename" do
      assert_raise CompileError, ~r/col_2_width.*Rename it/s, fn ->
        compile_source("attr :col_2_width, :integer")
      end
    end

    test "non-round-tripping prop name raises" do
      assert_raise CompileError, ~r/foo__bar.*Rename it/s, fn ->
        compile_source("prop :foo__bar, :string")
      end
    end

    test "non-round-tripping event detail key raises" do
      assert_raise CompileError, ~r/does not survive the snake↔camel wire round-trip/, fn ->
        compile_source("event \"a-b\", detail: %{trailing_: :string}")
      end
    end

    test "non-round-tripping state name raises (X-20 compile guard)" do
      assert_raise CompileError, ~r/tessera state :col_2_width.*Rename it/s, fn ->
        compile_source("state :col_2_width, :integer, default: 0")
      end
    end

    test "action internal: annotation lands on the spec entry only when set (D2 advisory)" do
      mod =
        compile_source("""
        template ~TSR"<div></div>"
        action :plain, fn state, _params -> state end
        action :cached, fn state, _params -> state end, internal: true
        """)

      [plain, cached] = mod.__tessera_spec__().actions
      # common entry shape stays byte-identical (no :internal key at all)
      refute Map.has_key?(plain, :internal)
      assert cached.internal == true
    end

    test "non-literal DSL opts raise with a clear message" do
      assert_raise CompileError, ~r/must be compile-time literals/, fn ->
        compile_source("""
        opts = [required: true]
        attr :x, :string, opts
        """)
      end
    end

    test "non-string cy raises" do
      assert_raise CompileError, ~r/cy hook must be a string/, fn ->
        compile_source("cy :atom_hook")
      end
    end
  end

  describe "extension_api declaration (§8.3) — X-15 agreement" do
    alias Noizu.Tessera.Codegen
    alias Noizu.Tessera.Component.LitCodegen

    defp tagged(id, api_opt) do
      ~s|tag: "ext-api-#{id}", js: "ext_api_#{id}.mjs"#{api_opt}|
    end

    test "an element component with no declaration defaults to 1.0.0 everywhere" do
      id = :erlang.unique_integer([:positive])
      mod = compile_source(tagged(id, ""), "")
      spec = mod.__tessera_spec__()

      assert spec.extension_api == "1.0.0"

      # X-15: spec / manifest / CEM / generated static all agree — the same
      # spec object feeds each emitter, so the §8.3 value is byte-identical.
      assert mod.__tessera_manifest__()["extension_api"] == "1.0.0"
      assert hd(Codegen.cem([spec])["modules"])["tessera"]["extensionApi"] == "1.0.0"
      assert LitCodegen.element_module(spec) =~ ~s|extensionApi: "1.0.0"|
    end

    test "a declared extension_api flows into spec, manifest, CEM and the element" do
      id = :erlang.unique_integer([:positive])
      mod = compile_source(tagged(id, ~s|, extension_api: "2.5.1"|), "")
      spec = mod.__tessera_spec__()

      assert spec.extension_api == "2.5.1"
      assert mod.__tessera_manifest__()["extension_api"] == "2.5.1"

      assert hd(Codegen.cem([spec])["modules"])["tessera"] == %{
               "extensionApi" => "2.5.1",
               "actions" => []
             }

      assert LitCodegen.element_module(spec) =~ ~s|extensionApi: "2.5.1"|
    end

    test "a non-version extension_api declaration raises with a pointed message" do
      id = :erlang.unique_integer([:positive])

      assert_raise CompileError, ~r/:extension_api option must be an exact literal semver/, fn ->
        compile_source(tagged(id, ~s|, extension_api: "~> 1.0"|), "")
      end

      assert_raise CompileError, ~r/:extension_api option must be an exact literal semver/, fn ->
        compile_source(tagged(id, ~s|, extension_api: "1"|), "")
      end
    end

    test "the derived lane keeps the base's version when it declares no pin" do
      base_id = :erlang.unique_integer([:positive])
      base = compile_source(tagged(base_id, ~s|, extension_api: "1.2.0"|), "")

      derived_id = :erlang.unique_integer([:positive])
      derived_path = Path.join(@tmp_dir, "tessera_derived_#{derived_id}.ex")

      [{derived, _}] =
        Code.compile_string(
          """
          defmodule Tessera.Inline.D#{derived_id} do
            use #{inspect(base)}, tag: "ext-api-derived-#{derived_id}"
          end
          """,
          derived_path
        )

      assert derived.__tessera_spec__().extension_api == "1.2.0"
    end

    # MAJOR→CompileError / minor→warning proof-of-firing lives in
    # extension_test.exs (check_pin!/3) — compile-time behavior of the
    # `use Base, extension_api:` pin, covered there since brief 2c.
  end

  describe "form_associated DSL (§6.7, brief 2f)" do
    alias Noizu.Tessera.Codegen
    alias Noizu.Tessera.Component.LitCodegen

    @form_opts ~s(tag: "form-probe", js: "form_probe.mjs")

    test "defaults to false and rides NO surface (absent, not false)" do
      id = :erlang.unique_integer([:positive])
      mod = compile_source(~s(tag: "form-off-#{id}", js: "form_off_#{id}.mjs"), "")
      spec = mod.__tessera_spec__()

      assert spec.form_associated == false
      # Absent keeps pre-2f manifest bytes byte-stable; runtimes treat
      # absent/false identically (never attach internals).
      refute Map.has_key?(mod.__tessera_manifest__(), "formAssociated")
      refute Map.has_key?(hd(Codegen.cem([spec])["modules"])["tessera"], "formAssociated")
      refute LitCodegen.element_module(spec) =~ "formAssociated"
    end

    test "declaring true flows into spec, manifest, CEM and the element static" do
      id = :erlang.unique_integer([:positive])

      mod =
        compile_source(
          ~s(tag: "form-on-#{id}", js: "form_on_#{id}.mjs", form_associated: true),
          ""
        )

      spec = mod.__tessera_spec__()

      assert spec.form_associated == true
      assert mod.__tessera_manifest__()["formAssociated"] == true
      assert hd(Codegen.cem([spec])["modules"])["tessera"]["formAssociated"] == true
      assert LitCodegen.element_module(spec) =~ "static formAssociated = true;"
    end

    test "a non-boolean declaration raises with a pointed message" do
      id = :erlang.unique_integer([:positive])

      assert_raise CompileError, ~r/:form_associated option must be a boolean/, fn ->
        compile_source(
          ~s(tag: "form-bad-#{id}", js: "form_bad_#{id}.mjs", form_associated: "yes"),
          ""
        )
      end
    end

    test "a derived spec inherits the base's participation unless it declares its own" do
      base_id = :erlang.unique_integer([:positive])

      base =
        compile_source(
          ~s(tag: "form-base-#{base_id}", js: "form_base_#{base_id}.mjs", form_associated: true),
          ""
        )

      derived_id = :erlang.unique_integer([:positive])
      derived_path = Path.join(@tmp_dir, "tessera_form_derived_#{derived_id}.ex")

      [{derived, _}] =
        Code.compile_string(
          """
          defmodule Tessera.Inline.F#{derived_id} do
            use #{inspect(base)}, tag: "form-derived-#{derived_id}"
          end
          """,
          derived_path
        )

      # Additive: participation flows down the chain, never silently dropped.
      assert derived.__tessera_spec__().form_associated == true
      assert derived.__tessera_manifest__()["formAssociated"] == true

      assert LitCodegen.element_module(derived.__tessera_spec__()) =~
               "static formAssociated = true;"
    end
  end

  describe "styles DSL" do
    @styles_opts ~s(tag: "styles-probe", js: "styles_probe.mjs")

    test "records a single plain-string entry" do
      mod = compile_source(@styles_opts, ~s(styles ":host { color: red; }"))

      assert [%{kind: :css, value: ":host { color: red; }", line: line}] =
               mod.__tessera_spec__().styles

      assert is_integer(line)
    end

    test "records a ~CSS sigil block" do
      mod =
        compile_source(
          @styles_opts,
          ~s|styles ~CSS":host{color:var(--tsr-styles-probe-accent, #6cf)}"|
        )

      assert [%{kind: :css, value: ":host{color:var(--tsr-styles-probe-accent, #6cf)}"}] =
               mod.__tessera_spec__().styles
    end

    test "composes a static list in declaration order (css, string, shared)" do
      mod =
        compile_source(
          @styles_opts,
          ~s(styles [~CSS"a{}", "b{}", {:shared, "./shared_styles.mjs"}])
        )

      assert Enum.map(mod.__tessera_spec__().styles, &{&1.kind, &1.value}) == [
               {:css, "a{}"},
               {:css, "b{}"},
               {:shared, "./shared_styles.mjs"}
             ]
    end

    test "repeated styles declarations append in order" do
      mod =
        compile_source(@styles_opts, """
        styles "a{}"
        styles [{:shared, "./s.mjs"}, "b{}"]
        """)

      assert Enum.map(mod.__tessera_spec__().styles, & &1.value) == ["a{}", "./s.mjs", "b{}"]
    end

    test "manifest exposes the styles entries" do
      mod =
        compile_source(@styles_opts, ~s(styles [~CSS"a{}", {:shared, "./s.mjs"}]))

      assert mod.__tessera_manifest__()["styles"] == [
               %{"kind" => "css", "value" => "a{}"},
               %{"kind" => "shared", "value" => "./s.mjs"}
             ]
    end

    test "styles without a template compile (spec-only theming declarations)" do
      mod = compile_source(@styles_opts, ~s(styles "a{}"))
      spec = mod.__tessera_spec__()
      assert spec.template == nil
      assert [%{kind: :css}] = spec.styles
    end

    test "styles with a template reach the generated element module" do
      mod =
        compile_source(@styles_opts, """
        styles [~CSS".x{color:var(--tsr-styles-probe-accent, #6cf)}", {:shared, "./shared_styles.mjs"}]
        template ~TSR"<div class=\\\"x\\\"></div>"
        """)

      spec = mod.__tessera_spec__()
      dir = Path.dirname(spec.file)
      element = File.read!(Path.join(dir, "styles-probe.element.generated.mjs"))

      assert element =~ "static styles = ["
      assert element =~ "baseStyles"
      assert element =~ ".x{color:var(--tsr-styles-probe-accent, #6cf)}"
      assert element =~ ~s|import { styles as __tsrSharedStyles0 } from "./shared_styles.mjs";|
      assert element =~ ~s|this.setAttribute("part", "root");|
    end

    test "non-literal styles entries raise with a pointed message" do
      assert_raise CompileError, ~r/styles entries must be/, fn ->
        compile_source(@styles_opts, "some_var = \"a{}\"\nstyles some_var")
      end
    end

    test "an empty css string raises" do
      assert_raise CompileError, ~r/non-empty string/, fn ->
        compile_source(@styles_opts, ~s(styles ""))
      end
    end

    test "an empty styles list raises" do
      assert_raise CompileError, ~r/styles list is empty/, fn ->
        compile_source(@styles_opts, "styles []")
      end
    end

    test "a tag-scoped var() read without a fallback raises, naming the property" do
      assert_raise CompileError, ~r/--tsr-styles-probe-accent.*must carry a fallback/s, fn ->
        compile_source(@styles_opts, ~s|styles ~CSS"a{color:var(--tsr-styles-probe-accent)}"|)
      end
    end

    test "an unbalanced var( raises a line-accurate CompileError" do
      assert_raise CompileError, ~r/unbalanced var/, fn ->
        compile_source(@styles_opts, ~s|styles ~CSS"a{color:var(--tsr-styles-probe-a, 1px}"|)
      end
    end

    test "a non-string shared path raises" do
      assert_raise CompileError, ~r/styles entries must be/, fn ->
        compile_source(@styles_opts, "styles {:shared, 123}")
      end
    end

    test "an unknown entry shape raises" do
      assert_raise CompileError, ~r/styles entries must be/, fn ->
        compile_source(@styles_opts, "styles :nope")
      end
    end
  end

  describe "css/part DSL" do
    test "css and part declarations land in the spec and the manifest" do
      mod =
        compile_source("""
        css "--inline-accent", default: "#ffffff"
        part "select-button"
        """)

      spec = mod.__tessera_spec__()
      assert [%{name: "--inline-accent", default: "#ffffff"}] = spec.css_properties
      assert [%{name: "select-button"}] = spec.parts

      manifest = mod.__tessera_manifest__()
      assert manifest["cssProperties"] == [%{"name" => "--inline-accent", "default" => "#ffffff"}]
      assert manifest["parts"] == ["select-button"]
    end

    test "css/part are CEM metadata — they do not ride the wire contract" do
      mod =
        compile_source("""
        css "--inline-accent", default: "#ffffff"
        part "select-button"
        """)

      contract = Noizu.Tessera.Codegen.contract_module(mod.__tessera_spec__())
      refute contract =~ "inline-accent"
      refute contract =~ "select-button"
    end

    test "invalid css name raises" do
      assert_raise CompileError, ~r/tessera css property/, fn ->
        compile_source("css \"accent\"")
      end
    end

    test "non-string css default raises" do
      assert_raise CompileError, ~r/default must be a string/, fn ->
        compile_source("css \"--inline-gap\", default: 4")
      end
    end

    test "invalid part name raises" do
      assert_raise CompileError, ~r/tessera part name/, fn ->
        compile_source("part \"Select\"")
      end
    end

    test "duplicate css / part declarations raise" do
      assert_raise CompileError, ~r/duplicate tessera css/, fn ->
        compile_source("css \"--inline-a\"\ncss \"--inline-a\"")
      end

      assert_raise CompileError, ~r/duplicate tessera part/, fn ->
        compile_source("part \"go\"\npart \"go\"")
      end
    end
  end

  describe "package macro" do
    test "exposes components/0 and manifest/0" do
      assert Tessera.TestFixtures.Package.components() == [Tessera.TestFixtures.PersonaCard]

      [entry] = Tessera.TestFixtures.Package.manifest()
      assert entry["tag"] == "persona-card"
      assert entry["module"] == "Tessera.TestFixtures.PersonaCard"
    end

    test "exposes the __tessera_package__/0 marker and cem/0 (gallery by default)" do
      assert Tessera.TestFixtures.Package.__tessera_package__() == %{
               components: [Tessera.TestFixtures.PersonaCard]
             }

      cem = Tessera.TestFixtures.Package.cem()
      assert cem["schemaVersion"] == "1.0.0"
      assert [module] = cem["modules"]
      assert [decl] = module["declarations"]
      assert decl["tagName"] == "persona-card"

      assert decl["cssProperties"] == [
               %{"name" => "--persona-card-accent", "default" => "#6366f1"},
               %{"name" => "--tsr-persona-card-accent", "default" => "#6cf"},
               %{"name" => "--tsr-persona-card-gap", "default" => "4px"}
             ]

      assert decl["cssParts"] == [%{"name" => "select-button"}]
    end

    test "rejects non-tessera modules that are already compiled" do
      id = :erlang.unique_integer([:positive])
      path = Path.join(@tmp_dir, "tessera_inline_pkg_#{id}.ex")

      assert_raise CompileError, ~r/is not a tessera component/, fn ->
        Code.compile_string(
          "defmodule Tessera.Inline.Pkg#{id} do\n  use Noizu.Tessera.Package, components: [String]\nend\n",
          path
        )
      end
    end
  end

  describe "top-level register() check" do
    alias Noizu.Tessera.Hologram.Adapter

    test "detects a top-level register() call" do
      assert Adapter.has_top_level_register?("import x\n\nregister();\n")
      assert Adapter.has_top_level_register?("register()\n")
      assert Adapter.has_top_level_register?("export function register() {}\n\nregister()")
      # Leading whitespace (indentation) is tolerated.
      assert Adapter.has_top_level_register?("{\n  register();\n}\n")
      assert Adapter.has_top_level_register?("\tregister()\n")
      refute Adapter.has_top_level_register?("export function register() {}\n")
      refute Adapter.has_top_level_register?("// register();\n")
      refute Adapter.has_top_level_register?("foo.register();\n")
      # Only a standalone STATEMENT counts, never an inline call.
      refute Adapter.has_top_level_register?("foo(); register();\n")
    end

    test "warns at compile time when a component .mjs lacks the load-bearing call" do
      import ExUnit.CaptureIO

      id = :erlang.unique_integer([:positive])
      mjs = Path.join(@tmp_dir, "no_register_#{id}.mjs")
      File.write!(mjs, "export function register() {}\n")

      warnings =
        capture_io(:stderr, fn ->
          assert :ok = Adapter.warn_missing_top_level_register(mjs)
        end)

      assert warnings =~ "no top-level `register()` call"
    end
  end

  describe "property options (lit-parity 1c)" do
    test "attr carries attribute rename + reflect into the entry, manifest and element" do
      mod =
        compile_source("""
        attr :display_name, :string, attribute: "data-name", reflect: true
        state :count, :integer, default: 0
        template ~TSR"<div>{@count}</div>"
        """)

      spec = mod.__tessera_spec__()
      entry = hd(spec.attrs)
      assert entry[:attribute] == "data-name"
      assert entry[:reflect] == true

      manifest = mod.__tessera_manifest__()
      m_entry = hd(manifest["attrs"])
      assert m_entry["attribute"] == "data-name"
      assert m_entry["reflect"] == true

      element = File.read!(Path.join(@tmp_dir, "#{spec.tag}.element.generated.mjs"))
      assert element =~ ~S|displayName: { type: String, attribute: "data-name", reflect: true }|
    end

    test "attribute: false disables the attribute; prop and state accept the opts too" do
      mod =
        compile_source("""
        attr :tone, :string, attribute: false
        prop :tag_list, :list, attribute: "data-tags", reflect: true
        state :count, :integer, default: 0, attribute: false
        template ~TSR"<div>{@count}</div>"
        """)

      spec = mod.__tessera_spec__()
      assert hd(spec.attrs)[:attribute] == false
      assert hd(spec.props)[:attribute] == "data-tags"
      assert hd(spec.props)[:reflect] == true
      assert hd(spec.state)[:attribute] == false

      element = File.read!(Path.join(@tmp_dir, "#{spec.tag}.element.generated.mjs"))
      assert element =~ "tone: { type: String, attribute: false }"
      assert element =~ ~S|tagList: { type: Array, attribute: "data-tags", reflect: true }|
      assert element =~ "count: { type: Number, attribute: false }"
    end

    test "absent opts keep entries unchanged (no attribute/reflect keys)" do
      mod = compile_source("attr :tone, :string")
      entry = hd(mod.__tessera_spec__().attrs)
      refute Map.has_key?(entry, :attribute)
      refute Map.has_key?(entry, :reflect)
      refute Map.has_key?(hd(mod.__tessera_manifest__()["attrs"]), "attribute")
    end

    test "invalid attribute/reflect values raise pointed CompileErrors" do
      for {opts, match} <- [
            {"attribute: true", "attribute:"},
            {"attribute: 123", "attribute:"},
            {"attribute: \"bad name\"", "attribute:"},
            {"attribute: \"\"", "attribute:"},
            {"reflect: \"yes\"", "reflect:"}
          ] do
        assert_raise CompileError, ~r/#{Regex.escape(match)}/, fn ->
          compile_source("attr :tone, :string, #{opts}")
        end
      end
    end
  end

  describe "lifecycle DSL (lit-parity 1c)" do
    @lifecycle_body """
    state :count, :integer, default: 0
    event "hook-ping", detail: %{n: :integer}
    template ~TSR"<div>{@count}</div>"
    """

    test "all four hooks translate and land in spec.lifecycle + the manifest" do
      mod =
        compile_source(
          @lifecycle_body <>
            """
            should_update fn state, _changed -> state.count < 5 end
            will_update fn state, _changed -> %{state | count: state.count + 1} end
            first_updated fn state, _changed -> emit("hook-ping", %{n: state.count}) end
            updated fn state, _changed -> emit("hook-ping", %{n: state.count}) end
            """
        )

      spec = mod.__tessera_spec__()
      assert spec.lifecycle[:should_update].js == "(state.count < 5)"
      assert spec.lifecycle[:will_update].js == "({ ...state, count: (state.count + 1) })"
      assert spec.lifecycle[:first_updated].js == ~s|emit(this, "hook-ping", {n: state.count})|
      assert spec.lifecycle[:updated].js == ~s|emit(this, "hook-ping", {n: state.count})|

      assert mod.__tessera_manifest__()["lifecycle"] ==
               ["should_update", "will_update", "first_updated", "updated"]

      element = File.read!(Path.join(@tmp_dir, "#{spec.tag}.element.generated.mjs"))
      assert element =~ "shouldUpdate(changedProperties) {"
      assert element =~ "willUpdate(changedProperties) {"
      assert element =~ "firstUpdated(changedProperties) {"
      assert element =~ "updated(changedProperties) {"
      assert element =~ "const changed = Object.fromEntries(changedProperties);"
    end

    test "a differently-named second argument is rejected (the binding is `changed`)" do
      assert_raise CompileError, ~r/second argument must be named `changed`/, fn ->
        compile_source(
          @lifecycle_body <>
            """
            will_update fn state, delta -> %{state | count: delta.count} end
            """
        )
      end
    end

    test "a hook reading an undeclared state key raises at compile time" do
      assert_raise CompileError, ~r/not a declared state key/, fn ->
        compile_source(
          @lifecycle_body <>
            """
            updated fn state, _changed -> %{state | count: state.nope} end
            """
        )
      end
    end

    test "a hook outside the subset is rejected by name" do
      assert_raise CompileError, ~r/case/, fn ->
        compile_source(
          @lifecycle_body <>
            """
            will_update fn state, _changed -> case state.count do 0 -> state end end
            """
        )
      end
    end

    test "duplicate hook declarations raise" do
      assert_raise CompileError, ~r/duplicate tessera lifecycle hook :updated/, fn ->
        compile_source(
          @lifecycle_body <>
            """
            updated fn state, _changed -> state end
            updated fn state, _changed -> state end
            """
        )
      end
    end

    test "wrong arity / multi-clause / pattern second arg raise" do
      assert_raise CompileError, ~r/exactly two arguments/, fn ->
        compile_source(@lifecycle_body <> "updated fn state -> state end")
      end

      assert_raise CompileError, ~r/exactly two arguments/, fn ->
        compile_source(@lifecycle_body <> "updated fn state, a, b -> state end")
      end

      assert_raise CompileError, ~r/single-clause|exactly two arguments/, fn ->
        compile_source(
          @lifecycle_body <>
            """
            updated fn
              state, _changed -> state
              state, _changed -> state
            end
            """
        )
      end

      assert_raise CompileError, ~r/second argument must be named `changed`/, fn ->
        compile_source(
          @lifecycle_body <>
            """
            updated fn state, %{count: c} -> state end
            """
        )
      end
    end

    test "lifecycle without a template raises (element DSL is all-or-nothing)" do
      assert_raise CompileError, ~r/all-or-nothing/, fn ->
        compile_source("""
        state :count, :integer, default: 0
        updated fn state, _changed -> state end
        """)
      end
    end

    test "no hooks → empty lifecycle map and no lifecycle methods in the element" do
      mod =
        compile_source("""
        state :count, :integer, default: 0
        template ~TSR"<div>{@count}</div>"
        """)

      assert mod.__tessera_spec__().lifecycle == %{}
      assert mod.__tessera_manifest__()["lifecycle"] == []

      element =
        File.read!(Path.join(@tmp_dir, "#{mod.__tessera_spec__().tag}.element.generated.mjs"))

      refute element =~ "shouldUpdate"
      refute element =~ "willUpdate"
      refute element =~ "firstUpdated"
      refute element =~ "updated(changedProperties)"
    end
  end

  describe "render_root: :light (lit-parity #96, BoE #1)" do
    alias Noizu.Tessera.Component.LitCodegen

    defp light_opts(id, extra) do
      ~s|tag: "light-#{id}", js: "light_#{id}.mjs"#{extra}|
    end

    @light_body """
    state :count, :integer, default: 0
    template ~TSR"<p>{@count}</p>"
    """

    test "a light component renders into the element and says so in the manifest" do
      id = :erlang.unique_integer([:positive])
      mod = compile_source(light_opts(id, ", render_root: :light"), @light_body)
      spec = mod.__tessera_spec__()

      assert spec.render_root == :light
      assert mod.__tessera_manifest__()["renderRoot"] == "light"

      js = LitCodegen.element_module(spec)
      assert js =~ "createRenderRoot() {"
      assert js =~ "return this;"
      # styles adopted additively, never via Lit's replacing adoptStyles
      assert js =~ "[...root.adoptedStyleSheets, ...add]"
    end

    test "the default stays a shadow root with no manifest key" do
      id = :erlang.unique_integer([:positive])
      mod = compile_source(light_opts(id, ""), @light_body)

      assert mod.__tessera_spec__().render_root == :shadow
      refute Map.has_key?(mod.__tessera_manifest__(), "renderRoot")
      refute LitCodegen.element_module(mod.__tessera_spec__()) =~ "createRenderRoot"
    end

    test "an unknown render_root raises" do
      id = :erlang.unique_integer([:positive])

      assert_raise CompileError,
                   ~r/:render_root option must be :shadow \(default\) or :light/,
                   fn ->
                     compile_source(light_opts(id, ", render_root: :open"), @light_body)
                   end
    end

    test "light DOM cannot declare slots" do
      id = :erlang.unique_integer([:positive])

      assert_raise CompileError, ~r/render_root: :light cannot declare slots/, fn ->
        compile_source(light_opts(id, ", render_root: :light"), """
        slot "header"
        """)
      end
    end
  end
end
