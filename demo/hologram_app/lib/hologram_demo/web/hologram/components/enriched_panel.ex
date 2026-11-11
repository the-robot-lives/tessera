defmodule HologramDemo.Web.Hologram.Components.EnrichedPanel do
  @moduledoc """
  Panel (d): the EXTENDING.md extension demo.

  `install` runs `behaviors.add("persona-card", …)` from a `js_import`-ed
  module (client-side JS interop inside an action handler — the documented
  client-side hook). `mount_card` then mounts a FRESH stateless card, whose
  `connectedCallback` runs the behavior: the e2e suite asserts
  `data-tessera-enriched="true"` on a card that never existed when the
  behavior was installed.
  """

  use Hologram.Component

  use Hologram.JS

  alias PersonaKit.PersonaCard

  js_import :installDemoBehaviors, from: "./demo_behaviors.js"

  def init(_props, component, _server) do
    put_state(component, behaviors_installed: false, card_mounted: false)
  end

  def action(:install_behaviors, _params, component) do
    JS.call(:installDemoBehaviors, [])
    put_state(component, behaviors_installed: true)
  end

  def action(:mount_card, _params, component) do
    put_state(component, card_mounted: true)
  end

  def action(_other, _params, component), do: component

  def template do
    ~HOLO"""
    <div data-cy="panel-d-inner">
      <p data-cy="behaviors-status">
        behaviors: {if @behaviors_installed do "installed" else "off" end}
      </p>
      <button type="button" data-cy="install-behaviors" $click={:install_behaviors}>
        install behaviors
      </button>
      <button type="button" data-cy="mount-card" $click={:mount_card}>
        mount a fresh card
      </button>
      {%if @card_mounted}
        <div data-cy="panel-d-card-mount">
          <PersonaCard display_name="Alan Turing" tagline="of machines and code" />
        </div>
      {/if}
    </div>
    """
  end
end
