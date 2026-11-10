defmodule PersonaKitTest do
  use ExUnit.Case, async: true

  describe "package inventory" do
    test "components/0 lists both example components" do
      assert PersonaKit.components() == [PersonaKit.PersonaCard, PersonaKit.PersonaPicker]
    end

    test "manifest/0 aggregates one manifest entry per component" do
      manifest = PersonaKit.manifest()

      assert length(manifest) == 2
      assert %{"tag" => "persona-card"} = Enum.find(manifest, &(&1["tag"] == "persona-card"))
      assert %{"tag" => "persona-picker"} = Enum.find(manifest, &(&1["tag"] == "persona-picker"))
    end
  end

  describe "persona-card spec" do
    test "compiles the contract spec (attrs, json prop, event, cy)" do
      spec = PersonaKit.PersonaCard.__tessera_spec__()

      assert spec.tag == "persona-card"
      assert spec.cy == "persona-card-root"
      assert Enum.any?(spec.attrs, &(&1.name == :display_name and &1.required))
      assert Enum.any?(spec.attrs, &(&1.name == :disabled and &1.type == :boolean))
      assert [%{name: :tag_list, json: true}] = Enum.filter(spec.props, & &1.json)

      assert [%{name: "persona-select", detail: %{persona_id: :string, click_count: :integer}}] =
               spec.events
    end

    test "detail keys round-trip snake→camel→snake (CONTRACT.md §1)" do
      import Noizu.Tessera.Naming, only: [round_trips?: 1]

      assert round_trips?(:persona_id)
      assert round_trips?(:click_count)
      assert round_trips?(:display_name)
      assert round_trips?(:tag_list)
    end
  end

  describe "persona-picker spec" do
    test "compiles the contract spec (json personas prop, persona-picked event)" do
      spec = PersonaKit.PersonaPicker.__tessera_spec__()

      assert spec.tag == "persona-picker"
      assert [%{name: :personas, json: true, default: []}] = spec.props
      assert [%{name: "persona-picked", detail: %{persona_id: :string}}] = spec.events
      assert spec.cy == "persona-picker-root"
    end
  end
end
