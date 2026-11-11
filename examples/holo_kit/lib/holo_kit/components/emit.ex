defmodule HoloKit.Emit do
  @moduledoc """
  The tessera emit seam for ordinary Hologram components (Tier 2 spike).

  A component hosted inside a tessera custom element has no parent Hologram
  component to `put_action/2` at, so this helper targets a **synthetic
  host bridge**: `mount/2` derives the bridge cid from the component's own
  `cid` prop (`<cid>$h`), and `emit/3` queues a plain `put_action/2` at that
  cid. The tessera runtime intercepts any action whose target ends in
  `$h` **before** Hologram's dispatcher runs it, and re-dispatches it as a
  composed DOM `CustomEvent`:

  * action name `:item_saved` → event type `"item-saved"` (snake → kebab),
  * `params` map → event `detail` with camelCased keys
    (`%{item_id: 1}` → `{itemId: 1}`),

  which is exactly the CONTRACT.md §1 wire shape the `data-tsr-on` bridge
  already understands on Hologram hosts.

  On a normal Hologram page (component used directly, no tessera element)
  the interception never happens and the action would target a missing cid —
  components destined for both worlds should emit only under tessera hosts.
  That is the one tessera-authored convention in an otherwise stock
  Hologram component.
  """

  @host_suffix "$h"

  @doc """
  Call from `init/2` as `component |> HoloKit.Emit.mount(props)`. Stores the
  synthetic host-bridge cid derived from the component's `cid` prop under
  the reserved `:__tessera_host__` state key.
  """
  def mount(component, props) do
    cid = Map.get(props, :cid, "")
    host = cid <> @host_suffix

    Hologram.Component.put_state(component, :__tessera_host__, host)
  end

  @doc """
  Emits `event` (a snake_case atom, e.g. `:item_saved`) with `params`
  (a map with snake_case keys) as a composed CustomEvent on the host
  custom element.
  """
  def emit(component, event, params \\ %{}) do
    host = Map.get(component.state, :__tessera_host__, "")

    Hologram.Component.put_action(component,
      name: event,
      params: params,
      target: host
    )
  end
end
