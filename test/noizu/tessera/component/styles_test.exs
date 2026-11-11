defmodule Noizu.Tessera.Component.StylesTest do
  @moduledoc """
  Styles DSL helpers — theming-contract extraction (EXTENSION-CONTRACT.md §7)
  and css`` literal safety. Pure-function tests; no CSS parsing beyond the
  contract surface is claimed.
  """

  use ExUnit.Case, async: true

  alias Noizu.Tessera.Component.Styles

  describe "custom_property_reads/2" do
    test "extracts a tag-scoped read with its fallback" do
      css = ":host { color: var(--tsr-x-card-accent, #6cf); }"

      assert Styles.custom_property_reads(css, "x-card") == [
               %{name: "--tsr-x-card-accent", default: "#6cf"}
             ]
    end

    test "a read without a fallback reports default nil" do
      assert Styles.custom_property_reads("a{color:var(--tsr-x-card-accent)}", "x-card") == [
               %{name: "--tsr-x-card-accent", default: nil}
             ]
    end

    test "nested var() fallbacks are reported as their own reads" do
      css = "a{gap:var(--tsr-x-card-a, var(--tsr-x-card-b, 2px))}"

      assert Styles.custom_property_reads(css, "x-card") == [
               %{name: "--tsr-x-card-a", default: "var(--tsr-x-card-b, 2px)"},
               %{name: "--tsr-x-card-b", default: "2px"}
             ]
    end

    test "fallbacks with nested parens and commas survive intact (rgba)" do
      css = "a{box-shadow:var(--tsr-x-card-shadow, rgba(0, 0, 0, 0.5))}"

      assert Styles.custom_property_reads(css, "x-card") == [
               %{name: "--tsr-x-card-shadow", default: "rgba(0, 0, 0, 0.5)"}
             ]
    end

    test "other tags' properties and un-prefixed globals are not this element's surface" do
      css = "a{color:var(--tsr-other-card-a, 1px); background:var(--global, 2px)}"
      assert Styles.custom_property_reads(css, "x-card") == []
    end

    test "CSS comments are stripped before scanning" do
      css = "/* var(--tsr-x-card-ghost, 1px) */ a{color:var(--tsr-x-card-real, 2px)}"

      assert Styles.custom_property_reads(css, "x-card") == [
               %{name: "--tsr-x-card-real", default: "2px"}
             ]
    end

    test "non-lower-kebab prop segments are ignored" do
      css =
        "a{a:var(--tsr-x-card-UPPER, 1px); b:var(--tsr-x-card-, 2px); c:var(--tsr-x-card-ok, 3px)}"

      assert Styles.custom_property_reads(css, "x-card") == [
               %{name: "--tsr-x-card-ok", default: "3px"}
             ]
    end

    test "duplicates keep the first occurrence; output is sorted by name" do
      css = """
      a{color:var(--tsr-x-card-z, 1px); background:var(--tsr-x-card-a, 2px)}
      b{color:var(--tsr-x-card-z, 9px)}
      """

      assert Styles.custom_property_reads(css, "x-card") == [
               %{name: "--tsr-x-card-a", default: "2px"},
               %{name: "--tsr-x-card-z", default: "1px"}
             ]
    end

    test "identifiers merely ending in var( are not reads" do
      assert Styles.custom_property_reads("a{color:myvar(--tsr-x-card-a, 1px)}", "x-card") == []
    end

    test "whitespace around name and fallback is trimmed" do
      css = "a{color:var( --tsr-x-card-a , 1px )}"

      assert Styles.custom_property_reads(css, "x-card") == [
               %{name: "--tsr-x-card-a", default: "1px"}
             ]
    end

    test "an unbalanced var( raises ArgumentError" do
      assert_raise ArgumentError, ~r/unbalanced var/, fn ->
        Styles.custom_property_reads("a{color:var(--tsr-x-card-a, 1px}", "x-card")
      end
    end
  end

  describe "missing_fallbacks/2" do
    test "names only the tag-scoped reads lacking a fallback" do
      css = """
      a{color:var(--tsr-x-card-a); gap:var(--tsr-x-card-b, 2px); border:var(--other-c)}
      """

      assert Styles.missing_fallbacks(css, "x-card") == ["--tsr-x-card-a"]
    end
  end

  describe "parts/1" do
    test "nil markup has no parts" do
      assert Styles.parts(nil) == []
    end

    test "extracts part attributes (single and double quotes, multi-name lists)" do
      markup = ~s(<div part="row"><span part='accent label'></span><b part="row"></b>)
      assert Styles.parts(markup) == ["row", "accent", "label"]
    end

    test "exportparts and data-part are not part declarations" do
      markup = ~s(<div exportparts="inner" data-part="fake" part="real"></div>)
      assert Styles.parts(markup) == ["real"]
    end
  end

  describe "escape_css_template/1" do
    test "escapes backticks, interpolation openers and backslashes" do
      assert Styles.escape_css_template(~S"a`b") == ~S"a\`b"
      assert Styles.escape_css_template(~S"a${b}") == ~S"a\${b}"
      assert Styles.escape_css_template(~S"a\b") == ~S"a\\b"
    end

    test "backslash is escaped first so added escapes are not re-escaped" do
      # Input chars: \ $ {  →  \ \ \ $ {  (literal \ then literal ${ in JS)
      assert Styles.escape_css_template(~S"\${") == ~S"\\\${"
    end

    test "plain CSS passes through verbatim" do
      css = ":host { display: block; }\n::slotted(p) { margin: 0; }"
      assert Styles.escape_css_template(css) == css
    end
  end
end
