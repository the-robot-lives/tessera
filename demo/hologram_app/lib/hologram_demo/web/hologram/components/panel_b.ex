defmodule HologramDemo.Web.Hologram.Components.PanelB do
  @moduledoc """
  Panel (b): a stateless wrapper hosting the STATEFUL card instance
  `cid="p1"`. The tuple binding `{{:chose, target: "p1"}}` (CONTRACT.md §3)
  routes the card's `persona-select` events to the card module's own
  `action/3` — not to this wrapper and not to the page.
  """

  use Hologram.Component

  alias PersonaKit.PersonaCard

  def template do
    ~HOLO"""
    <div data-cy="panel-b-inner">
      <PersonaCard
        cid="p1"
        display_name="Grace Hopper"
        tagline="the compiler is the program"
        on_persona_select={{:chose, target: "p1"}}
      />
    </div>
    """
  end
end
