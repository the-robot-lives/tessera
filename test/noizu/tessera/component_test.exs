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
end
