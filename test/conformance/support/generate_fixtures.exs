# Conformance fixture generator (brief 4b case-fill).
#
# Compiles the DSL fixture components in test/support/conformance/*.ex into
# the Tier-1 WTR fixture directory js/test/fixtures/conformance/, so the
# conformance lane (`cd js && npm run test:fast`) runs against REAL generated
# Lit elements without an Elixir compile step at test time.
#
# The generated files are committed (reviewed artifacts, like the goldens):
# the element module's `@noizu/tessera-core` import is rewritten to a relative
# path into priv/js/src (js/ has no @noizu/tessera-core dependency — the core
# tests import the source directly), and the contract module is renamed
# `<snake>.contract.mjs` (the repo gitignores `*.contract.generated.mjs`).
#
# Regenerate after a DSL/codegen change, then REVIEW the diff:
#
#     MIX_ENV=test mix run test/conformance/support/generate_fixtures.exs
#
# Verify the committed fixtures are current (CI-style, no write):
#
#     MIX_ENV=test mix run test/conformance/support/generate_fixtures.exs -- --check

alias Noizu.Tessera.Codegen
alias Noizu.Tessera.Component.LitCodegen

fixtures = [
  Tessera.TestFixtures.Conformance.State,
  Tessera.TestFixtures.Conformance.Template,
  Tessera.TestFixtures.Conformance.Styles,
  Tessera.TestFixtures.Conformance.Slots,
  Tessera.TestFixtures.Conformance.Directives,
  Tessera.TestFixtures.Conformance.Pipeline
]

out_dir = Path.expand("js/test/fixtures/conformance", File.cwd!())
# Relative path from js/test/fixtures/conformance/ back to the repo root.
core_rel = "../../../../priv/js/src/index.mjs"
check? = "--check" in System.argv()

File.mkdir_p!(out_dir)

artifacts =
  for mod <- fixtures do
    unless Code.ensure_loaded?(mod) do
      Mix.raise(
        "generate_fixtures: #{inspect(mod)} is not compiled — fixtures live in " <>
          "test/support (test env only). Run: MIX_ENV=test mix run " <>
          "test/conformance/support/generate_fixtures.exs"
      )
    end

    spec = mod.__tessera_spec__()
    snake = Codegen.snake_tag(spec)

    element =
      spec
      |> LitCodegen.element_module()
      |> String.replace(~s|from "@noizu/tessera-core"|, ~s|from "#{core_rel}"|)
      |> String.replace(
        ~s|from "./#{snake}.contract.generated.mjs"|,
        ~s|from "./#{snake}.contract.mjs"|
      )

    contract = Codegen.contract_module(spec)

    %{
      element_path: Path.join(out_dir, "#{spec.tag}.element.generated.mjs"),
      element: element,
      contract_path: Path.join(out_dir, "#{snake}.contract.mjs"),
      contract: contract
    }
  end

if check? do
  stale =
    for a <- artifacts,
        expected <- [{a.element_path, a.element}, {a.contract_path, a.contract}],
        {path, content} = expected,
        not File.exists?(path) or File.read!(path) != content do
      path
    end

  if stale == [] do
    Mix.shell().info("generate_fixtures: #{length(artifacts)} fixtures current.")
  else
    Mix.raise(
      "generate_fixtures: STALE committed fixtures (regenerate + review):\n  " <>
        Enum.join(stale, "\n  ")
    )
  end
else
  for a <- artifacts do
    File.write!(a.element_path, a.element)
    File.write!(a.contract_path, a.contract)
  end

  Mix.shell().info(
    "generate_fixtures: wrote #{length(artifacts)} fixtures to js/test/fixtures/conformance/ — " <>
      "REVIEW the diff before committing."
  )
end
