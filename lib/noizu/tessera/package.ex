defmodule Noizu.Tessera.Package do
  @moduledoc """
  `use Noizu.Tessera.Package, components: [MyApp.PersonaCard, ...]`

  Marks a library as a tessera component package:

    * `components/0` — the component module list, verbatim;
    * `manifest/0` — every component's `__tessera_manifest__/0` entry, in
      list order;
    * `cem/0` — the package's Custom Elements Manifest
      (`Noizu.Tessera.Codegen.cem/1` over the components' specs);
    * `__tessera_package__/0` — discovery marker used by the mix tasks.

  Gallery support is included by default: every package exposes `cem/0`,
  and `mix tessera.gen.gallery` scaffolds the built-in interactive gallery
  (live demos + typed attr/prop editors + slot editing + event log) from it
  — no opt-in flag. `mix tessera.cem` writes the package's
  `custom-elements.json` standalone.

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

      @doc false
      @spec __tessera_package__() :: %{components: [module()]}
      def __tessera_package__, do: %{components: unquote(components)}

      @doc "The aggregated manifest entries of this package's components."
      @spec manifest() :: [map()]
      def manifest do
        Enum.map(components(), fn mod ->
          mod.__tessera_manifest__()
        end)
      end

      @doc """
      The package's Custom Elements Manifest (schemaVersion "1.0.0") — the
      same shape `mix tessera.cem` writes and the built-in gallery reads.
      """
      @spec cem() :: map()
      def cem do
        Noizu.Tessera.Codegen.cem(Enum.map(components(), & &1.__tessera_spec__()))
      end
    end
  end
end
