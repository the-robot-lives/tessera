defmodule Noizu.Tessera.FromLit.ExtractorTest do
  use ExUnit.Case, async: true

  alias Noizu.Tessera.FromLit.Extractor

  @fixture_dir Path.expand("../../../fixtures/lit", __DIR__)
  @persona Extractor.extract_file(Path.join(@fixture_dir, "persona_widget.ts")) |> elem(1)
  @legacy Extractor.extract_file(Path.join(@fixture_dir, "legacy_widget.js")) |> elem(1)

  defp prop(shape, name), do: Enum.find(shape["properties"], &(&1["name"] == name))
  defp event(shape, name), do: Enum.find(shape["events"], &(&1["name"] == name))

  describe "persona_widget.ts — tag, class, decorated properties" do
    test "extracts the @customElement tag and the LitElement class" do
      assert @persona["tag"] == "persona-widget"
      assert @persona["class_name"] == "PersonaWidget"
      assert @persona["source"] =~ "persona_widget.ts"
    end

    test "extracts every decorated field, in declaration order" do
      assert Enum.map(@persona["properties"], & &1["name"]) ==
               ~w(displayName clickCount disabled tagList filters tone label sessionId open internalCount)
    end

    test "string property with custom attribute + reflect" do
      assert prop(@persona, "displayName") == %{
               "name" => "displayName",
               "kind" => "property",
               "type" => "string",
               "source_type" => "String",
               "default" => "Anonymous",
               "default_expression" => nil,
               "attribute" => "display-name",
               "reflect" => true
             }
    end

    test "Number maps to float, Boolean to boolean, with literal defaults" do
      assert prop(@persona, "clickCount")["type"] == "float"
      assert prop(@persona, "clickCount")["default"] == 0
      assert prop(@persona, "disabled")["type"] == "boolean"
      assert prop(@persona, "disabled")["default"] == false
      assert prop(@persona, "disabled")["reflect"] == true
    end

    test "Array/Object map to list/map; attribute: false is captured" do
      assert prop(@persona, "tagList")["type"] == "list"
      assert prop(@persona, "tagList")["default"] == []
      assert prop(@persona, "filters")["type"] == "map"
      assert prop(@persona, "filters")["default"] == %{}
      assert prop(@persona, "filters")["attribute"] == false
    end

    test "multiline decorator options parse; custom converter is warned, not guessed" do
      tone = prop(@persona, "tone")
      assert tone["type"] == "string"
      assert tone["attribute"] == "tone"
      assert tone["default"] == "neutral"
      assert Enum.any?(@persona["warnings"], &(&1 =~ "tone: Lit option `converter`"))
    end

    test "TS annotation supplies the type when no Lit type is declared" do
      label = prop(@persona, "label")
      assert label["type"] == "string"
      assert label["source_type"] == "string"
      assert label["default"] == nil
    end

    test "computed defaults are surfaced as expressions, never silently dropped" do
      session = prop(@persona, "sessionId")
      assert session["default"] == nil
      assert session["default_expression"] == "crypto.randomUUID()"
      assert Enum.any?(@persona["warnings"], &(&1 =~ "sessionId: computed default"))
    end

    test "@state fields are marked state with inferred types" do
      open = prop(@persona, "open")
      assert open["kind"] == "state"
      assert open["type"] == "boolean"
      assert open["attribute"] == false

      count = prop(@persona, "internalCount")
      assert count["kind"] == "state"
      assert count["type"] == "integer"
      assert count["default"] == 0
    end

    test "comments are stripped — decorated fields inside comments are not extracted" do
      refute prop(@persona, "ghost")
      refute prop(@persona, "commentedOut")
    end
  end

  describe "persona_widget.ts — events, slots, styles" do
    test "CustomEvent detail key types are inferred from literal values" do
      event = event(@persona, "persona-select")
      assert event["bubbles"] == true
      assert event["composed"] == true

      assert event["detail"] == [
               %{"name" => "personaId", "type" => "string"},
               %{"name" => "clickCount", "type" => "integer"},
               %{"name" => "active", "type" => "boolean"}
             ]
    end

    test "non-literal detail values become any; detail-less events keep an empty detail" do
      assert event(@persona, "focusChanged")["detail"] == [%{"name" => "source", "type" => "any"}]
      assert event(@persona, "close")["detail"] == []
      assert event(@persona, "close")["bubbles"] == false
    end

    test "named and unnamed slots are extracted in order" do
      assert @persona["slots"] == [
               %{"name" => "header"},
               %{"name" => "default"},
               %{"name" => "footer"}
             ]
    end

    test "static styles css`` content is captured raw" do
      assert [css] = @persona["styles"]
      assert css =~ ":host { display: block; }"
      assert css =~ ".card { padding: 8px; }"
    end

    test "the shape is JSON-encodable" do
      assert {:ok, _json} = Jason.encode(@persona)
    end
  end

  describe "legacy_widget.js — static properties, define, getter styles" do
    test "tag comes from customElements.define when there is no @customElement" do
      assert @legacy["tag"] == "legacy-widget"
      assert @legacy["class_name"] == "LegacyWidget"
    end

    test "static properties entries parse with options, shorthand and state: true" do
      assert Enum.map(@legacy["properties"], & &1["name"]) ==
               ~w(heading count payload mode shortcut)

      heading = prop(@legacy, "heading")
      assert heading["kind"] == "static"
      assert heading["type"] == "string"
      assert heading["attribute"] == "heading"
      assert heading["reflect"] == true

      assert prop(@legacy, "count")["type"] == "float"
      assert prop(@legacy, "payload")["type"] == "map"
      assert prop(@legacy, "payload")["attribute"] == false
      assert prop(@legacy, "mode")["kind"] == "state"
      assert prop(@legacy, "shortcut")["type"] == "string"
    end

    test "getter-form styles array yields every css`` block" do
      assert @legacy["styles"] == [":host { color: red; }", ".x { margin: 0; }"]
    end

    test "CustomEvent and plain Event dispatches are both captured" do
      fired = event(@legacy, "legacy-fired")
      assert fired["detail"] == [%{"name" => "ok", "type" => "boolean"}]
      assert fired["bubbles"] == true
      assert event(@legacy, "ping")["detail"] == []
    end

    test "unnamed slot becomes default" do
      assert @legacy["slots"] == [%{"name" => "default"}]
    end
  end

  describe "edge cases" do
    test "source without a tag or LitElement class warns instead of guessing" do
      shape = Extractor.extract("export const x = 1;")
      assert shape["tag"] == nil
      assert shape["class_name"] == nil
      assert Enum.any?(shape["warnings"], &(&1 =~ "no @customElement"))
      assert Enum.any?(shape["warnings"], &(&1 =~ "no `class ... extends LitElement`"))
    end

    test "non-literal event names are not captured and the miss is warned" do
      shape =
        Extractor.extract("""
        class X extends LitElement {
          fire(name) { this.dispatchEvent(new CustomEvent(name, { detail: {} })); }
        }
        """)

      assert shape["events"] == []
      assert Enum.any?(shape["warnings"], &(&1 =~ "not tied to a dispatchEvent"))
    end

    test "interpolated styles are captured raw but flagged" do
      shape =
        Extractor.extract("""
        class X extends LitElement {
          static styles = css`:host { color: ${theme.primary}; }`;
        }
        """)

      assert [css] = shape["styles"]
      assert css =~ "${theme.primary}"
      assert Enum.any?(shape["warnings"], &(&1 =~ "interpolation"))
    end

    test "multiline array and object literal defaults parse" do
      shape =
        Extractor.extract("""
        class X extends LitElement {
          @property({ type: Array }) items = [
            "a",
            "b",
          ];
          @property({ type: Object }) config = { a: 1, b: "x" };
        }
        """)

      assert prop(shape, "items")["default"] == ["a", "b"]
      assert prop(shape, "config")["default"] == %{"a" => 1, "b" => "x"}
    end

    test "private (#) fields are skipped with a warning" do
      shape =
        Extractor.extract("""
        class X extends LitElement {
          @state() #secret = 1;
        }
        """)

      assert shape["properties"] == []
      assert Enum.any?(shape["warnings"], &(&1 =~ "private"))
    end

    test "declare/accessor/visibility modifiers between decorator and name are skipped" do
      shape =
        Extractor.extract("""
        class X extends LitElement {
          @property() declare foo: string;
          @property() accessor bar = 1;
          @state() private baz = false;
        }
        """)

      assert Enum.map(shape["properties"], & &1["name"]) == ~w(foo bar baz)
      assert prop(shape, "foo")["type"] == "string"
      assert prop(shape, "bar")["default"] == 1
    end

    test "repeated dispatches of one event merge detail keys and warn" do
      shape =
        Extractor.extract("""
        class X extends LitElement {
          a() { this.dispatchEvent(new CustomEvent("x-fired", { detail: { a: 1 } })); }
          b() { this.dispatchEvent(new CustomEvent("x-fired", { detail: { b: "s" }, composed: true })); }
        }
        """)

      assert [%{"name" => "x-fired", "detail" => detail, "composed" => true}] = shape["events"]

      assert detail == [
               %{"name" => "a", "type" => "integer"},
               %{"name" => "b", "type" => "string"}
             ]

      assert Enum.any?(shape["warnings"], &(&1 =~ "dispatched more than once"))
    end

    test "strings containing // survive comment stripping" do
      shape =
        Extractor.extract("""
        class X extends LitElement {
          @property({ type: String }) url = "https://example.com/a//b";
        }
        """)

      assert prop(shape, "url")["default"] == "https://example.com/a//b"
    end

    test "duplicate decorated + static declarations keep the decorated one and warn" do
      shape =
        Extractor.extract("""
        class X extends LitElement {
          @property({ type: Number }) count = 1;
          static properties = { count: { type: String } };
        }
        """)

      assert [p] = shape["properties"]
      assert p["type"] == "float"
      assert Enum.any?(shape["warnings"], &(&1 =~ "declared both"))
    end
  end
end
