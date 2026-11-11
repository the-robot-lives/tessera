defmodule Noizu.Tessera.SpecTest do
  use ExUnit.Case, async: true

  alias Noizu.Tessera.Naming
  alias Noizu.Tessera.Spec

  describe "validate! :tag" do
    test "accepts contract-grammar tags" do
      assert Spec.validate!(:tag, "persona-card", %{}, "t.ex", 1) == :ok
    end

    test "rejects non-grammar tags" do
      for bad <- ["PersonaCard", "persona", "1persona-card", "persona-card-", "persona--card"] do
        assert_raise CompileError, ~r/invalid tessera tag/, fn ->
          Spec.validate!(:tag, bad, %{}, "t.ex", 1)
        end
      end
    end
  end

  describe "validate! :event" do
    test "accepts kebab event names with camel-safe detail keys" do
      assert Spec.validate!(
               :event,
               "persona-select",
               %{persona_id: :string, click_count: :integer},
               "t.ex",
               1
             ) == :ok
    end

    test "rejects non-kebab event names" do
      assert_raise CompileError, ~r/invalid tessera event/, fn ->
        Spec.validate!(:event, "personaselect", %{}, "t.ex", 1)
      end
    end

    test "rejects names containing reserved bridge-grammar characters (whitespace `:` `@` `;`)" do
      for bad <- ["persona@select", "persona:select", "persona;select", "persona select"] do
        assert_raise CompileError, ~r/reserved data-tsr-on character/, fn ->
          Spec.validate!(:event, bad, %{}, "t.ex", 1)
        end
      end

      assert_raise CompileError, ~r/reserved data-tsr-on character/, fn ->
        Spec.validate!(:tag, "bad@tag-name", %{}, "t.ex", 1)
      end
    end

    test "rejects detail keys that are not snake atoms" do
      assert_raise CompileError, ~r/must be a snake_case atom/, fn ->
        Spec.validate!(:event, "persona-select", %{"persona_id" => :string}, "t.ex", 1)
      end

      assert_raise CompileError, ~r/must be a snake_case atom/, fn ->
        Spec.validate!(:event, "persona-select", %{userID: :string}, "t.ex", 1)
      end
    end

    test "rejects detail keys that do not round-trip" do
      assert_raise CompileError, ~r/does not survive the snake↔camel wire round-trip/, fn ->
        Spec.validate!(:event, "persona-select", %{col_2: :integer}, "t.ex", 1)
      end
    end

    test "rejects unknown detail types" do
      assert_raise CompileError, ~r/unknown type/, fn ->
        Spec.validate!(:event, "persona-select", %{persona_id: :datetime}, "t.ex", 1)
      end
    end
  end

  describe "validate! :attr / :prop" do
    test "accepts round-tripping snake names with known types" do
      assert Spec.validate!(:attr, :display_name, %{type: :string}, "t.ex", 1) == :ok
      assert Spec.validate!(:prop, :tag_list, %{type: :list}, "t.ex", 1) == :ok
      assert Spec.validate!(:attr, :col2_width, %{type: :integer}, "t.ex", 1) == :ok
    end

    test "rejects non-snake names" do
      assert_raise CompileError, ~r/must be a snake_case atom/, fn ->
        Spec.validate!(:attr, :Display_Name, %{type: :string}, "t.ex", 1)
      end
    end

    test "rejects leading-underscore names" do
      assert_raise CompileError, ~r/must be a snake_case atom/, fn ->
        Spec.validate!(:attr, :_hidden, %{type: :string}, "t.ex", 1)
      end
    end

    test "rejects names that do not survive the round-trip, suggesting a rename" do
      assert_raise CompileError, ~r/col_2_width.*col2_width.*Rename it/s, fn ->
        Spec.validate!(:attr, :col_2_width, %{type: :integer}, "t.ex", 1)
      end

      assert_raise CompileError, ~r/foo__bar/, fn ->
        Spec.validate!(:prop, :foo__bar, %{type: :string}, "t.ex", 1)
      end
    end

    test "rejects unknown types" do
      assert_raise CompileError, ~r/unknown type :datetime/, fn ->
        Spec.validate!(:attr, :when, %{type: :datetime}, "t.ex", 1)
      end
    end
  end

  describe "validate! :slot" do
    test "accepts lowercase slot names" do
      assert Spec.validate!(:slot, "default", %{}, "t.ex", 1) == :ok
      assert Spec.validate!(:slot, "header-left", %{}, "t.ex", 1) == :ok
    end

    test "rejects other names" do
      assert_raise CompileError, ~r/must be a lowercase string/, fn ->
        Spec.validate!(:slot, "Header", %{}, "t.ex", 1)
      end
    end
  end

  describe "validate! :part" do
    test "accepts lowercase part names" do
      assert Spec.validate!(:part, "select-button", %{}, "t.ex", 1) == :ok
      assert Spec.validate!(:part, "header_left", %{}, "t.ex", 1) == :ok
    end

    test "rejects other names" do
      for bad <- ["Select", "1part", "select button", ""] do
        assert_raise CompileError, ~r/tessera part name/, fn ->
          Spec.validate!(:part, bad, %{}, "t.ex", 1)
        end
      end
    end
  end

  describe "validate! :css" do
    test "accepts --kebab custom property names with a string default" do
      assert Spec.validate!(:css, "--persona-card-accent", [default: "#6366f1"], "t.ex", 1) == :ok
      assert Spec.validate!(:css, "--gap", [], "t.ex", 1) == :ok
    end

    test "rejects names that are not lowercase --kebab custom properties" do
      for bad <- ["accent", "-accent", "--Accent", "--accent_color", "--1accent", ""] do
        assert_raise CompileError, ~r/tessera css property/, fn ->
          Spec.validate!(:css, bad, [], "t.ex", 1)
        end
      end
    end

    test "rejects non-string defaults" do
      assert_raise CompileError, ~r/default must be a string/, fn ->
        Spec.validate!(:css, "--gap", [default: 4], "t.ex", 1)
      end
    end
  end

  describe "json_literal/1" do
    test "maps nil and booleans" do
      assert Spec.json_literal(nil) == "null"
      assert Spec.json_literal(true) == "true"
      assert Spec.json_literal(false) == "false"
    end

    test "numbers, strings, lists, maps" do
      assert Spec.json_literal(42) == "42"
      assert Spec.json_literal(1.5) == "1.5"
      assert Spec.json_literal("ada") == ~s("ada")
      assert Spec.json_literal([1, 2]) == "[1,2]"
      assert Spec.json_literal(%{b: 1, a: 2}) == ~s({"a":2,"b":1})
      assert Spec.json_literal(%{"b" => 1, "a" => 2}) == ~s({"a":2,"b":1})
    end

    test "lists of maps are key-sorted deterministically (not Jason's arbitrary order)" do
      assert Spec.json_literal([%{b: 1, a: 2}, %{d: 3, c: 4}]) ==
               ~s([{"a":2,"b":1},{"c":4,"d":3}])

      assert Spec.json_literal([]) == "[]"
      assert Spec.json_literal(["x", %{k: "v"}]) == ~s(["x",{"k":"v"}])
    end

    test "escapes strings" do
      # input:  say "hi"
      # output: "say \"hi\""  (as JSON literal text)
      assert Spec.json_literal("say \"hi\"") == "\"say \\\"hi\\\"\""
    end

    test "rejects non-JSON-safe defaults" do
      assert_raise ArgumentError, ~r/must be JSON-safe/, fn ->
        Spec.json_literal(fn -> :x end)
      end
    end
  end

  describe "escape_json/1" do
    test "escapes quotes, backslashes and control chars" do
      assert Spec.escape_json("a\"b\\c\nd\te") == "a\\\"b\\\\c\\nd\\te"
    end

    test "escapes carriage returns (a raw CR inside a generated .mjs string literal is a SyntaxError)" do
      assert Spec.escape_json("a\rb") == "a\\rb"

      assert Spec.escape_json("mix\rof\rthem\rall\there") ==
               "mix\\rof\\rthem\\rall\\there"
    end

    test "escapes EVERY control char < 0x20 — short forms for LF/CR/TAB, \\u00XX for the rest (F-14)" do
      for c <- 0x00..0x1F do
        expected =
          case c do
            0x0A ->
              "\\n"

            0x0D ->
              "\\r"

            0x09 ->
              "\\t"

            _ ->
              "\\u" <>
                (c |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0"))
          end

        assert Spec.escape_json(<<c>>) == expected,
               "control char 0x#{String.pad_leading(Integer.to_string(c, 16), 2, "0")} " <>
                 "escaped wrong: expected #{inspect(expected)}, " <>
                 "got #{inspect(Spec.escape_json(<<c>>))}"
      end
    end

    test "escapes backspace and form feed as \\u0008 / \\u000c (F-14)" do
      assert Spec.escape_json("a\bb") == "a\\u0008b"
      assert Spec.escape_json("a\fb") == "a\\u000cb"
    end

    test "every control char survives a JSON decode round trip (F-14)" do
      for c <- 0x00..0x1F do
        input = "x" <> <<c>> <> "y"
        assert Jason.decode!("\"" <> Spec.escape_json(input) <> "\"") == input
      end
    end

    test "control chars mixed with quotes and backslashes stay valid JSON (F-14)" do
      input = "a\"b\\c\bd\fe\vf\0g"
      assert Jason.decode!("\"" <> Spec.escape_json(input) <> "\"") == input
    end
  end

  describe "to_manifest_map/1" do
    test "renders a JSON-encodable plain map" do
      spec = %Spec{
        version: 1,
        tag: "persona-card",
        module: Some.Mod,
        file: "/x/persona_card.ex",
        js: "persona_card.mjs",
        cy: "persona-card-root",
        attrs: [%{name: :display_name, type: :string, required: true, default: nil, line: 3}],
        props: [%{name: :tag_list, type: :list, json: true, default: [], line: 4}],
        events: [%{name: "persona-select", detail: %{persona_id: :string}, line: 5}],
        slots: [%{name: "header", line: 6}],
        css_properties: [%{name: "--persona-card-accent", default: "#6366f1", line: 7}],
        parts: [%{name: "select-button", line: 8}]
      }

      map = Spec.to_manifest_map(spec)

      assert map == %{
               "contractVersion" => 1,
               "tag" => "persona-card",
               "module" => "Some.Mod",
               "file" => "/x/persona_card.ex",
               "js" => "persona_card.mjs",
               "cy" => "persona-card-root",
               "attrs" => [
                 %{
                   "name" => "display-name",
                   "type" => "string",
                   "required" => true,
                   "default" => nil
                 }
               ],
               "props" => [
                 %{"name" => "tagList", "type" => "list", "json" => true, "default" => []}
               ],
               "events" => [
                 %{"name" => "persona-select", "detail" => %{"personaId" => "string"}}
               ],
               "slots" => ["header"],
               "cssProperties" => [
                 %{"name" => "--persona-card-accent", "default" => "#6366f1"}
               ],
               "parts" => ["select-button"]
             }

      # Must be JSON-encodable (the manifest task writes it verbatim).
      assert is_binary(Jason.encode!(map))
      assert Naming.known_type?(:any)
    end
  end
end
