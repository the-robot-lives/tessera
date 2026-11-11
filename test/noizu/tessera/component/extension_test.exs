defmodule Noizu.Tessera.Component.ExtensionTest do
  @moduledoc """
  Shared derivation layer (EXTENSION-CONTRACT.md §5): merge_spec! rules,
  check_pin! semver pins, and the `use Vendor.Element` macro's compile-time
  guards (§5.7). Conformance X-16 (end-to-end) lives in the spike_kit WTR suite;
  these pin the Elixir definition layer both tiers reuse.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Noizu.Tessera.Component.Extension
  alias Noizu.Tessera.Spec

  @tmp_dir System.tmp_dir!()

  # -- hand-built base spec for merge_spec! unit tests -------------------------

  defp base_spec do
    %Spec{
      tag: "base-card",
      module: Tessera.Ext.BaseFixture,
      file: "/tmp/base_card.ex",
      attrs: [
        %{name: :label, type: :string, required: true, default: nil, line: 1},
        %{name: :disabled, type: :boolean, required: false, default: false, line: 2}
      ],
      props: [%{name: :items, type: :list, json: true, default: [], line: 3}],
      events: [%{name: "pick", detail: %{id: :string}, line: 4}],
      slots: [%{name: "default", line: 5}],
      state: [%{name: :count, type: :integer, default: 0, line: 6}],
      actions: [
        %{name: :increment, js: "({ ...state, count: (state.count + 1) })", fn_ast: nil, line: 7}
      ],
      styles: [%{kind: :css, value: "a{}", line: 8}],
      template: %{raw: "<div>{@count}</div>", lexer: :minimal, render_js: "html`<div></div>`", line: 9},
      lifecycle: %{}
    }
  end

  defp deltas(overrides \\ %{}) do
    Map.merge(
      %{
        attrs: [],
        props: [],
        events: [],
        slots: [],
        css_properties: [],
        parts: [],
        state: [],
        actions: [],
        template: nil,
        lifecycle: %{},
        styles: [],
        cy: nil
      },
      overrides
    )
  end

  describe "merge_spec!/3 — additive + override (§5.5)" do
    test "new names append after inherited entries, in declaration order" do
      merged =
        Extension.merge_spec!(
          base_spec(),
          deltas(%{attrs: [%{name: :badge, type: :string, required: false, default: "", line: 20}]}),
          __ENV__
        )

      assert Enum.map(merged.attrs, & &1.name) == [:label, :disabled, :badge]
      assert Enum.map(merged.attrs, & !!&1[:inherited]) == [true, true, false]
    end

    test "override-by-name replaces wholesale and is not marked inherited" do
      merged =
        Extension.merge_spec!(
          base_spec(),
          deltas(%{
            attrs: [%{name: :label, type: :integer, required: false, default: 5, line: 20}]
          }),
          __ENV__
        )

      label = Enum.find(merged.attrs, &(&1.name == :label))
      assert label.type == :integer
      assert label.default == 5
      refute label[:inherited]
      # the other inherited attr persists
      assert Enum.find(merged.attrs, &(&1.name == :disabled))[:inherited]
    end

    test "inherited names are never dropped (removal forbidden invariant)" do
      merged = Extension.merge_spec!(base_spec(), deltas(), __ENV__)

      for kind <- [:attrs, :props, :events, :slots, :state, :actions] do
        base_names = MapSet.new(Enum.map(Map.get(base_spec(), kind), & &1.name))
        merged_names = MapSet.new(Enum.map(merged[kind], & &1.name))
        assert MapSet.subset?(base_names, merged_names), "#{kind} lost inherited names"
      end
    end

    test "required: may relax (true → false)" do
      merged =
        Extension.merge_spec!(
          base_spec(),
          deltas(%{attrs: [%{name: :label, type: :string, required: false, default: "x", line: 20}]}),
          __ENV__
        )

      refute Enum.find(merged.attrs, &(&1.name == :label)).required
    end

    test "required: may NOT tighten (false → true) — CompileError" do
      assert_raise CompileError, ~r/tightens `required:`/, fn ->
        Extension.merge_spec!(
          base_spec(),
          deltas(%{attrs: [%{name: :disabled, type: :boolean, required: true, line: 20}]}),
          __ENV__
        )
      end
    end

    test "duplicate author declarations raise (no silent last-wins)" do
      assert_raise CompileError, ~r/duplicate tessera attrs :badge/, fn ->
        Extension.merge_spec!(
          base_spec(),
          deltas(%{
            attrs: [
              %{name: :badge, type: :string, line: 20},
              %{name: :badge, type: :integer, line: 21}
            ]
          }),
          __ENV__
        )
      end
    end

    test "event redeclare keeps inherited detail keys and extends (§5.6)" do
      merged =
        Extension.merge_spec!(
          base_spec(),
          deltas(%{events: [%{name: "pick", detail: %{extra: :integer}, line: 20}]}),
          __ENV__
        )

      pick = Enum.find(merged.events, &(&1.name == "pick"))
      assert pick.detail == %{id: :string, extra: :integer}
    end

    test "styles are additive — base (inherited) then author" do
      merged =
        Extension.merge_spec!(
          base_spec(),
          deltas(%{styles: [%{kind: :css, value: "b{}", line: 20}]}),
          __ENV__
        )

      assert Enum.map(merged.styles, & &1.value) == ["a{}", "b{}"]
      assert Enum.map(merged.styles, & !!&1[:inherited]) == [true, false]
    end

    test "template: author replaces; absent inherits the base raw markup" do
      inherited = Extension.merge_spec!(base_spec(), deltas(), __ENV__)
      assert inherited.template.markup == "<div>{@count}</div>"

      overridden =
        Extension.merge_spec!(
          base_spec(),
          deltas(%{template: %{line: 20, markup: "<span>derived</span>"}}),
          __ENV__
        )

      assert overridden.template.markup == "<span>derived</span>"
    end
  end

  describe "check_pin!/3 — extension-api semver (§8.4)" do
    test "nil requirement is a no-op" do
      assert Extension.check_pin!("1.0.0", nil, __ENV__) == :ok
    end

    test "satisfied ~> range passes" do
      assert Extension.check_pin!("1.5.0", "~> 1.0", __ENV__) == :ok
    end

    test "caret requirement normalizes and passes" do
      assert Extension.check_pin!("1.5.0", "^1.0.0", __ENV__) == :ok
    end

    test "exact requirement matches" do
      assert Extension.check_pin!("1.2.3", "1.2.3", __ENV__) == :ok
    end

    test "MAJOR mismatch raises CompileError" do
      assert_raise CompileError, ~r/MAJOR mismatch/, fn ->
        Extension.check_pin!("2.0.0", "~> 1.0", __ENV__)
      end
    end

    test "minor-range mismatch warns (does not raise)" do
      warning =
        capture_io(:stderr, fn ->
          assert Extension.check_pin!("1.0.0", "~> 1.5", __ENV__) == :ok
        end)

      assert warning =~ "minor range"
      assert warning =~ "1.0.0"
    end

    test "a base with no declared version defaults to 1.0.0" do
      assert Extension.check_pin!(nil, "~> 1.0", __ENV__) == :ok
    end

    test "invalid requirement raises" do
      assert_raise CompileError, ~r/not a valid semver requirement/, fn ->
        Extension.check_pin!("1.0.0", "banana", __ENV__)
      end
    end
  end

  # -- compile-level derivation guards (§5.7) ----------------------------------

  defp compile_base(id) do
    dir = Path.join(@tmp_dir, "tessera_ext_base_#{id}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "base_card.ex")
    mod = "Tessera.Ext.Base#{id}"

    Code.compile_string(
      """
      defmodule #{mod} do
        use Noizu.Tessera.Component, tag: "ext-base-#{id}", js: "base_#{id}.mjs"
        attr :label, :string, required: true
        attr :disabled, :boolean, default: false
        state :count, :integer, default: 0
        event "row-pick", detail: %{id: :string}
        template ~TSR"<div>{@count}</div>"
        action :increment, fn state, _params -> %{state | count: state.count + 1} end
      end
      """,
      path
    )

    {String.to_atom("Elixir." <> mod), dir}
  end

  defp compile_derived(base_mod, id, opts, body \\ "") do
    dir = Path.join(@tmp_dir, "tessera_ext_derived_#{id}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "derived.ex")
    mod = "Tessera.Ext.Derived#{id}"

    Code.compile_string(
      """
      defmodule #{mod} do
        use #{inspect(base_mod)}, #{opts}
        #{body}
      end
      """,
      path
    )

    String.to_atom("Elixir." <> mod)
  end

  describe "use Vendor.Element — option validation" do
    test "missing tag raises" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_base(id)

      assert_raise CompileError, ~r/derivation requires `tag:`/, fn ->
        compile_derived(base, id, "priority: 0")
      end
    end

    test "invalid fresh tag raises" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_base(id)

      assert_raise CompileError, ~r/invalid tessera tag/, fn ->
        compile_derived(base, id, ~s(tag: "BadTag"))
      end
    end

    test "fresh tag equal to the base tag raises (use :inherit)" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_base(id)

      assert_raise CompileError, ~r/equals the base tag/, fn ->
        compile_derived(base, id, ~s(tag: "ext-base-#{id}"))
      end
    end

    test "non-integer priority raises" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_base(id)

      assert_raise CompileError, ~r/`priority:` must be an integer/, fn ->
        compile_derived(base, id, ~s(tag: "ext-der-#{id}", priority: "high"))
      end
    end

    test "extension_api MAJOR mismatch raises" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_base(id)

      assert_raise CompileError, ~r/MAJOR mismatch/, fn ->
        compile_derived(base, id, ~s(tag: "ext-der-#{id}", extension_api: "~> 2.0"))
      end
    end
  end

  describe "use Vendor.Element — double use + cycle (§5.1, §5.9)" do
    test "repeating use Noizu.Tessera.Component after use Base raises" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_base(id)

      assert_raise CompileError, ~r/double use/, fn ->
        compile_derived(
          base,
          id,
          ~s(tag: "ext-der-#{id}"),
          ~s(use Noizu.Tessera.Component, tag: "other-#{id}", js: "other.mjs")
        )
      end
    end

    test "use Noizu.Tessera.Component before use Base raises" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_base(id)
      dir = Path.join(@tmp_dir, "tessera_ext_rev_#{id}")
      File.mkdir_p!(dir)

      assert_raise CompileError, ~r/double use/, fn ->
        Code.compile_string(
          """
          defmodule Tessera.Ext.Rev#{id} do
            use Noizu.Tessera.Component, tag: "rev-#{id}", js: "rev.mjs"
            use #{inspect(base)}, tag: "ext-der-#{id}"
          end
          """,
          Path.join(dir, "rev.ex")
        )
      end
    end

    test "a derivation cycle raises" do
      id = :erlang.unique_integer([:positive])
      {base, base_dir} = compile_base(id)
      # mid derives from base
      mid = compile_derived(base, id, ~s(tag: "ext-mid-#{id}"))

      # base tries to derive from mid — base's module is in mid's spine
      assert_raise CompileError, ~r/derivation cycle/, fn ->
        Code.compile_string(
          """
          defmodule Tessera.Ext.Base#{id} do
            use #{inspect(mid)}, tag: "ext-cyc-#{id}"
          end
          """,
          Path.join(base_dir, "base_card.ex")
        )
      end
    end
  end

  describe "use Vendor.Element — merged spec + artifacts (X-16 definition layer)" do
    test "derived spec names its base and merges the surface" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_base(id)

      derived =
        compile_derived(base, id, ~s(tag: "ext-der-#{id}", priority: 5), """
        attr :badge, :string, default: ""
        state :extra, :integer, default: 0
        action :increment, fn state, params ->
          state = base_action(:increment, state, params)
          %{state | extra: state.extra + 1}
        end
        """)

      spec = derived.__tessera_spec__()
      assert spec.derived_from == base
      assert spec.priority == 5
      assert spec.tag == "ext-der-#{id}"
      assert Enum.map(spec.attrs, & &1.name) == [:label, :disabled, :badge]
      assert Enum.map(spec.state, & &1.name) == [:count, :extra]
      assert Enum.map(spec.actions, & &1.name) == [:increment]
      assert derived.__tessera_manifest__()["derived_from"] == inspect(base)
    end

    test "base artifacts are byte-unchanged by a fresh-tag derivation" do
      id = :erlang.unique_integer([:positive])
      {base, base_dir} = compile_base(id)
      base_element = Path.join(base_dir, "ext-base-#{id}.element.generated.mjs")
      before = File.read!(base_element)

      _derived = compile_derived(base, id, ~s(tag: "ext-der-#{id}"))

      assert File.read!(base_element) == before
    end

    test "tag: :inherit registers under the base tag in the extending app" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_base(id)

      derived = compile_derived(base, id, "tag: :inherit")
      spec = derived.__tessera_spec__()
      assert spec.tag == "ext-base-#{id}"
      assert spec.derived_from == base
    end

    test "tag: :inherit in the base's own directory raises (would clobber vendor artifacts)" do
      id = :erlang.unique_integer([:positive])
      {base, base_dir} = compile_base(id)

      assert_raise CompileError, ~r/overwrite the vendor's generated artifacts/, fn ->
        Code.compile_string(
          """
          defmodule Tessera.Ext.Inherit#{id} do
            use #{inspect(base)}, tag: :inherit
          end
          """,
          Path.join(base_dir, "inherit.ex")
        )
      end
    end

    test "an inherited template renders without a derived template declaration" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_base(id)

      derived = compile_derived(base, id, ~s(tag: "ext-der-#{id}"), "attr :badge, :string")
      spec = derived.__tessera_spec__()
      assert spec.template.raw == "<div>{@count}</div>"
    end

    test "a prop colliding with an inherited attr is re-checked over the merged spec" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_base(id)

      assert_raise CompileError, ~r/attr\/prop name collision on :label/, fn ->
        compile_derived(base, id, ~s(tag: "ext-der-#{id}"), "prop :label, :string")
      end
    end

    test "base_action against a non-inherited action raises" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_base(id)

      assert_raise CompileError, ~r/not an inherited action/, fn ->
        compile_derived(base, id, ~s(tag: "ext-der-#{id}"), """
        action :brand_new, fn state, params ->
          base_action(:brand_new, state, params)
        end
        """)
      end
    end
  end
end