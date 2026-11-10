defmodule Noizu.Tessera.CodegenTest do
  use ExUnit.Case, async: true

  alias Noizu.Tessera.Codegen
  alias Noizu.Tessera.Spec

  # The golden fixtures pin the exact byte output of the generators for the
  # PersonaCard fixture component (every DSL entry kind). The CEM golden is
  # checked in; the CONTRACT golden is gitignored (`*.contract.generated.mjs`)
  # because it is a compile-time artifact, so `contract_golden/0` BOOTSTRAPS
  # it from the current generator on a fresh checkout and then pins it
  # byte-for-byte on every later run. To re-review by eye against
  # CONTRACT.md §2 after an intentional change, delete
  # `test/fixtures/persona_card.contract.generated.mjs` and run the suite.
  @golden_dir Path.expand("../../fixtures", __DIR__)
  @cem_golden File.read!(Path.join(@golden_dir, "persona_card.cem.json"))

  @fixture_spec Tessera.TestFixtures.PersonaCard.__tessera_spec__()

  defp contract_golden do
    path = Path.join(@golden_dir, "persona_card.contract.generated.mjs")

    unless File.exists?(path) do
      File.write!(path, Codegen.contract_module(@fixture_spec))
    end

    File.read!(path)
  end

  describe "contract_module/1" do
    test "is byte-identical to the golden fixture (CONTRACT.md §2)" do
      assert Codegen.contract_module(@fixture_spec) == contract_golden()
    end

    test "is deterministic" do
      assert Codegen.contract_module(@fixture_spec) == Codegen.contract_module(@fixture_spec)
    end

    test "empty spec renders empty lists, default slot and null cy" do
      text =
        Codegen.contract_module(%Spec{
          tag: "bare-thing",
          module: Some.Mod,
          file: nil,
          js: nil
        })

      assert text =~ "tag: \"bare-thing\""
      assert text =~ "attrs:  []"
      assert text =~ "props:  []"
      assert text =~ "events: []"
      assert text =~ "slots:  [\"default\"]"
      assert text =~ "cy: null"
    end

    test "json flag appears only for json props" do
      spec = %Spec{
        tag: "bare-thing",
        props: [
          %{name: :plain, type: :string, json: false, default: nil, line: 1},
          %{name: :encoded, type: :list, json: true, default: [], line: 2}
        ]
      }

      text = Codegen.contract_module(spec)
      assert text =~ "{ name: \"plain\", type: \"string\", default: null }"
      assert text =~ "{ name: \"encoded\", type: \"list\", json: true, default: [] }"
    end
  end

  describe "cem/1" do
    test "is byte-identical to the golden fixture JSON" do
      assert Jason.encode!(Codegen.cem([@fixture_spec]), pretty: true) <> "\n" == @cem_golden
    end

    test "schemaVersion is 1.0.0 and path falls back to the snake module file" do
      cem = Codegen.cem([%Spec{tag: "bare-thing", module: Some.Mod, file: nil, js: nil}])
      assert cem["schemaVersion"] == "1.0.0"
      assert [%{"kind" => "javascript-module", "path" => "bare_thing.ex"}] = cem["modules"]
    end
  end

  describe "write_contract_module/2" do
    @tag :tmp_dir
    test "writes when missing, unchanged when equal, written when changed", %{tmp_dir: tmp_dir} do
      assert Codegen.write_contract_module(@fixture_spec, tmp_dir) == :written

      path = Codegen.contract_path(@fixture_spec, tmp_dir)
      assert File.read!(path) == contract_golden()
      assert Codegen.write_contract_module(@fixture_spec, tmp_dir) == :unchanged

      changed = %Spec{@fixture_spec | cy: "other-hook"}
      assert Codegen.write_contract_module(changed, tmp_dir) == :written
      assert File.read!(path) =~ "cy: \"other-hook\""
    end

    test "contract path uses the snake tag" do
      assert Codegen.contract_path(@fixture_spec, "/tmp/x") ==
               "/tmp/x/persona_card.contract.generated.mjs"

      assert Codegen.snake_tag(@fixture_spec) == "persona_card"
    end
  end
end
