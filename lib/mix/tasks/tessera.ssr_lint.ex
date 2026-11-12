defmodule Mix.Tasks.Tessera.SsrLint do
  @shortdoc "Lint DSD-exported (SSR) components for the init/3 author contract"

  @moduledoc """
  Pre-render lint of the SSR author contract (TESSER-028).

  Probe-renders each listed component server-side via
  `Noizu.Tessera.Hologram.Render.lint_component/2` and reports violations of
  the "server `init/3` computes what the template reads" contract before any
  real render (or user) hits them:

      mix tessera.ssr_lint MyAppWeb.Components.CounterEl MyAppWeb.HoloKit.Picker
      mix tessera.ssr_lint   # no args: uses app env

  The DSD-exported manifest comes from the host app's config:

      config :tessera, :ssr_components, [
        MyAppWeb.Components.CounterEl,
        MyAppWeb.HoloKit.Picker
      ]

  Requires the `:hologram` dependency (the probe is a real server render) and
  runs after `mix compile` (it renders compiled modules).

  Per component, one line:

      ok         <Module>
      violation  <Module> — missing server init/3 for state key :count
      error      <Module> — <exception>

  Exits non-zero (Mix.raise) when any component is a violation or an error,
  so CI can gate on it. Run it in CI as `mix compile && mix tessera.ssr_lint`.
  """

  use Mix.Task

  alias Noizu.Tessera.Hologram.Render

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")

    components = components_from(args)

    if components == [] do
      Mix.shell().info(
        "tessera.ssr_lint: no components given and config :tessera, :ssr_components is empty — nothing to lint"
      )

      :ok
    else
      results = Enum.map(components, &lint_one/1)
      failures = Enum.count(results, &(!match?({:ok, _}, &1)))

      if failures > 0 do
        Mix.raise(
          "tessera.ssr_lint: #{failures} of #{length(results)} component(s) failed the SSR author contract"
        )
      end

      Mix.shell().info("tessera.ssr_lint: #{length(results)} component(s) ok")
      :ok
    end
  end

  defp components_from(argv) do
    argv_modules = Enum.map(argv, &module_from_name!/1)
    env_modules = Application.get_env(:tessera, :ssr_components, [])

    env_modules
    |> Enum.concat(argv_modules)
    |> Enum.uniq()
  end

  defp module_from_name!(name) when is_binary(name) do
    mod =
      try do
        String.to_existing_atom("Elixir." <> name)
      rescue
        ArgumentError ->
          Mix.raise("tessera.ssr_lint: unknown or unloaded component module #{inspect(name)}")
      end

    unless is_atom(mod) and Code.ensure_loaded?(mod) do
      Mix.raise("tessera.ssr_lint: unknown or unloaded component module #{inspect(name)}")
    end

    mod
  end

  defp lint_one(module) do
    case Render.lint_component(module) do
      :ok ->
        Mix.shell().info("ok         #{inspect(module)}")
        {:ok, module}

      {:violation, key} ->
        Mix.shell().error(
          "violation  #{inspect(module)} — missing server init/3 for state key #{inspect(key)}"
        )

        {:violation, module, key}

      {:error, exception} ->
        Mix.shell().error(
          "error      #{inspect(module)} — #{Exception.format(:error, exception)}"
        )

        {:error, module, exception}
    end
  end
end
