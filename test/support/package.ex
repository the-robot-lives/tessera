defmodule Tessera.TestFixtures.Package do
  @moduledoc "Package-macro fixture over the PersonaCard golden-fixture component."

  use Noizu.Tessera.Package, components: [Tessera.TestFixtures.PersonaCard]
end
