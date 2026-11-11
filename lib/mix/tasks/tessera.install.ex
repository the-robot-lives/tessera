defmodule Mix.Tasks.Tessera.Install do
  @shortdoc "Wire @noizu/tessera-core (file: dep) + lit into the host assets/package.json"

  @moduledoc """
  Prepares a Hologram host app's `assets/` for tessera components:

    * creates or merges `assets/package.json`, adding
      `"@noizu/tessera-core": "file:<relpath to deps/noizu_tessera/priv/js>"`
      and `"lit": "^3"`, plus `file:` entries for every dep app that ships its
      own tessera `priv/js` runtime. Idempotent: existing keys are never
      overwritten, unrelated keys preserved;
    * runs `npm install` in `assets/` unless `--no-npm` is given.

  Hologram resolves bare npm specifiers through the host's
  `assets/node_modules` (NODE_PATH), so components' `.mjs` files can import
  `@noizu/tessera-core` without any further wiring.

      mix tessera.install
      mix tessera.install --no-npm
  """

  use Mix.Task

  alias Noizu.Tessera.Installer

  @switches [no_npm: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, _positionals, _invalid} = OptionParser.parse(args, strict: @switches)
    root = File.cwd!()
    assets_dir = Path.join(root, "assets")

    case tessera_core_relpath(root) do
      {:ok, relpath} ->
        additions = Installer.additions(relpath, dep_js_entries())

        case Installer.merge_into_assets(assets_dir, additions) do
          :written ->
            Mix.shell().info("tessera: merged tessera deps into #{assets_dir}/package.json")

          :unchanged ->
            Mix.shell().info("tessera: #{assets_dir}/package.json already up to date")

          {:error, reason} ->
            Mix.raise("tessera.install: could not write package.json: #{inspect(reason)}")
        end

        maybe_npm_install(assets_dir, opts)

      {:error, msg} ->
        Mix.raise("tessera.install: " <> msg)
    end
  end

  defp tessera_core_relpath(root) do
    case Installer.core_js_dir(Mix.Project.deps_paths(), Mix.Project.deps_path()) do
      {:ok, core_js} ->
        # A REAL relative path even when the dep lives OUTSIDE the app tree —
        # Path.relative_to/2 silently falls back to the host-absolute path
        # there, which embeds a non-relocatable `file:` URL into
        # assets/package.json. No relative path (different volume) fails
        # loudly instead.
        case Installer.relative_path(assets_dir(root), core_js) do
          {:ok, relpath} -> {:ok, relpath}
          {:error, msg} -> {:error, msg}
        end

      :error ->
        core_js = Path.join([Mix.Project.deps_path(), "noizu_tessera", "priv", "js"])

        {:error,
         "#{core_js} not found — is noizu_tessera in this app's deps (direct or " <>
           "transitive)? Run `mix deps.get` first"}
    end
  end

  defp dep_js_entries do
    assets = assets_dir(File.cwd!())
    Installer.dep_js_entries(Mix.Project.deps_paths(), assets, Mix.Project.config()[:app])
  end

  defp assets_dir(root), do: Path.join(root, "assets")

  defp maybe_npm_install(_assets_dir, %{no_npm: true}) do
    Mix.shell().info("tessera: --no-npm given, skipping npm install")
  end

  defp maybe_npm_install(assets_dir, _opts) do
    # Friendly failure when npm is absent (bare elixir docker images ship no
    # node) instead of a raw :enoent ErlangError from System.cmd.
    case Installer.find_npm() do
      {:ok, _path} ->
        Mix.shell().info("tessera: running npm install in #{assets_dir} ...")

        case Installer.npm_install(assets_dir) do
          {:ok, _output} ->
            Mix.shell().info("tessera: npm install done")

          {:error, code, output} ->
            Mix.shell().error("tessera: npm install failed (exit #{code}):")
            Mix.shell().error(output)
        end

      {:error, guidance} ->
        Mix.raise("tessera.install: " <> guidance)
    end
  end
end
