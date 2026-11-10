defmodule Noizu.Tessera.Package do
  @moduledoc """
  `use Noizu.Tessera.Package, components: [MyApp.PersonaCard, ...]`

  Marks a library as a tessera component package:

    * `components/0` — the component module list, verbatim;
    * `manifest/0` — every component's `__tessera_manifest__/0` entry, in
      list order.

  `mix tessera.manifest` aggregates across all loaded apps that use this
  macro, and `mix tessera.install` adds `file:` npm entries for component
  packages that ship a `priv/js` runtime.
  """

  @doc false
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    caller = __CALLER__

    # `use` hands us the option values as AST — expand the component aliases
    # (e.g. {:__aliases__, _, [:MyApp, :PersonaCard]}) to module atoms.
    components =
      case Keyword.get(opts, :components, []) do
        list when is_list(list) -> Enum.map(list, &Macro.expand(&1, caller))
        other -> other
      end

    unless is_list(components) and components != [] and Enum.all?(components, &is_atom/1) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description:
          "Noizu.Tessera.Package expects components: [Module, ...] — got: #{inspect(components)}"
    end

    # Compile-time check for whatever is already compiled; modules compiled
    # later in the same project (or in deps still building) are checked at
    # runtime by manifest/0 instead.
    Enum.each(components, fn mod ->
      if Code.ensure_loaded(mod) == {:module, mod} and
           not function_exported?(mod, :__tessera_manifest__, 0) do
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description:
            "#{inspect(mod)} is not a tessera component — it must `use " <>
              "Noizu.Tessera.Component` (which defines __tessera_manifest__/0)"
      end
    end)

    quote bind_quoted: [components: components] do
      @doc "The tessera component modules declared by this package."
      @spec components() :: [module()]
      def components, do: unquote(components)

      @doc "The aggregated manifest entries of this package's components."
      @spec manifest() :: [map()]
      def manifest do
        Enum.map(components(), fn mod ->
          mod.__tessera_manifest__()
        end)
      end
    end
  end
end
