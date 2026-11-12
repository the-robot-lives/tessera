defmodule Noizu.Tessera.Hologram.RenderTest do
  use ExUnit.Case, async: true

  alias Noizu.Tessera.Hologram.Render

  defmodule SsrCounter do
    use Hologram.Component

    prop :label, :string, default: "Count"
    prop :step, :integer, default: 1

    def init(props, component) do
      Hologram.Component.put_state(component, count: 0, step: Map.get(props, :step, 1))
    end

    # SSR author contract: server init mirrors the client init.
    def init(props, component, server), do: {init(props, component), server}

    def template do
      ~HOLO"""
      <div class="tsr-counter" data-cy="ssr-root"><span class="label">{@label}</span> <span class="count">{@count}</span></div>
      """
    end
  end

  defmodule ClientOnlyInit do
    use Hologram.Component

    # Only the CLIENT init — violates the SSR author contract.
    def init(_props, component), do: Hologram.Component.put_state(component, count: 0)

    def template do
      ~HOLO"<span>{@count}</span>"
    end
  end

  defmodule GenuineTemplateKeyError do
    use Hologram.Component

    # Full contract honoured (init/3 present), but the template itself raises
    # a KeyError on a keyword-list term — a real bug, not a state miss.
    def init(props, component),
      do: Hologram.Component.put_state(component, opts: Map.get(props, :opts, []))

    def init(props, component, server), do: {init(props, component), server}

    def template do
      ~HOLO"<span>{Keyword.fetch!(@opts, :missing)}</span>"
    end
  end

  defmodule GenuineInitKeyError do
    use Hologram.Component

    # init/3 present but raises its own KeyError on a plain-map term
    # (shape-identical to a state miss) — must propagate untouched.
    def init(props, component),
      do: Hologram.Component.put_state(component, x: Map.fetch!(props, :required))

    def init(props, component, server), do: {init(props, component), server}

    def template do
      ~HOLO"<span>{@x}</span>"
    end
  end

  test "a component without init/3 fails with the author-contract fix, not a bare KeyError" do
    error =
      assert_raise ArgumentError, fn ->
        Render.element(ClientOnlyInit, "client-only")
      end

    assert error.message =~ "read state key :count"
    assert error.message =~ "def init(props, component, server)"
  end

  test "a genuine template KeyError surfaces untouched, not rewritten as the author-contract error" do
    error =
      assert_raise KeyError, fn ->
        Render.element(GenuineTemplateKeyError, "genuine-kw")
      end

    assert error.key == :missing
    refute is_map(error.term)
  end

  test "a KeyError raised inside the author's own init/3 surfaces untouched" do
    error =
      assert_raise KeyError, fn ->
        Render.element(GenuineInitKeyError, "genuine-init")
      end

    assert error.key == :required
    assert is_map(error.term)
  end

  test "element/4 emits a declarative shadow root holding the server host" do
    html = Render.element(SsrCounter, "ssr-counter", %{label: "pings", step: 2})

    assert html =~
             ~r{^<ssr-counter tsr-props="[^"]+"><template shadowrootmode="open"><div data-tessera-holo-host>}

    assert html =~ ~s(<span class="label">pings</span>)
    assert html =~ ~s(<span class="count">0</span>)
    assert String.ends_with?(html, "</div></template></ssr-counter>")
  end

  test "tsr-props carries camelCase JSON, HTML-escaped" do
    html = Render.element(SsrCounter, "ssr-counter", %{label: ~s(a "b" <c>), step: 2})
    [_, attr] = Regex.run(~r/tsr-props="([^"]*)"/, html)

    decoded =
      attr
      |> String.replace("&quot;", "\"")
      |> String.replace("&lt;", "<")
      |> String.replace("&gt;", ">")
      |> String.replace("&amp;", "&")
      |> Jason.decode!()

    assert decoded == %{"label" => ~s(a "b" <c>), "step" => 2}
    assert Render.props_json(%{"max_count" => 3}) == ~s({"maxCount":3})
  end

  test "defaults apply and no props means no tsr-props attribute" do
    html = Render.element(SsrCounter, "ssr-counter")

    assert html =~ ~r{^<ssr-counter><template}
    assert html =~ ~s(<span class="label">Count</span>)
  end

  test "the cid never appears in the markup" do
    refute Render.element(SsrCounter, "ssr-counter", %{}, cid: "tssr_secret") =~ "tssr_secret"
  end
end
