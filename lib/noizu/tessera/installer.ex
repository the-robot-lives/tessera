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
