defmodule PersonaKit do
  @moduledoc """
  PersonaKit — a tessera **component package** example.

  Ships two web components (`persona-card`, `persona-picker`) as Elixir
  spec modules with colocated `.mjs` elements. Hosts depend on this package
  and run `mix tessera.install` once: the install task adds
  `@noizu/tessera-core` (and `lit`) to the host's `assets/package.json`,
  and the Hologram adapter inside each component wires rendering + the
  event bridge with zero hand-written glue (CONTRACT.md §3/§5).

  This module declares the package's component inventory for
  `mix tessera.manifest` (`docs/CONSUMING.md` §4).
  """

  use Noizu.Tessera.Package,
    components: [PersonaKit.PersonaCard, PersonaKit.PersonaPicker]
end
