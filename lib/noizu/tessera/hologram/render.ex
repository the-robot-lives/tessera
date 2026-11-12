defmodule Noizu.Tessera.Hologram.Render do
  @moduledoc """
  Server-side rendering of Tier-2 (Hologram-runtime) elements as Declarative
  Shadow DOM (TESSER SSR-2, `docs/notes/ssr-dsd-spike.md` §4.2).

  `element/4` renders a Hologram component on the server with Hologram's own
  renderer (`Hologram.Template.Renderer.render_dom/3`, public 0.10 API) and
  wraps the result so the browser attaches it as the element's shadow root
  before any JavaScript runs:

      <counter-el tsr-props="{&quot;label&quot;:&quot;pings&quot;}">
        <template shadowrootmode="open">
          <div data-tessera-holo-host>…server HTML…</div>
        </template>
      </counter-el>

  When the Tier-2 runtime upgrades the element it finds that
  `[data-tessera-holo-host]` and HYDRATES onto it (adopt + morph, node
  identity preserved) instead of mounting from scratch.

  ## Author contract

  Hologram 0.10 splits client `init/2` from server `init/3`. A component
  rendered here must define `init/3` computing whatever its template reads,
  usually by mirroring the client init:

      def init(props, component, server), do: {init(props, component), server}

  Without it the server render raises on state the client init would have
  created. Server state that differs from the client init is reconciled by
  the first client patch (Lit-equivalent behaviour).

  Props are passed twice on purpose: to the server render (so the HTML
  matches) and as the `tsr-props` JSON attribute (camelCase keys, the same
  path the element reads on upgrade), so client and server see one value.

  Hologram is an optional dependency of this library; the renderer is resolved
  at runtime so hosts without Hologram still compile.
  """

  alias Noizu.Tessera.Naming

  @host_attr "data-tessera-holo-host"

  @doc """
  Render `module` as the custom element `tag` with a declarative shadow root.

  Options:

    * `:attrs` — extra host attributes (`%{"class" => "x"}`), HTML-escaped.
    * `:cid` — the server render cid (default `"tssr_ssr"`; never appears in
      the markup, the client mount owns its own cid after hydration).
  """
  @spec element(module(), String.t(), map() | keyword(), keyword()) :: String.t()
  def element(module, tag, props \\ %{}, opts \\ []) when is_atom(module) and is_binary(tag) do
    props = Map.new(props)
    inner = shadow_html(module, props, opts)

    attrs =
      opts
      |> Keyword.get(:attrs, %{})
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> maybe_put_props(props)

    "<#{tag}#{render_attrs(attrs)}><template shadowrootmode=\"open\">" <>
      "<div #{@host_attr}>#{inner}</div></template></#{tag}>"
  end

  @doc """
  The server-rendered component HTML (the host div's contents), without the
  element or template wrapper.
  """
  @spec shadow_html(module(), map(), keyword()) :: String.t()
  def shadow_html(module, props, opts \\ []) when is_atom(module) and is_map(props) do
    renderer = Module.concat([Hologram, Template, Renderer])
    env = struct(Module.concat([Hologram, Template, Renderer, Env]))
    server = struct(Module.concat([Hologram, Server]))
    cid = Keyword.get(opts, :cid, "tssr_ssr")

    unless Code.ensure_loaded?(renderer) do
      raise ArgumentError,
            "Noizu.Tessera.Hologram.Render needs the :hologram dependency (Tier-2 SSR)"
    end

    props_dom =
      Enum.map(props, fn {k, v} -> {to_string(k), [expression: {v}]} end) ++
        [{"cid", [expression: {cid}]}]

    try do
      {html, _registry, _server} =
        renderer.render_dom({:component, module, props_dom, []}, env, server)

      html
    rescue
      # SSR author contract (spike §4.3): Hologram's default init/3 is a no-op,
      # so a component that only defines the CLIENT init/2 renders its
      # template against empty state and KeyErrors on the first `@key`.
      # Re-raise with the fix instead of a bare KeyError.
      #
      # Narrowed (TESSER-029): only the genuine state-miss shape earns the
      # rewrite — see state_miss?/3. Any other KeyError is a real bug in the
      # author's code and re-raises untouched with its original stacktrace.
      error in KeyError ->
        if state_miss?(error, module, __STACKTRACE__) do
          reraise ArgumentError,
                  [
                    message:
                      "tessera SSR: #{inspect(module)} read state key #{inspect(error.key)} " <>
                        "that its server init did not set. Hologram renders on the server " <>
                        "with init/3, not the client init/2. Define it, usually by " <>
                        "mirroring the client init: " <>
                        "`def init(props, component, server), do: {init(props, component), server}` " <>
                        "(Noizu.Tessera.Hologram.Render moduledoc, Author contract)."
                  ],
                  __STACKTRACE__
        else
          reraise error, __STACKTRACE__
        end
    end
  end

  # Only the genuine SSR state-miss shape earns the author-contract rewrite.
  #
  # Three structural facts, verified empirically against Hologram 0.10
  # (raw-KeyError probes for every class; the drift-probe test in
  # render_test.exs pins them so an upstream change fails loudly instead of
  # silently re-classifying):
  #
  # 1. Template `@key` access compiles to `:erlang.map_get(key, vars)` over
  #    the merged props+state map (Renderer.render_stateful_component/5), so a
  #    state miss is a KeyError whose term is a PLAIN map. KeyErrors on
  #    keyword lists or structs (or tuples, etc.) are the author's own data
  #    bugs and must propagate raw.
  # 2. `vars` always carries `:cid` — TESSERA injects the `"cid"` expression
  #    into props_dom here (our contract, not Hologram's), and Hologram's
  #    renderer threads it into nested child components too. A KeyError whose
  #    term lacks `:cid` therefore did not miss against `vars`: it is a
  #    nested plain-map access (`Map.fetch!(@config, :k)` on state data) —
  #    the author's own bug, propagated raw. (Accepted residue: a nested map
  #    that itself contains a `:cid` key still gets the contract message.)
  # 3. A KeyError raised anywhere inside the author's init/3 call tree still
  #    carries the `{module, :init, 3}` frame on the stack, while Hologram's
  #    injected no-op default init/3 (defoverridable in Hologram.Component)
  #    can never raise. So an init frame present = the author's own failure.
  #    (Shape alone is not enough here: `Map.fetch!(props, :missing)` in
  #    init/3 raises on a plain map with `:cid` in it, identical to a miss.)
  defp state_miss?(%KeyError{term: term}, module, stacktrace)
       when is_map(term) and not is_struct(term) and is_map_key(term, :cid) do
    not Enum.any?(stacktrace, fn
      {^module, :init, 3, _meta} -> true
      _frame -> false
    end)
  end

  defp state_miss?(%KeyError{}, _module, _stacktrace), do: false

  @doc "Props as the `tsr-props` JSON the element reads (camelCase keys)."
  @spec props_json(map()) :: String.t()
  def props_json(props) when is_map(props) do
    props
    |> Map.new(fn {k, v} -> {camel(k), v} end)
    |> Jason.encode!()
  end

  defp maybe_put_props(attrs, props) when map_size(props) == 0, do: attrs
  defp maybe_put_props(attrs, props), do: Map.put(attrs, "tsr-props", props_json(props))

  defp camel(key) when is_atom(key), do: Naming.snake_to_camel(key)
  # Same split rule as Naming.snake_to_camel/1 without minting atoms from
  # caller-supplied string keys.
  defp camel(key) when is_binary(key) do
    [first | rest] = String.split(key, "_", trim: false)
    Enum.join([first | Enum.map(rest, &upcase_first/1)], "")
  end

  defp upcase_first(""), do: ""
  defp upcase_first(<<c::utf8, rest::binary>>), do: String.upcase(<<c::utf8>>) <> rest

  defp render_attrs(attrs) do
    attrs
    |> Enum.sort()
    |> Enum.map_join(fn {k, v} -> " #{k}=\"#{escape(to_string(v))}\"" end)
  end

  defp escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
