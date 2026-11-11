defmodule Noizu.Tessera.Registry do
  @moduledoc false

  # Discovers tessera component modules across the current Mix project and its
  # loaded deps, by scanning each app's compiled beam dir for modules that
  # export `__tessera_manifest__/0`. Shared by `mix tessera.manifest` and
  # `mix tessera.install`.

  @doc "Apps considered: the current project plus all declared Mix deps."
  @spec tessera_apps() :: [atom()]
  def tessera_apps do
    current = current_app()
    deps = Mix.Project.deps_paths() |> Map.keys()

    [current | deps] |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
  end

  @doc "Modules of `app` that export `__tessera_manifest__/0`, sorted."
  @spec tessera_modules(atom()) :: [module()]
  def tessera_modules(app) when is_atom(app) do
    app_modules(app)
    |> Enum.filter(&component_module?/1)
    |> Enum.sort()
  end

  @doc "All tessera component modules across every considered app, sorted."
  @spec all_modules() :: [module()]
  def all_modules do
    tessera_apps()
    |> Enum.flat_map(&tessera_modules/1)
    |> Enum.sort()
  end

  @doc "Modules of `app` that `use Noizu.Tessera.Package` (export `__tessera_package__/0`), sorted."
  @spec package_modules(atom()) :: [module()]
  def package_modules(app) when is_atom(app) do
    app_modules(app)
    |> Enum.filter(&package_module?/1)
    |> Enum.sort()
  end

  @doc "All tessera package modules across every considered app, sorted."
  @spec all_package_modules() :: [module()]
  def all_package_modules do
    tessera_apps()
    |> Enum.flat_map(&package_modules/1)
    |> Enum.sort()
  end

  @doc "The current Mix project's app name (nil outside a project)."
  @spec current_app() :: atom() | nil
  def current_app do
    Mix.Project.get() && Mix.Project.config()[:app]
  end

  @doc """
  Resolves one package module for the mix tasks: an explicit module name, or
  the current project's single package. Returns `{:ok, module}` or
  `{:error, message}` (the tasks turn the message into `Mix.raise`).
  """
  @spec resolve_package(String.t() | nil) :: {:ok, module()} | {:error, String.t()}
  def resolve_package(name) when is_binary(name) do
    mod = Module.concat([name])

    if load(mod) and function_exported?(mod, :__tessera_package__, 0) do
      {:ok, mod}
    else
      {:error,
       "#{name} is not a loaded tessera package — it must `use Noizu.Tessera.Package` " <>
         "and be compiled (run `mix compile` first)"}
    end
  end

  def resolve_package(nil) do
    case package_modules(current_app()) do
      [mod] ->
        {:ok, mod}

      [] ->
        {:error,
         "no tessera package found in the current project — declare one with " <>
           "`use Noizu.Tessera.Package, components: [...]`, compile, and re-run"}

      mods ->
        {:error,
         "multiple tessera packages in the current project " <>
           "(#{Enum.map_join(mods, ", ", &inspect/1)}) — pass --package Module"}
    end
  end

  @doc "`priv/js/package.json` of a dep app, when the app ships a JS runtime."
  @spec app_js_package(atom()) :: {String.t(), String.t()} | nil
  def app_js_package(app) when is_atom(app) do
    case Mix.Project.deps_paths()[app] do
      nil ->
        nil

      src ->
        path = Path.join([src, "priv", "js", "package.json"])

        with true <- File.exists?(path),
             {:ok, json} <- File.read(path),
             {:ok, map} <- Jason.decode(json),
             name when is_binary(name) <- map["name"] do
          {name, path}
        else
          _ -> nil
        end
    end
  end

  @doc "Loads a beam module by name; false when unavailable."
  @spec load(module()) :: boolean()
  def load(mod) do
    match?({:module, ^mod}, Code.ensure_loaded(mod))
  end

  defp component_module?(mod) do
    load(mod) and function_exported?(mod, :__tessera_manifest__, 0)
  end

  defp package_module?(mod) do
    load(mod) and function_exported?(mod, :__tessera_package__, 0)
  end

  # Beam dirs, in preference order: the current project's compile path, a dep's
  # build-path ebin, an OTP-lib ebin (last resort, pre-OTP-29 style lookup).
  defp app_modules(app) do
    dir =
      cond do
        app == current_app() ->
          Mix.Project.compile_path()

        is_binary(Mix.Project.deps_paths()[app]) ->
          Path.join([Mix.Project.build_path(), "lib", to_string(app), "ebin"])

        true ->
          Path.join([:code.lib_dir(), to_string(app), "ebin"])
      end

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".beam"))
        |> Enum.map(&Path.rootname/1)
        |> Enum.map(&String.to_atom/1)

      {:error, _} ->
        []
    end
  end
end
