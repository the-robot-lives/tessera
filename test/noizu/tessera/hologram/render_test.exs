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
