defmodule Noizu.Tessera.Hologram.SsrLintTest do
  use ExUnit.Case, async: false
  # not async: Mix.shell() is global state and one test touches app env

  alias Noizu.Tessera.Hologram.Render

  defmodule OkCounter do
    use Hologram.Component

    prop :label, :string, default: "Count"

    def init(props, component), do: Hologram.Component.put_state(component, count: 0)
    def init(props, component, server), do: {init(props, component), server}

    def template do
      ~HOLO"<span>{@label}: {@count}</span>"
    end
  end

  defmodule ViolatingCounter do
    use Hologram.Component

    # Only the CLIENT init — violates the SSR author contract.
    def init(_props, component), do: Hologram.Component.put_state(component, count: 0)

    def template do
      ~HOLO"<span>{@count}</span>"
    end
  end

  defmodule BrokenHelper do
    use Hologram.Component

    # Contract honoured, but the template raises a genuine KeyError on a
    # keyword-list term — the lint surfaces it as :error, not :violation.
    def init(_props, component), do: Hologram.Component.put_state(component, opts: [])

    def init(props, component, server), do: {init(props, component), server}

    def template do
      ~HOLO"<span>{Keyword.fetch!(@opts, :missing)}</span>"
    end
  end

  # -- lint_component/2 -------------------------------------------------------

  test "a contract-honouring component lints :ok" do
    assert Render.lint_component(OkCounter) == :ok
  end

  test "a component violating the author contract lints {:violation, key}" do
    assert Render.lint_component(ViolatingCounter) == {:violation, :count}
  end

  test "a genuine template KeyError lints {:error, exception}, not a violation" do
    assert {:error, %KeyError{key: :missing}} = Render.lint_component(BrokenHelper)
  end

  test "an unknown module lints {:error, exception}" do
    assert {:error, %UndefinedFunctionError{}} = Render.lint_component(NoSuch.ComponentAnywhere)
  end

  # -- mix tessera.ssr_lint ---------------------------------------------------

  test "the task reports ok for clean components and passes" do
    output =
      ExUnit.CaptureIO.capture_io(:stdio, fn ->
        Mix.Tasks.Tessera.SsrLint.run([inspect(OkCounter)])
      end)

    assert output =~ ~r/ok\s+#{Regex.escape(inspect(OkCounter))}/
    assert output =~ "tessera.ssr_lint: 1 component(s) ok"
  end

  test "the task reports a violation and exits non-zero" do
    assert_raise Mix.Error, ~r/1 of 1 component\(s\) failed the SSR author contract/, fn ->
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Tessera.SsrLint.run([inspect(ViolatingCounter)])
      end)
    end
  end

  test "the task reports a genuine KeyError as an error and exits non-zero" do
    assert_raise Mix.Error, ~r/failed the SSR author contract/, fn ->
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Tessera.SsrLint.run([inspect(BrokenHelper)])
      end)
    end
  end

  test "the task mixes app-env and argv components, deduplicated" do
    Application.put_env(:tessera, :ssr_components, [OkCounter, ViolatingCounter])

    on_exit(fn -> Application.delete_env(:tessera, :ssr_components) end)

    assert_raise Mix.Error, ~r/1 of 2 component\(s\) failed/, fn ->
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Tessera.SsrLint.run([inspect(OkCounter)])
      end)
    end

    # dedup: OkCounter appeared once from env and once from argv — the total
    # linted set is 2, not 3, and the violation exit message names 1 of 2.
  end

  test "the task with no components and no app env is a clean no-op" do
    Application.delete_env(:tessera, :ssr_components)

    output =
      ExUnit.CaptureIO.capture_io(:stdio, fn ->
        Mix.Tasks.Tessera.SsrLint.run([])
      end)

    assert output =~ "nothing to lint"
  end
end
