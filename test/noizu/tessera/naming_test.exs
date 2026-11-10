defmodule Noizu.Tessera.NamingTest do
  use ExUnit.Case, async: true

  alias Noizu.Tessera.Naming

  describe "snake_to_kebab/1" do
    test "converts underscores to hyphens" do
      assert Naming.snake_to_kebab(:display_name) == "display-name"
      assert Naming.snake_to_kebab(:a) == "a"
    end
  end

  describe "snake_to_camel/1" do
    test "capitalizes every segment after the first" do
      assert Naming.snake_to_camel(:display_name) == "displayName"
      assert Naming.snake_to_camel(:persona_id) == "personaId"
      assert Naming.snake_to_camel(:tag_list) == "tagList"
      assert Naming.snake_to_camel(:a) == "a"
    end

    test "byte-exact rule, not Macro.camelize — digit segments keep their case" do
      assert Naming.snake_to_camel(:col2_width) == "col2Width"
      # Macro.camelize upcases every segment whole, so it diverges on
      # lowercase-after-digit / acronym segments:
      assert Macro.camelize("col2_width") == "Col2Width"
      assert Naming.snake_to_camel(:user_i_d) == "userID"
    end
  end

  describe "camel_to_snake/1" do
    test "every uppercase char becomes underscore + lowercase" do
      assert Naming.camel_to_snake("displayName") == :display_name
      assert Naming.camel_to_snake("userID") == :user_i_d
      assert Naming.camel_to_snake("col2Width") == :col2_width
      assert Naming.camel_to_snake("a") == :a
    end
  end

  describe "round_trips?/1" do
    test "accepts plain snake names" do
      for name <- [:display_name, :tag_list, :persona_id, :a, :col2_width, :user_id, :x1_y2] do
        assert Naming.round_trips?(name), "expected #{inspect(name)} to round-trip"
      end
    end

    test "rejects digit-initial segments (col_2_width)" do
      refute Naming.round_trips?(:col_2_width)
    end

    test "rejects double and trailing underscores" do
      refute Naming.round_trips?(:foo__bar)
      refute Naming.round_trips?(:foo_)
      refute Naming.round_trips?(:my__key)
    end
  end

  describe "kebab_to_snake/1" do
    test "converts hyphens to underscores" do
      assert Naming.kebab_to_snake("persona-select") == :persona_select
    end
  end

  describe "event_binding_prop/1 + event_default_action/1" do
    test "binding prop is on_ + snake(event)" do
      assert Naming.event_binding_prop("persona-select") == :on_persona_select
    end

    test "default action is snake(event)" do
      assert Naming.event_default_action("persona-select") == :persona_select
    end
  end

  describe "grammars" do
    test "tag and event grammar requires a hyphen and lowercase" do
      assert Regex.match?(Naming.tag_regex(), "persona-card")
      assert Regex.match?(Naming.event_regex(), "persona-select")
      refute Regex.match?(Naming.event_regex(), "personaselect")
      refute Regex.match?(Naming.event_regex(), "Persona-Select")
      refute Regex.match?(Naming.event_regex(), "persona--select")
      refute Regex.match?(Naming.tag_regex(), "1a-b")
    end

    test "snake grammar" do
      assert Regex.match?(Naming.snake_regex(), "display_name")
      refute Regex.match?(Naming.snake_regex(), "Display_Name")
      refute Regex.match?(Naming.snake_regex(), "_hidden")
      refute Regex.match?(Naming.snake_regex(), "2col")
    end
  end
end
