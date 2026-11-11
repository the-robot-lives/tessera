defmodule Noizu.Tessera.Component.ExprTest do
  @moduledoc """
  SPIKE (spike/elixir-to-lit): restricted-subset translator — accept the
  subset, reject everything else BY NAME.
  """
  use ExUnit.Case, async: true

  alias Noizu.Tessera.Component.Expr

  defp ctx do
    %Expr{
      state_keys: MapSet.new([:count]),
      attrs: %{step: :integer, label: :string},
      props: %{items: :list},
      events: MapSet.new(["count-change", "chip-select"]),
      actions: MapSet.new([:increment]),
      module: __MODULE__,
      file: __ENV__.file,
      line: 0
    }
  end

  defp act(body) do
    {:fn, [], [{:->, [], [[{:state, [], Elixir}, {:params, [], Elixir}], body]}]}
  end

  defp translate!(ast), do: Expr.translate(ast, ctx())

  defp reject!(construct_name, code) when is_binary(code) do
    {:ok, ast} = Code.string_to_quoted(code)

    error =
      assert_raise CompileError, fn -> translate!(ast) end

    assert error.description =~ construct_name,
           "expected error naming #{inspect(construct_name)}, got: #{error.description}"
  end

  describe "accepts (in the subset)" do
    test "state reads and map update" do
      assert Expr.translate_action(act(quote do: %{state | count: state.count + 1}), ctx()) ==
               "({ ...state, count: (state.count + 1) })"
    end

    test "attr/prop reads become camelCase this reads" do
      assert translate!(quote do: @step) == "this.step"
      assert translate!(quote do: @label) == "this.label"
    end

    test "strict equality and boolean ops" do
      assert translate!(quote do: state.count == 1 and not (@label == "x")) ==
               "((state.count === 1) && (!(this.label === \"x\")))"
    end

    test "if expression form" do
      assert translate!(quote do: if(state.count > 0, do: "pos", else: "neg")) ==
               "((state.count > 0) ? (\"pos\") : (\"neg\"))"
    end

    test "string interpolation over subset expressions" do
      assert translate!(quote do: "count: #{state.count}") == "`count: ${state.count}`"
    end

    test "list/map access + literals" do
      assert translate!(quote do: params[:step]) == "params.step"
      assert translate!(quote do: params["k"]) == ~S|params["k"]|
      assert translate!(quote do: [1, 2, 3]) == "[1, 2, 3]"
    end

    test "emit/2 with camelCased detail keys" do
      js = translate!(quote do: emit("chip-select", %{chip_id: "a", selected: true}))
      assert js == ~S|emit(this, "chip-select", {chipId: "a", selected: true})|
    end

    test "allowlisted Kernel/String/Enum + pipe" do
      assert translate!(quote do: Kernel.abs(0 - 1)) == "Math.abs((0 - 1))"
      assert translate!(quote do: String.upcase(@label)) == "this.label.toUpperCase()"
      assert translate!(quote do: @label |> String.trim() |> String.downcase()) ==
               "this.label.trim().toLowerCase()"

      assert translate!(quote do: Enum.count(@items)) == "this.items.length"
    end

    test "Enum.map with single-clause callback" do
      js = translate!(quote do: Enum.map(@items, fn item -> item end))
      assert js == "this.items.map((item) => item)"
    end

    test "multi-expression action body becomes an IIFE" do
      js =
        Expr.translate_action(
          quote do
            fn state, _params ->
              emit("count-change", %{count: state.count})
              %{state | count: state.count}
            end
          end,
          ctx()
        )

      assert js =~ "(() => {"
      assert js =~ ~S|emit(this, "count-change", {count: state.count}); |
      assert js =~ "return ({ ...state, count: state.count }); })()"
    end
  end

  describe "rejects (outside the subset — each named in the error)" do
    test "case" do
      reject!("case", """
case state.count do
  1 -> :a
end
""")
    end

    test "cond" do
      reject!("cond", """
cond do
  true -> 1
end
""")
    end

    test "with" do
      reject!("with", """
with x <- 1 do
  x
end
""")
    end

    test "multi-clause fn" do
      error =
        assert_raise CompileError, fn ->
          Expr.translate_action(
            quote do
              fn
                state, %{a: 1} -> state
                state, _ -> state
              end
            end,
            ctx()
          )
        end

      assert error.description =~ "multi-clause fn"
    end

    test "capture syntax" do
      reject!("capture", """
Enum.map(@items, &String.upcase/1)
""")
    end

    test "module outside the allowlist" do
      reject!("Map", """
Map.get(state, :count, 0)
""")
    end

    test "allowlisted module, non-allowlisted function" do
      reject!("pad_leading", """
String.pad_leading(@label, 2)
""")
    end

    test "structs" do
      reject!("struct", """
%Counter{}
""")
    end

    test "tuples" do
      reject!("tuple", """
{1, 2}
""")
    end

    test "list concatenation" do
      reject!("++", """
[1] ++ [2]
""")
    end

    test "undeclared state key" do
      reject!("nope", """
state.nope
""")
    end

    test "undeclared attr in template expression" do
      reject!("does not resolve", """
@undeclared
""")
    end

    test "undeclared event in emit" do
      reject!("not declared", """
emit("nope-event", %{})
""")
    end

    test "assignment (bindings are outside the expression subset)" do
      reject!("=", """
x = state.count
""")
    end

    test "enum callback with wrong shape (two args)" do
      reject!("fn", """
Enum.map(@items, fn a, b -> a end)
""")
    end
  end

  describe "action arity/shape errors" do
    test "one-argument fn rejected" do
      error =
        assert_raise CompileError, fn ->
          Expr.translate_action(quote(do: fn state -> state end), ctx())
        end

      assert error.description =~ "exactly 2 arguments"
    end
  end
end
