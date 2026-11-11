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

  describe "package macro" do
    test "exposes components/0 and manifest/0" do
      assert Tessera.TestFixtures.Package.components() == [Tessera.TestFixtures.PersonaCard]

      [entry] = Tessera.TestFixtures.Package.manifest()
      assert entry["tag"] == "persona-card"
      assert entry["module"] == "Tessera.TestFixtures.PersonaCard"
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
end
