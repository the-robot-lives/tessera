defmodule HologramDemo.Web.Hologram.Pages.SecondPage do
  @moduledoc """
  Panel (e): the `<Link>` navigation round trip. Renders another stateless
  tessera card to prove elements hydrate correctly after client-side
  navigation (no NotSupportedError, custom element still live).
  """

  use Hologram.Page

  alias HologramDemo.Web.Hologram.Layouts.RootLayout
  alias PersonaKit.PersonaCard

  route "/second"
  layout RootLayout, page_title: "tessera demo — second"

  def template do
    ~HOLO"""
    <h1 data-cy="second-title">tessera demo — second page</h1>
    <p data-cy="second-note">Round trip: navigate main ⇄ second; the card below must stay live.</p>
    <PersonaCard display_name="Linus Torvalds" tagline="talk is cheap" />
    """
  end
end
