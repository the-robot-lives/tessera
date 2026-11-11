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
      template: %{
        raw: "<div>{@count}</div>",
        lexer: :minimal,
        render_js: "html`<div></div>`",
        line: 9
      },
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
          deltas(%{
            attrs: [%{name: :badge, type: :string, required: false, default: "", line: 20}]
          }),
          __ENV__
        )

      assert Enum.map(merged.attrs, & &1.name) == [:label, :disabled, :badge]
      assert Enum.map(merged.attrs, &(!!&1[:inherited])) == [true, true, false]
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
          deltas(%{
            attrs: [%{name: :label, type: :string, required: false, default: "x", line: 20}]
          }),
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
      assert Enum.map(merged.styles, &(!!&1[:inherited])) == [true, false]
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

  # -- brief 2d: event renames + detail/type guards (§5.5/§5.6) ----------------

  describe "event renames (merge level, §5.6)" do
    test "rename replaces the inherited event in place: new name, merged detail, provenance" do
      merged =
        Extension.merge_spec!(
          base_spec(),
          deltas(%{
            events: [
              %{name: "persona-select", detail: %{persona: :string}, renames: "pick", line: 20}
            ]
          }),
          __ENV__
        )

      assert Enum.map(merged.events, & &1.name) == ["persona-select"]
      [ev] = merged.events
      assert ev.detail == %{id: :string, persona: :string}
      assert ev.renamed_from == "pick"
      refute Map.has_key?(ev, :renames)
    end

    test "emission rewrite: inherited action JS re-emits under the new name + :re_emit" do
      spec = %{
        base_spec()
        | actions: [
            %{
              name: :increment,
              js: ~S|emit(this, "pick", {id: state.id}); state|,
              fn_ast: nil,
              line: 7
            }
          ]
      }

      merged =
        Extension.merge_spec!(
          spec,
          deltas(%{
            events: [%{name: "chip-pick", detail: %{}, renames: "pick", line: 20}]
          }),
          __ENV__
        )

      [a] = merged.actions
      assert a.js == ~S|emit(this, "chip-pick", {id: state.id}); state|
      assert a[:re_emit] == true
    end

    test "renaming a non-inherited event is a broken chain" do
      assert_raise CompileError, ~r/broken rename chain.*not an inherited event/, fn ->
        Extension.merge_spec!(
          base_spec(),
          deltas(%{
            events: [%{name: "x-sel", detail: %{}, renames: "nope", line: 20}]
          }),
          __ENV__
        )
      end
    end

    test "renaming an already-renamed event is forbidden (no rename chains)" do
      spec = %{
        base_spec()
        | events: [%{name: "pick", detail: %{id: :string}, renamed_from: "orig", line: 4}]
      }

      assert_raise CompileError, ~r/broken rename chain.*already a rename/, fn ->
        Extension.merge_spec!(
          spec,
          deltas(%{
            events: [%{name: "pick-again", detail: %{}, renames: "pick", line: 20}]
          }),
          __ENV__
        )
      end
    end

    test "renaming an event to itself raises" do
      assert_raise CompileError, ~r/renames itself/, fn ->
        Extension.merge_spec!(
          base_spec(),
          deltas(%{
            events: [%{name: "pick", detail: %{}, renames: "pick", line: 20}]
          }),
          __ENV__
        )
      end
    end

    test "a rename landing on an existing inherited name is a target conflict" do
      spec = %{
        base_spec()
        | events: [
            %{name: "pick", detail: %{id: :string}, line: 4},
            %{name: "swap", detail: %{}, line: 4}
          ]
      }

      assert_raise CompileError, ~r/rename target conflict/, fn ->
        Extension.merge_spec!(
          spec,
          deltas(%{
            events: [%{name: "pick", detail: %{}, renames: "swap", line: 20}]
          }),
          __ENV__
        )
      end
    end

    test "two renames of the same inherited event raise" do
      assert_raise CompileError, ~r/rename the same inherited event/, fn ->
        Extension.merge_spec!(
          base_spec(),
          deltas(%{
            events: [
              %{name: "a-sel", detail: %{}, renames: "pick", line: 20},
              %{name: "b-sel", detail: %{}, renames: "pick", line: 21}
            ]
          }),
          __ENV__
        )
      end
    end

    test "a non-string renames: target raises" do
      assert_raise CompileError, ~r/`renames:` must name the inherited event as a string/, fn ->
        Extension.merge_spec!(
          base_spec(),
          deltas(%{
            events: [%{name: "a-sel", detail: %{}, renames: :pick, line: 20}]
          }),
          __ENV__
        )
      end
    end

    test "removal guard exempts exactly the renamed-away base name" do
      merged =
        Extension.merge_spec!(
          base_spec(),
          deltas(%{
            events: [%{name: "persona-select", detail: %{}, renames: "pick", line: 20}]
          }),
          __ENV__
        )

      # every OTHER inherited kind still carries its base names (assert_no_removal!
      # would have raised on any loss before returning)
      assert Enum.map(merged.attrs, & &1.name) == [:label, :disabled]
      assert Enum.map(merged.state, & &1.name) == [:count]
    end
  end

  describe "detail narrowing + type-change guards (merge level, §5.5/§5.6)" do
    test "re-declaring an event with a retyped detail key narrows the inherited detail" do
      assert_raise CompileError,
                   ~r/narrows the inherited detail key :id from :string to :integer/,
                   fn ->
                     Extension.merge_spec!(
                       base_spec(),
                       deltas(%{events: [%{name: "pick", detail: %{id: :integer}, line: 20}]}),
                       __ENV__
                     )
                   end
    end

    test "retyping a key the base template READS is rejected (§5.5 reference graph)" do
      assert_raise CompileError,
                   ~r/type-change guard.*retypes state :count from :integer to :string/,
                   fn ->
                     Extension.merge_spec!(
                       base_spec(),
                       deltas(%{state: [%{name: :count, type: :string, default: "", line: 20}]}),
                       __ENV__
                     )
                   end
    end

    test "retyping a key the base never reads is allowed (attr :label in the fixture)" do
      merged =
        Extension.merge_spec!(
          base_spec(),
          deltas(%{
            attrs: [%{name: :label, type: :integer, required: false, default: 5, line: 20}]
          }),
          __ENV__
        )

      assert Enum.find(merged.attrs, &(&1.name == :label)).type == :integer
    end

    test "an event rename may also extend detail but never retype it" do
      assert_raise CompileError, ~r/narrows the inherited detail key/, fn ->
        Extension.merge_spec!(
          base_spec(),
          deltas(%{
            events: [
              %{name: "persona-select", detail: %{id: :integer}, renames: "pick", line: 20}
            ]
          }),
          __ENV__
        )
      end
    end
  end

  # -- brief 2d: regions + slot_template (compile level, §5.4/§5.7) -------------

  defp compile_region_base(id) do
    dir = Path.join(@tmp_dir, "tessera_ext_rbase_#{id}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "base_region_#{id}.ex")
    mod = "Tessera.Ext.RBase#{id}"

    Code.compile_string(
      """
      defmodule #{mod} do
        use Noizu.Tessera.Component, tag: "ext-rbase-#{id}", js: "rbase_#{id}.mjs"
        attr :label, :string, required: true
        state :count, :integer, default: 0
        event "row-pick", detail: %{id: :string}
        template ~TSR'<div class="card">{%region :header}<h2>hdr</h2>{%endregion}<ul><li class="outer">{%region :outer}O{%region :inner}I<em>{@label}</em>{%endregion}x{%endregion}</li></ul></div>'
        action :pick, fn state, _params ->
          emit("row-pick", %{id: "x"})
          state
        end
      end
      """,
      path
    )

    {String.to_atom("Elixir." <> mod), dir}
  end

  defp artifact(dir, tag, suffix), do: Path.join(dir, "#{tag}.#{suffix}")

  describe "regions + slot_template (compile level, §5.4)" do
    test "a fresh base compiles region methods into its element module" do
      id = :erlang.unique_integer([:positive])
      {_base, dir} = compile_region_base(id)
      element = File.read!(artifact(dir, "ext-rbase-#{id}", "element.generated.mjs"))

      assert element =~ "__region_header() {"
      assert element =~ "__region_outer() {"
      assert element =~ "__region_inner() {"
      assert element =~ "${this.__region_header()}"
      assert element =~ "${this.__region_outer()}"
    end

    test "region names with nested sets survive into the spec" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_region_base(id)
      spec = base.__tessera_spec__()

      assert spec.regions == [
               %{name: :header, nested: []},
               %{name: :outer, nested: [:inner]},
               %{name: :inner, nested: []}
             ]
    end

    test "slot_template override composes via {%super%} → super.__region_x()" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_region_base(id)

      derived =
        compile_derived(base, id, ~s(tag: "ext-rder-#{id}"), """
        slot_template :header, ~TSR'<h2 class="vh">{%super%}</h2>'
        """)

      spec = derived.__tessera_spec__()
      assert spec.region_overrides == [:header]

      dir = Path.join(@tmp_dir, "tessera_ext_derived_#{id}")
      element = File.read!(artifact(dir, "ext-rder-#{id}", "element.generated.mjs"))
      assert element =~ "__region_header() {"
      assert element =~ "super.__region_header()"
      # regions the derived never overrides ride the ES chain — not re-emitted
      refute element =~ "__region_outer() {"
    end

    test "override of a nesting region must keep the nested region set (§5.7 mismatch)" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_region_base(id)

      assert_raise CompileError, ~r/region mismatch.*nested region set/, fn ->
        compile_derived(base, id, ~s(tag: "ext-rder-#{id}"), """
        slot_template :outer, ~TSR'<div class="flat">{%super%}</div>'
        """)
      end
    end

    test "override that keeps the nested set compiles and redefines the nested region too" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_region_base(id)

      derived =
        compile_derived(base, id, ~s(tag: "ext-rder-#{id}"), """
        slot_template :outer, ~TSR'<div class="v-outer">{%region :inner}<b>v</b>{%endregion}{%super%}</div>'
        """)

      assert derived.__tessera_spec__().region_overrides == [:outer]
      dir = Path.join(@tmp_dir, "tessera_ext_derived_#{id}")
      element = File.read!(artifact(dir, "ext-rder-#{id}", "element.generated.mjs"))
      assert element =~ "super.__region_outer()"
      assert element =~ "__region_inner() {"
    end

    test "override of an unknown region is a CompileError (§5.7)" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_region_base(id)

      assert_raise CompileError,
                   ~r/unknown override.*slot_template :nope.*declares no region/,
                   fn ->
                     compile_derived(base, id, ~s(tag: "ext-rder-#{id}"), """
                     slot_template :nope, ~TSR"<b>x</b>"
                     """)
                   end
    end

    test "duplicate overrides of the same region are a CompileError" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_region_base(id)

      assert_raise CompileError, ~r/duplicate tessera slot_template/, fn ->
        compile_derived(base, id, ~s(tag: "ext-rder-#{id}"), """
        slot_template :header, ~TSR"<h2>a</h2>"
        slot_template :header, ~TSR"<h2>b</h2>"
        """)
      end
    end

    test "slot_template on a fresh component is a CompileError" do
      id = :erlang.unique_integer([:positive])
      dir = Path.join(@tmp_dir, "tessera_ext_rfresh_#{id}")
      File.mkdir_p!(dir)

      assert_raise CompileError, ~r/slot_template.*on a fresh component/, fn ->
        Code.compile_string(
          """
          defmodule Tessera.Ext.RFresh#{id} do
            use Noizu.Tessera.Component, tag: "ext-rfresh-#{id}", js: "rfresh_#{id}.mjs"
            template ~TSR"<div>x</div>"
            slot_template :header, ~TSR"<h2>a</h2>"
          end
          """,
          Path.join(dir, "rfresh.ex")
        )
      end
    end

    test "{%super%} in a base template (outside any override) fails the compile" do
      id = :erlang.unique_integer([:positive])
      dir = Path.join(@tmp_dir, "tessera_ext_rsuper_#{id}")
      File.mkdir_p!(dir)

      assert_raise CompileError, ~r/only valid inside a slot_template/, fn ->
        Code.compile_string(
          """
          defmodule Tessera.Ext.RSuper#{id} do
            use Noizu.Tessera.Component, tag: "ext-rsuper-#{id}", js: "rsuper_#{id}.mjs"
            template ~TSR"<div>{%region :a}{%super%}{%endregion}</div>"
          end
          """,
          Path.join(dir, "rsuper.ex")
        )
      end
    end

    test "region nesting beyond 8 fails the compile" do
      id = :erlang.unique_integer([:positive])
      dir = Path.join(@tmp_dir, "tessera_ext_rdeep_#{id}")
      File.mkdir_p!(dir)

      body =
        Enum.map_join(1..9, "", fn i -> "{%region :r#{i}}" end) <>
          "x" <> String.duplicate("{%endregion}", 9)

      assert_raise CompileError, ~r/nest more than 8 regions deep/, fn ->
        Code.compile_string(
          """
          defmodule Tessera.Ext.RDeep#{id} do
            use Noizu.Tessera.Component, tag: "ext-rdeep-#{id}", js: "rdeep_#{id}.mjs"
            template ~TSR"<div>#{body}</div>"
          end
          """,
          Path.join(dir, "rdeep.ex")
        )
      end
    end
  end

  describe "event rename end-to-end (compile level, §5.6)" do
    test "rename rewrites the inherited emission and shadows the action; base artifacts untouched" do
      id = :erlang.unique_integer([:positive])
      {base, base_dir} = compile_region_base(id)

      derived =
        compile_derived(base, id, ~s(tag: "ext-rder-#{id}"), """
        event "persona-select", detail: %{persona: :string}, renames: "row-pick"
        """)

      spec = derived.__tessera_spec__()
      assert Enum.map(spec.events, & &1.name) == ["persona-select"]
      [ev] = spec.events
      assert ev.detail == %{id: :string, persona: :string}
      assert ev.renamed_from == "row-pick"

      dir = Path.join(@tmp_dir, "tessera_ext_derived_#{id}")
      element = File.read!(artifact(dir, "ext-rder-#{id}", "element.generated.mjs"))
      # rewritten emission + shadowing re-emit of the base action
      assert element =~ ~S|emit(this, "persona-select"|
      refute element =~ ~S|emit(this, "row-pick"|
      assert element =~ "__action_pick"

      base_element = File.read!(artifact(base_dir, "ext-rbase-#{id}", "element.generated.mjs"))
      assert base_element =~ ~S|emit(this, "row-pick"|
      refute base_element =~ "persona-select"

      contract_files = Path.wildcard(Path.join(dir, "*.contract.generated.mjs"))
      assert contract_files != []
      contract = contract_files |> hd() |> File.read!()
      assert contract =~ "persona-select"
      refute contract =~ "row-pick"
    end

    test "type-change guard fires on a compile-level derived override" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_region_base(id)

      assert_raise CompileError, ~r/type-change guard/, fn ->
        compile_derived(base, id, ~s(tag: "ext-rder-#{id}"), """
        attr :label, :integer, required: true
        """)
      end
    end

    test "detail narrowing fires on a compile-level derived redeclare" do
      id = :erlang.unique_integer([:positive])
      {base, _dir} = compile_region_base(id)

      assert_raise CompileError, ~r/narrows the inherited detail key/, fn ->
        compile_derived(base, id, ~s(tag: "ext-rder-#{id}"), """
        event "row-pick", detail: %{id: :integer}
        """)
      end
    end
  end

  # -- tag-takeover chain (§5.9, brief 2e) — X-19's compile-time half ----------

  describe "tag takeover chain (§5.9): depth → priority → module name" do
    test "chain_order sorts depth, then priority, then module name (innermost first)" do
      entries = [
        %{depth: 2, priority: 0, module: "App.Ccc"},
        %{depth: 1, priority: 10, module: "App.Bbb"},
        %{depth: 1, priority: 0, module: "App.Mmm"},
        %{depth: 1, priority: 0, module: "App.Aaa"}
      ]

      assert Enum.map(Extension.chain_order(entries), & &1.module) == [
               "App.Aaa",
               "App.Mmm",
               "App.Bbb",
               "App.Ccc"
             ]
    end

    test "takeover?/chain_depth classify the conformance takeover fixtures" do
      base = Tessera.TestFixtures.Conformance.Takeover.__tessera_spec__()
      aaa = Tessera.TestFixtures.Conformance.TakeoverExtAaa.__tessera_spec__()
      bbb = Tessera.TestFixtures.Conformance.TakeoverExtBbb.__tessera_spec__()
      ccc = Tessera.TestFixtures.Conformance.TakeoverExtCcc.__tessera_spec__()

      refute Extension.takeover?(base)
      assert Extension.takeover?(aaa)
      assert Extension.takeover?(bbb)
      assert Extension.takeover?(ccc)

      # every layer registers under the BASE tag (D1 takeover)
      assert aaa.tag == base.tag
      assert bbb.tag == base.tag
      assert ccc.tag == base.tag

      # dependency depth walks the derived_from spine; priority: rides the spec
      assert Extension.chain_depth(base) == 0
      assert Extension.chain_depth(aaa) == 1
      assert Extension.chain_depth(bbb) == 1
      assert Extension.chain_depth(ccc) == 2
      assert aaa.priority == 0
      assert bbb.priority == 10
    end

    test "takeover artifacts carry the base tag + module stem, siblings never clobber (§5.8)" do
      base = Tessera.TestFixtures.Conformance.Takeover.__tessera_spec__()
      aaa = Tessera.TestFixtures.Conformance.TakeoverExtAaa.__tessera_spec__()

      assert Extension.artifact_stem(base) == "tsr-conf-takeover"
      assert Extension.artifact_stem(aaa) == "tsr-conf-takeover__takeover_ext_aaa"
      assert Extension.snake_stem(aaa) == "tsr_conf_takeover__takeover_ext_aaa"
    end

    test "chain conflict: same-depth siblings overriding one action warn naming BOTH + the winner" do
      id_a = :erlang.unique_integer([:positive])
      id_b = :erlang.unique_integer([:positive])
      {base, _dir} = compile_base(id_a)

      compile_derived(base, id_a, ~s(tag: :inherit, priority: 5), """
      action :increment, fn state, _params -> %{state | count: state.count + 10} end
      """)

      warning =
        capture_io(:stderr, fn ->
          compile_derived(base, id_b, ~s(tag: :inherit, priority: 5), """
          action :increment, fn state, _params -> %{state | count: state.count + 20} end
          """)
        end)

      # §5.7: names both modules, the §5.9 winner, the contested body, and
      # that the inner layer stays silent until the dispatch goes down-chain
      assert warning =~ "chain conflict"
      assert warning =~ "Tessera.Ext.Derived#{id_a}"
      assert warning =~ "Tessera.Ext.Derived#{id_b}"
      assert warning =~ "increment"
      assert warning =~ "base_action/3"

      # same depth + same priority ⇒ module name resolves the tie: the
      # alphabetically-LATER module sits outermost and WINS
      outer = Enum.max(["Tessera.Ext.Derived#{id_a}", "Tessera.Ext.Derived#{id_b}"])
      assert warning =~ "#{outer} sits outermost"
    end

    test "a takeover layer compiles a registry mixin artifact, not an element module" do
      aaa = Tessera.TestFixtures.Conformance.TakeoverExtAaa.__tessera_spec__()
      stem = Extension.artifact_stem(aaa)

      source =
        IO.iodata_to_binary([
          Noizu.Tessera.Component.LitCodegen.element_module(aaa),
          Noizu.Tessera.Component.LitCodegen.wrapper_module(aaa)
        ])

      # the wrapper exports the MIXIN and never a class; the element module
      # queues via extendElement and never defines the tag
      assert source =~ "extendElement("
      assert source =~ "export { mixin }"
      refute source =~ "export { Tsr"
      assert source =~ ~s(export const tag = "tsr-conf-takeover";)
      assert stem == "tsr-conf-takeover__takeover_ext_aaa"
    end

    test "minting a fresh tag FROM a takeover layer raises (layers ship as mixins)" do
      fresh = "ext-fresh-#{:erlang.unique_integer([:positive])}"

      assert_raise CompileError, ~r/cannot mint a fresh tag from the tag-takeover layer/, fn ->
        compile_derived(
          Tessera.TestFixtures.Conformance.TakeoverExtBbb,
          :erlang.unique_integer([:positive]),
          ~s(tag: "#{fresh}")
        )
      end
    end
  end
end
