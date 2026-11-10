defmodule Noizu.Tessera.Installer do
  @moduledoc false

  # Machinery behind `mix tessera.install` (modeled on the
  # `tobor_kit_hologram.install` task). The JSON merge itself is a pure
  # function so idempotency is unit-tested without a Mix project.

  @core_dep_name "@noizu/tessera-core"
  @lit_version "^3"

  @doc """
  Dependencies `mix tessera.install` adds: `@noizu/tessera-core` as a `file:`
  dep on this hex package's `priv/js` (the Phoenix `file:../deps/...` idiom),
  `lit ^3`, plus `file:` entries for dep apps that ship their own
  `priv/js` runtime.
  """
  @spec additions(String.t(), [{String.t(), String.t()}]) :: %{String.t() => String.t()}
  def additions(core_js_relpath, dep_entries \\ []) when is_binary(core_js_relpath) do
    Map.merge(
      %{@core_dep_name => "file:" <> core_js_relpath, "lit" => @lit_version},
      Map.new(dep_entries)
    )
  end

  @doc """
  `[{name, "file:<relpath>"}]` entries for every dep app in `deps_paths`
  (an `{app_atom => project_root}` map) that ships a tessera js package —
  `priv/js/package.json` with a `name` — relative to `assets_dir`. Apps
  equal to `current_app` are skipped (their runtime is the core entry).
  Pure function of its arguments so it is unit-testable without Mix.
  """
  @spec dep_js_entries(map(), String.t(), atom() | nil) :: [{String.t(), String.t()}]
  def dep_js_entries(deps_paths, assets_dir, current_app)
      when is_map(deps_paths) and is_binary(assets_dir) do
    deps_paths
    |> Enum.reject(fn {app, _root} -> app == current_app end)
    |> Enum.flat_map(fn {_app, root} ->
      case js_package_name(root) do
        {name, js_dir} ->
          [{name, "file:" <> Path.relative_to(js_dir, assets_dir)}]

        nil ->
          []
      end
    end)
  end

  @doc """
  `{name, js_dir}` when `project_root/priv/js/package.json` declares a
  `name`; the returned `js_dir` is the `priv/js` directory itself.
  """
  @spec js_package_name(String.t()) :: {String.t(), String.t()} | nil
  def js_package_name(project_root) when is_binary(project_root) do
    js_dir = Path.join(project_root, Path.join(["priv", "js"]))
    path = Path.join(js_dir, "package.json")

    with true <- File.exists?(path),
         {:ok, json} <- File.read(path),
         {:ok, map} <- Jason.decode(json),
         name when is_binary(name) <- map["name"] do
      {name, js_dir}
    else
      _ -> nil
    end
  end

  @doc """
  Absolute path of the core `priv/js` runtime directory for the host app.

  Resolved through `deps_paths` (what Mix actually resolved — path deps may
  be transitive and are NOT guaranteed to be symlinked under `deps/<name>`,
  e.g. recent Mix versions link only direct path deps), falling back to the
  conventional `deps/noizu_tessera` join for callers that predate
  `deps_paths/0`.
  """
  @spec core_js_dir(map(), String.t()) :: {:ok, String.t()} | :error
  def core_js_dir(deps_paths, deps_path) when is_map(deps_paths) and is_binary(deps_path) do
    candidate =
      case Map.fetch(deps_paths, :noizu_tessera) do
        {:ok, root} when is_binary(root) ->
          root
          |> Path.expand()
          |> Path.join(Path.join(["priv", "js"]))

        :error ->
          Path.join([deps_path, "noizu_tessera", "priv", "js"])
      end

    if File.dir?(candidate), do: {:ok, candidate}, else: :error
  end

  @doc """
  Idempotent merge of `additions` into a decoded `package.json` map: keys that
  already exist keep their value, missing keys are added, every other
  top-level key is preserved untouched.
  """
  @spec merge_package_json(map(), map()) :: map()
  def merge_package_json(existing, additions) when is_map(existing) and is_map(additions) do
    deps = Map.get(existing, "dependencies", %{})

    merged_deps =
      Enum.reduce(additions, deps, fn {key, value}, acc ->
        if Map.has_key?(acc, key), do: acc, else: Map.put(acc, key, value)
      end)

    Map.put(existing, "dependencies", merged_deps)
  end

  @doc """
  Reads (or starts) `assets/package.json`, merges, and writes back pretty
  JSON only when the content changed. Returns `:written | :unchanged |
  {:error, term}`.
  """
  @spec merge_into_assets(String.t(), map()) :: :written | :unchanged | {:error, term()}
  def merge_into_assets(assets_dir, additions) do
    package_json_path = Path.join(assets_dir, "package.json")

    existing =
      case File.read(package_json_path) do
        {:ok, raw} ->
          case Jason.decode(raw) do
            {:ok, map} when is_map(map) -> map
            _ -> %{}
          end

        {:error, _} ->
          %{}
      end

    merged = merge_package_json(existing, additions)

    if merged == existing do
      :unchanged
    else
      with :ok <- File.mkdir_p(assets_dir),
           encoded = Jason.encode!(merged, pretty: true) <> "\n",
           :ok <- File.write(package_json_path, encoded) do
        :written
      else
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Runs `npm install` in `assets_dir`. Returns `{:ok, output}` or
  `{:error, exit_code, output}`.
  """
  @spec npm_install(String.t()) :: {:ok, String.t()} | {:error, non_neg_integer(), String.t()}
  def npm_install(assets_dir) do
    case System.cmd("npm", ["install"], cd: assets_dir, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, code, output}
    end
  end
end
