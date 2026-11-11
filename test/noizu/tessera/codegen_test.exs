defmodule Noizu.Tessera.CodegenTest do
  use ExUnit.Case, async: true

  alias Noizu.Tessera.Codegen
  alias Noizu.Tessera.Spec

  # Both goldens pin the exact byte output of the generators for the
  # PersonaCard fixture component (every DSL entry kind) and are CHECKED IN:
  # `persona_card.contract.golden.mjs` (the wire interface, CONTRACT.md §2) and
  # `persona_card.cem.json` (the Custom Elements Manifest). They are handled
  # IDENTICALLY on purpose — the old asymmetry (contract golden
  # self-bootstrapped from the current generator and was gitignored) made the
  # byte-identity test vacuous: on every fresh checkout the golden WAS the
  # output, so it could never fail. A missing golden now fails the suite
  # (`File.read!/1` below), and regeneration is an explicit, reviewed step:
  # `MIX_ENV=test mix tessera.golden` rewrites both files from the current
  # generators. Never bootstrap them in-test.
  @golden_dir Path.expand("../../fixtures", __DIR__)
  @cem_golden File.read!(Path.join(@golden_dir, "persona_card.cem.json"))

  @fixture_spec Tessera.TestFixtures.PersonaCard.__tessera_spec__()

  defp contract_golden do
    # Deliberately NOT `File.exists?` + bootstrap: an absent or stale golden
    # must FAIL here so an intentional codegen change forces a reviewed
    # `mix tessera.golden` regen (CONTRACT.md §2 byte-determinism).
    File.read!(Path.join(@golden_dir, "persona_card.contract.golden.mjs"))
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

    test "declares every tag-scoped var() read with its fallback, sorted (EXTENSION-CONTRACT §7)" do
      spec = %Spec{
        tag: "bare-thing",
        module: Some.Mod,
        styles: [
          %{
            kind: :css,
            value: "a{color:var(--tsr-bare-thing-z, 1px); gap:var(--tsr-bare-thing-a, 2px)}",
            line: 1
          },
          %{kind: :css, value: "b{color:var(--tsr-bare-thing-z, 9px)}", line: 2},
          %{kind: :shared, value: "./s.mjs", line: 3}
        ]
      }

      [declaration] = Codegen.cem([spec])["modules"] |> hd() |> Map.fetch!("declarations")

      assert declaration["cssCustomProperties"] == [
               %{"name" => "--tsr-bare-thing-a", "default" => "2px"},
               %{"name" => "--tsr-bare-thing-z", "default" => "1px"}
             ]
    end

    test "parts: root plus template-declared parts; spec-only components claim none" do
      templated = %Spec{
        tag: "bare-thing",
        module: Some.Mod,
        template: %{
          lexer: :minimal,
          raw: ~s(<div part="row"><b part="cell row"></b></div>),
          render_js: "html``",
          line: 1
        }
      }

      [declaration] = Codegen.cem([templated])["modules"] |> hd() |> Map.fetch!("declarations")

      assert declaration["parts"] == [
               %{"name" => "root"},
               %{"name" => "row"},
               %{"name" => "cell"}
             ]

      [spec_only] =
        Codegen.cem([%Spec{tag: "bare-thing", module: Some.Mod}])["modules"]
        |> hd()
        |> Map.fetch!("declarations")

      assert spec_only["parts"] == []
      assert spec_only["cssCustomProperties"] == []
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
