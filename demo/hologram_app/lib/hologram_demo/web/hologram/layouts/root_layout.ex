defmodule HologramDemo.Web.Hologram.Layouts.RootLayout do
  @moduledoc """
  Minimal demo layout: head + the Hologram client runtime, a nav (plain
  <span> hooks around the Links — Hologram <Link> drops unknown attributes,
  CONTRACT.md §5), and the page slot.
  """

  use Hologram.Component

  alias Hologram.UI.Link
  alias HologramDemo.Web.Hologram.Pages.MainPage
  alias HologramDemo.Web.Hologram.Pages.SecondPage

  prop :page_title, :string, default: "tessera demo"

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@page_title}</title>
        <Hologram.UI.Runtime />
      </head>
      <body>
        <nav data-cy="demo-nav">
          <span data-cy="nav-main"><Link to={MainPage}>main</Link></span>
          <span data-cy="nav-second"><Link to={SecondPage}>second</Link></span>
        </nav>
        <main><slot /></main>
      </body>
    </html>
    """
  end
end
