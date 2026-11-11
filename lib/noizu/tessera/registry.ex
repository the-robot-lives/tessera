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

  defp current_app do
    Mix.Project.get() && Mix.Project.config()[:app]
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
