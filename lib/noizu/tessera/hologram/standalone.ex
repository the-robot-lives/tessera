defmodule Noizu.Tessera.Hologram.Standalone do
  @moduledoc """
  Tier 2 spike: compiles ORDINARY Hologram components into standalone,
  host-agnostic bundles by driving Hologram's own compiler pipeline.

  Approach (item 1 of the spike brief — "synthetic stub page"):

  * a throwaway stub page + layout per target component is generated,
    compiled to BEAM in a scratch dir and loaded into the VM,
  * the exact pipeline of `Mix.Tasks.Compile.Hologram` is replayed against
    ONLY those stub pages — `build_ir_plt` → `build_call_graph` →
    `list_async_mfas` → clone + `remove_manually_ported_mfas` →
    `list_runtime_mfas` → `remove_runtime_mfas!` → `build_page_js` /
    `build_runtime_js`,
  * the emitted page JS gets string surgery: the
    `globalThis.Hologram.pageReachableFunctionDefs = (deps) => {...}`
    assignment becomes a plain `const tesseraDefs = (deps) => {...}` +
    `export default`, and the `pageScriptLoaded` dispatch tail is stripped —
    so a component bundle NEVER touches the page-global
    `globalThis.Hologram` object a host page may already own.

  ## Internals dependence (documented deliberately)

  Everything used is PUBLIC API of the 0.10.1 hex package
  (`Hologram.Compiler.*`, `Hologram.Compiler.CallGraph.*`), but it is
  pre-1.0 public API, and the string surgery anchors on the exact emitted
  statements:

  * `import PerformanceTimer from ...` / `const startTime = ...` header lines
  * `globalThis.Hologram.pageReachableFunctionDefs = (deps) => {` (page entry)
  * `globalThis.Hologram.pageScriptLoaded = true;` (page entry tail)
  * `document.addEventListener("hologram:pageScriptLoaded", ...)` (runtime entry tail)
  * `static #defineManuallyPortedFunctions() {` (body extracted verbatim
    from `assets/js/hologram.mjs` so the ~33 manual registrations stay in
    sync with upstream instead of being duplicated here)

  Any of those drifting makes the compile fail loudly (anchored splits
  raise) rather than silently producing broken bundles.
  """

  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph

  # Scratch OTP app the stub pages + third-party modules are loaded under so
  # `Hologram.Reflection.list_elixir_modules/0` (which enumerates LOADED
  # APPLICATIONS only) sees them during the pipeline.
  # NOTE: module attributes are order-dependent — keep this above first use.
  @scratch_app :tessera_holo_stubs

  @stub_prefix TesseraHolo.Stubs

  @page_defs_anchor "globalThis.Hologram.pageReachableFunctionDefs = (deps) => {"
  @page_tail_anchor "globalThis.Hologram.pageScriptLoaded = true;"
  @runtime_tail_anchor "document.addEventListener(\"hologram:pageScriptLoaded\""
  @manual_fn_anchor "static #defineManuallyPortedFunctions() {"

  # -------------------------------------------------------------------------
  # Public entry point
  # -------------------------------------------------------------------------

  @doc """
  Compiles the tessera runtime + one bundle set per given component module.

  Options:

  * `:out` — output dir (default: `priv/static/tessera-holo` under cwd)

  Writes into `out`:

  * `tessera-runtime.esm.js` / `tessera-runtime.umd.js` — the shared
    runtime (Hologram client runtime exactly once + tessera shim)
  * `<base>.esm.js` / `<base>.umd.js` per component — only that
    component's compiled Elixir + a runtime-free registrar
  * `<base>.standalone.esm.js` — runtime + component in one file
  * `manifest.json` — hologram version, prop contracts, file sizes
  """
  @spec compile(list(module() | String.t()), keyword()) :: map()
  def compile(components, opts \\ []) when is_list(components) do
    out_dir = Path.expand(opts[:out] || "priv/static/tessera-holo")
    build_dir = Path.join(out_dir, ".build")
    ebin_dir = Path.join(build_dir, "ebin")
    entry_dir = Path.join(build_dir, "entries")
    File.rm_rf!(build_dir)
    File.mkdir_p!(ebin_dir)
    File.mkdir_p!(entry_dir)

    paths = hologram_paths()
    shim_dir = priv_src_dir()

    IO.puts("[tessera-holo] components: #{inspect(components)}")
    IO.puts("[tessera-holo] hologram assets: #{short(paths.assets_dir)}")
    IO.puts("[tessera-holo] out: #{short(out_dir)}")

    # Third-party extension modules (e.g. `use HoloKit.Components.EditableList,
    # tag: "..."` consumers) compile FIRST so their module names resolve and
    # their injected __props__/0 is readable during stub generation.
    extra_sources = opts[:extra_sources] || []

    if extra_sources != [] do
      compile_extra_sources!(extra_sources, ebin_dir)
    end

    components = components |> List.wrap() |> Enum.map(&expand_module/1)

    if components == [] do
      raise ArgumentError, message: "no component modules given"
    end

    stubs = compile_stubs!(components, ebin_dir)

    {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    results =
      try do
        run_pipeline(components, stubs, %{
          paths: paths,
          shim_dir: shim_dir,
          out_dir: out_dir,
          entry_dir: entry_dir,
          supervisor: sup
        })
      after
        DynamicSupervisor.stop(sup)
      end

    # Keep the scratch dir when debugging (TESSERA_KEEP_BUILD=1).
    unless System.get_env("TESSERA_KEEP_BUILD") do
      File.rm_rf!(build_dir)
    end

    purge_stubs(stubs)

    results
  end

  # -------------------------------------------------------------------------
  # Pipeline
  # -------------------------------------------------------------------------

  defp run_pipeline(components, stubs, ctx) do
    paths = ctx.paths
    sup = ctx.supervisor

    # --- Hologram compiler pipeline, mirroring Mix.Tasks.Compile.Hologram ---
    ir_plt = Compiler.build_ir_plt(supervisor: sup)
    call_graph = Compiler.build_call_graph(ir_plt)

    # Must be computed before remove_manually_ported_mfas/1 strips the
    # Task.await/1 vertex (verbatim upstream ordering).
    async_mfas = CallGraph.list_async_mfas(call_graph)

    cg_runtime =
      call_graph
      |> CallGraph.clone(supervisor: sup)
      |> CallGraph.remove_manually_ported_mfas()

    page_modules = Enum.map(stubs.pages, & &1.module)
    Compiler.validate_page_modules(page_modules)

    runtime_mfas = CallGraph.list_runtime_mfas(cg_runtime, page_modules)
    cg_pages = CallGraph.remove_runtime_mfas!(cg_runtime, runtime_mfas)

    graph = CallGraph.get_graph(cg_pages)

    # Upstream passes ALL pages + ALL components here; list_page_mfas looks
    # up every templatable it extracts from the page's reachable set (the
    # layout included), so the map must at least cover the stub layout too.
    templatables = Enum.uniq(page_modules ++ [stubs.layout] ++ components)

    server_callback_analysis =
      CallGraph.server_callback_analysis_by_templatable(graph, templatables)

    # --- runtime entry    # --- runtime entry -------------------------------------------------------
    manual_imports = manually_ported_imports(paths)
    manual_body = manually_ported_body(paths)

    runtime_entry =
      runtime_mfas
      |> Compiler.build_runtime_js(ir_plt, async_mfas, paths.js_dir)
      |> build_runtime_entry(manual_imports, manual_body, ctx)

    IO.puts("[tessera-holo] runtime entry built")

    # --- per-component entries ----------------------------------------------
    component_entries =
      Enum.map(Enum.zip(components, stubs.pages), fn {component, page} ->
        page_js =
          Compiler.build_page_js(
            page.module,
            cg_pages,
            ir_plt,
            async_mfas,
            server_callback_analysis,
            paths.js_dir
          )

        {defs_entry, manifest} = build_component_entry(component, page_js, ctx)

        IO.puts("[tessera-holo] #{component} entry built (#{page.base})")

        # TESSERA_DEBUG_DUMP=1 keeps .build/ and additionally writes the raw
        # page JS next to the surgically-edited defs entry for inspection.
        if System.get_env("TESSERA_DEBUG_DUMP") do
          Path.join(ctx.entry_dir, "#{page.base}.page.js") |> File.write!(page_js)
        end

        %{component: component, base: page.base, defs_entry: defs_entry, manifest: manifest}
      end)

    # --- esbuild -------------------------------------------------------------
    esbuild!(paths, [
      runtime_entry,
      "--bundle",
      "--minify",
      "--target=es2021",
      "--format=esm",
      "--outfile=#{Path.join(ctx.out_dir, "tessera-runtime.esm.js")}"
    ])

    runtime_iife_tmp = Path.join(ctx.entry_dir, "runtime.iife.js")

    esbuild!(paths, [
      runtime_entry,
      "--bundle",
      "--minify",
      "--target=es2021",
      "--format=iife",
      "--global-name=TesseraHoloBundle",
      "--outfile=#{runtime_iife_tmp}"
    ])

    File.write!(
      Path.join(ctx.out_dir, "tessera-runtime.umd.js"),
      umd_wrap(File.read!(runtime_iife_tmp), "TesseraHoloBundle")
    )

    for entry <- component_entries do
      esm_path = Path.join(ctx.out_dir, "#{entry.base}.esm.js")
      iife_tmp = Path.join(ctx.entry_dir, "#{entry.base}.iife.js")

      esbuild!(paths, [
        entry.defs_entry,
        "--bundle",
        "--minify",
        "--target=es2021",
        "--format=esm",
        "--outfile=#{esm_path}"
      ])

      esbuild!(paths, [
        entry.defs_entry,
        "--bundle",
        "--minify",
        "--target=es2021",
        "--format=iife",
        "--global-name=TesseraHoloComponentBundle",
        "--outfile=#{iife_tmp}"
      ])

      File.write!(
        Path.join(ctx.out_dir, "#{entry.base}.umd.js"),
        umd_wrap(File.read!(iife_tmp), "TesseraHoloComponentBundle")
      )

      # self-contained: runtime + this component in one ESM file
      standalone_entry = Path.join(ctx.entry_dir, "#{entry.base}.standalone.entry.mjs")

      File.write!(standalone_entry, """
      import "#{runtime_entry}";
      import "#{entry.defs_entry}";
      import * as TesseraHolo from "#{runtime_entry}";

      export const ensureRuntime = TesseraHolo.ensureRuntime;
      export const mountComponent = TesseraHolo.mountComponent;
      export const defineElement = TesseraHolo.defineElement;
      export const setBus = TesseraHolo.setBus;
      export default TesseraHolo;
      """)

      esbuild!(paths, [
        standalone_entry,
        "--bundle",
        "--minify",
        "--target=es2021",
        "--format=esm",
        "--outfile=#{Path.join(ctx.out_dir, "#{entry.base}.standalone.esm.js")}"
      ])
    end

    write_manifest(component_entries, ctx)
  end

  # -------------------------------------------------------------------------
  # Entry-file surgery
  # -------------------------------------------------------------------------

  # Turns build_page_js output into a module that default-exports the defs
  # callback WITHOUT touching globalThis.Hologram (coexistence requirement).
  defp build_component_entry(component, page_js, ctx) do
    {header, rest} = split_once!(page_js, @page_defs_anchor)
    {body, _tail} = split_once!(rest, @page_tail_anchor)

    defs_src =
      header
      |> drop_performance_import()
      |> drop_start_time()
      |> Kernel.<>("const tesseraDefs = (deps) => {")
      |> Kernel.<>(String.trim_trailing(body))
      |> Kernel.<>("\n\nexport default tesseraDefs;\n")

    base = component_base(component)
    defs_path = Path.join(ctx.entry_dir, "#{base}_defs.mjs")
    File.write!(defs_path, defs_src)

    manifest = component_manifest(component)

    bundle_entry = Path.join(ctx.entry_dir, "#{base}.entry.mjs")

    File.write!(bundle_entry, """
    import defs from "#{defs_path}";
    import { registerComponent } from "#{Path.join(ctx.shim_dir, "register.mjs")}";

    registerComponent("#{component}", defs, #{Jason.encode!(manifest)});

    export default defs;
    """)

    {bundle_entry, manifest}
  end

  defp build_runtime_entry(runtime_js, manual_imports, manual_body, ctx) do
    {body, _tail} = split_once!(runtime_js, @runtime_tail_anchor)
    paths = ctx.paths

    extra_imports =
      Enum.map_join(
        ["renderer", "component_registry", "vdom", "client", "js_interop"],
        "\n",
        fn name ->
          "import #{js_alias(name)} from \"#{Path.join(paths.js_dir, "#{name}.mjs")}\";"
        end
      )

    entry =
      body
      |> String.trim_trailing()
      |> Kernel.<>("\n")
      |> Kernel.<>(manual_imports)
      |> Kernel.<>("\n\n")
      |> Kernel.<>("""
      function tesseraDefineManuallyPortedFunctions() {
      #{manual_body}
      }

      #{extra_imports}

      import { initRuntime } from "#{Path.join(ctx.shim_dir, "tessera_holo.mjs")}";
      import * as TesseraHolo from "#{Path.join(ctx.shim_dir, "index.mjs")}";

      initRuntime({
        Hologram: Hologram,
        Interpreter: Interpreter,
        Type: Type,
        Utils: Utils,
        Renderer: Renderer,
        ComponentRegistry: ComponentRegistry,
        Vdom: Vdom,
        Client: Client,
        JsInterop: JsInterop,
        defineManuallyPortedFunctions: tesseraDefineManuallyPortedFunctions,
        deps: {
          Bitstring: Bitstring,
          ERTS: ERTS,
          HologramBoxedError: HologramBoxedError,
          HologramInterpreterError: HologramInterpreterError,
          Interpreter: Interpreter,
          MemoryStorage: MemoryStorage,
          Type: Type,
          Utils: Utils,
        },
      });

      export const ensureRuntime = TesseraHolo.ensureRuntime;
      export const mountComponent = TesseraHolo.mountComponent;
      export const defineElement = TesseraHolo.defineElement;
      export const setBus = TesseraHolo.setBus;
      export default TesseraHolo;
      """)

    entry_path = Path.join(ctx.entry_dir, "runtime.entry.mjs")
    File.write!(entry_path, entry)
    entry_path
  end

  defp js_alias("renderer"), do: "Renderer"
  defp js_alias("component_registry"), do: "ComponentRegistry"
  defp js_alias("vdom"), do: "Vdom"
  defp js_alias("client"), do: "Client"
  defp js_alias("js_interop"), do: "JsInterop"

  defp split_once!(src, anchor) do
    case :binary.split(src, anchor) do
      [head, tail] ->
        {head, tail}

      [_] ->
        raise RuntimeError,
          message:
            "tessera standalone compiler: expected anchor not found in Hologram " <>
              "compiler output: #{inspect(anchor)} (Hologram version drift — see moduledoc)"
    end
  end

  defp drop_performance_import(header) do
    # Import path is absolute; match the line generically instead of
    # hardcoding it.
    Regex.replace(~r{^import PerformanceTimer from "[^"]+";\n}m, header, "")
  end

  defp drop_start_time(header) do
    # No-op replace by design: if the exact line spacing drifted, an unused
    # const minifies away harmlessly.
    String.replace(header, "const startTime = performance.now();\n\n", "")
  end

  # Extracts the body of Hologram.#defineManuallyPortedFunctions verbatim
  # (brace-balanced) so the shim registers the same ~33 manually ported
  # functions the upstream runtime would.
  defp manually_ported_body(paths) do
    source = File.read!(Path.join(paths.js_dir, "hologram.mjs"))
    [_, rest] = :binary.split(source, @manual_fn_anchor)
    balance_braces(rest, 1, "")
  end

  defp balance_braces(<<c::utf8, rest::binary>>, depth, acc) do
    new_depth =
      case c do
        ?{ -> depth + 1
        ?} -> depth - 1
        _ -> depth
      end

    if new_depth == 0 do
      String.trim(acc)
    else
      balance_braces(rest, new_depth, acc <> <<c::utf8>>)
    end
  end

  defp manually_ported_imports(paths) do
    Path.join(paths.js_dir, "hologram.mjs")
    |> File.read!()
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "import ManuallyPorted"))
    |> Enum.map_join("\n", fn line ->
      String.replace(line, ~s(from "./), ~s(from ") <> paths.js_dir <> "/")
    end)
  end

  # -------------------------------------------------------------------------
  # Stub pages
  # -------------------------------------------------------------------------

  # The scratch ebin is loaded as a REAL OTP app (`:tessera_holo_stubs`) so
  # `Hologram.Reflection.list_elixir_modules/0` — which enumerates loaded
  # apps only — sees the stub pages and any third-party extension modules.
  # Without this the IR PLT skips them and the emitted defs are empty.
  defp compile_extra_sources!([], _ebin_dir), do: :ok

  defp compile_extra_sources!(extra_sources, ebin_dir) do
    IO.puts("[tessera-holo] compiling #{length(extra_sources)} third-party extension source(s)")

    # NOTE: ParallelCompiler.compile/2 NEVER writes BEAM files (its :dest
    # option only annotates in-memory loads) — compile_to_path/3 is the one
    # that writes beams, which the scratch app load below depends on.
    case Kernel.ParallelCompiler.compile_to_path(extra_sources, ebin_dir,
           return_diagnostics: true
         ) do
      {:ok, modules, diagnostics} ->
        report_diagnostics(diagnostics)

        modules
        |> Enum.map_join(", ", &Atom.to_string/1)
        |> then(&IO.puts("[tessera-holo] third-party modules: #{&1}"))

      {:error, errors, diagnostics} ->
        report_diagnostics(diagnostics)

        formatted =
          Enum.map_join(errors, "\n", fn
            {file, line, msg} -> "  #{file}:#{line}: #{msg}"
            %{file: file, position: pos, message: msg} -> "  #{file}:#{pos}: #{msg}"
          end)

        raise RuntimeError, message: "tessera third-party component compilation failed:\n#{formatted}"
    end

    # Load the scratch app NOW so the freshly compiled modules exist when
    # `expand_module/1` resolves their names and `__props__/0` is readable.
    load_scratch_app!(ebin_dir)
  end

  defp compile_stubs!(components, ebin_dir) do
    layout_module = stub_module_name("Layout")

    layout_src = """
    defmodule #{layout_module} do
      use Hologram.Component

      def template do
        sigil_HOLO("<slot />", [])
      end
    end
    """

    pages =
      for component <- components do
        base = component_base(component)
        module = stub_module_name(Macro.camelize(base) <> "Page")
        tag = component |> Atom.to_string() |> String.split(".") |> List.last()
        tag_args = stub_tag_args(component)

        src = """
        defmodule #{module} do
          use Hologram.Page

          alias #{component}
          alias #{layout_module}

          route "/tessera_holo_stub/#{base}"
          layout #{layout_module}

          def template do
            sigil_HOLO("<#{tag} cid={~s(tssr)} #{tag_args} />", [])
          end
        end
        """

        %{module: module, base: base, component: component, src: src}
      end

    layout_path = Path.join(ebin_dir, "stub_layout.ex")
    File.write!(layout_path, layout_src)

    page_paths =
      for page <- pages do
        p = Path.join(ebin_dir, "#{page.base}_stub_page.ex")
        File.write!(p, page.src)
        p
      end

    case Kernel.ParallelCompiler.compile_to_path([layout_path | page_paths], ebin_dir,
           return_diagnostics: true
         ) do
      {:ok, _modules, diagnostics} ->
        report_diagnostics(diagnostics)

      {:error, errors, diagnostics} ->
        report_diagnostics(diagnostics)

        formatted =
          Enum.map_join(errors, "\n", fn
            {file, line, msg} -> "  #{file}:#{line}: #{msg}"
            %{file: file, position: pos, message: msg} -> "  #{file}:#{pos}: #{msg}"
          end)

        raise RuntimeError, message: "tessera stub compilation failed:\n#{formatted}"
    end

    load_scratch_app!(ebin_dir)
    %{layout: layout_module, pages: pages}
  end

  defp load_scratch_app!(ebin_dir) do
    # Unload a previous scratch app from an earlier run in the same VM.
    case Application.unload(@scratch_app) do
      :ok -> :ok
      {:error, {:not_loaded, @scratch_app}} -> :ok
    end

    beams =
      ebin_dir
      |> Path.join("*.beam")
      |> Path.wildcard()
      |> Enum.map(&(&1 |> Path.basename() |> Path.rootname() |> String.to_atom()))

    spec = [
      description: "tessera standalone compiler scratch app",
      vsn: "0",
      modules: beams,
      applications: [:elixir]
    ]

    :ok = :application.load({:application, @scratch_app, spec})
    Code.append_path(ebin_dir)

    # Re-load from disk so this VM run sees exactly what the scratch app
    # contains (compile_to_path already loaded the modules in memory; this
    # makes reruns deterministic).
    Enum.each(beams, fn m ->
      :code.purge(m)

      case Code.ensure_loaded(m) do
        {:module, ^m} -> :ok
        {:error, reason} -> raise "cannot load scratch module #{m}: #{inspect(reason)}"
      end
    end)

  end

  defp stub_module_name(suffix) do
    Module.concat(@stub_prefix, suffix)
  end

  defp report_diagnostics(diagnostics) do
    Enum.each(diagnostics, fn
      %{severity: :warning, file: file, position: pos, message: msg} ->
        IO.warn("#{file}:#{pos}: #{msg}")

      _ ->
        :ok
    end)
  end

  # Dummy prop args for the stub template: enough to make prop evaluation,
  # defaults and __props__/0 reachable. String values use ~s(...) so the
  # generated sigil_HOLO(...) argument needs no quote escaping.
  defp stub_tag_args(component) do
    Code.ensure_loaded!(component)

    props =
      if function_exported?(component, :__props__, 0) do
        component.__props__()
      else
        []
      end

    args =
      for {name, type, _opts} <- props,
          dummy = dummy_value(type),
          dummy != nil do
        "#{name}={#{dummy}}"
      end

    Enum.join(args, " ")
  end

  defp dummy_value(:string), do: "~s(t)"
  defp dummy_value(:atom), do: ":t"
  defp dummy_value(:integer), do: "1"
  defp dummy_value(:float), do: "1.0"
  defp dummy_value(:boolean), do: "true"
  # lists/maps arrive via tsr-props JSON at runtime; stub renders empty
  defp dummy_value(:list), do: "[]"
  defp dummy_value(:map), do: "%{}"
  defp dummy_value(_), do: nil

  defp purge_stubs(stubs) do
    case Application.unload(@scratch_app) do
      :ok -> :ok
      {:error, {:not_loaded, @scratch_app}} -> :ok
    end

    ([stubs.layout] ++ Enum.map(stubs.pages, & &1.module))
    |> Enum.each(fn module ->
      if :code.which(module) != :non_existing do
        :code.purge(module)
        :code.delete(module)
      end
    end)
  end

  # -------------------------------------------------------------------------
  # Manifest / naming
  # -------------------------------------------------------------------------

  defp component_manifest(component) do
    Code.ensure_loaded!(component)

    props =
      if function_exported?(component, :__props__, 0) do
        Enum.map(component.__props__(), fn {name, type, opts} ->
          %{
            "name" => Atom.to_string(name),
            "type" => Atom.to_string(type),
            "default" => Keyword.get(opts, :default)
          }
        end)
      else
        []
      end

    %{
      "module" => Atom.to_string(component),
      "element" => element_name_for(component),
      "props" => props
    }
  end

  defp element_name_for(component) do
    Code.ensure_loaded!(component)

    if function_exported?(component, :__tessera_tag__, 0) do
      component.__tessera_tag__()
    else
      "tsr-holo-" <> String.replace(component_base(component), "_", "-")
    end
  end

  defp component_base(component) do
    component
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> Macro.underscore()
  end

  defp expand_module(name) when is_binary(name) do
    String.to_existing_atom("Elixir." <> name)
  rescue
    ArgumentError ->
      raise ArgumentError,
        message: "unknown component module #{name} — is its package a dep of this app?"
  end

  defp expand_module(module) when is_atom(module), do: module

  # -------------------------------------------------------------------------
  # Paths / esbuild / manifest writing
  # -------------------------------------------------------------------------

  defp hologram_paths do
    # Upstream convention (Mix.Tasks.Compile.Hologram): the dep's assets
    # live at <project>/deps/hologram/assets. :code.lib_dir(:hologram)
    # resolves to the _build copy which has no assets.
    assets_dir = Path.join([File.cwd!(), "deps", "hologram", "assets"])

    unless File.dir?(Path.join(assets_dir, "js")) do
      raise RuntimeError,
        message: "hologram assets not found at #{assets_dir} (run from the host app)"
    end

    node_modules = Path.join(assets_dir, "node_modules")

    %{
      lib_dir: Path.dirname(assets_dir),
      assets_dir: assets_dir,
      js_dir: Path.join(assets_dir, "js"),
      node_modules: node_modules,
      esbuild: Path.join([node_modules, ".bin", "esbuild"])
    }
  end

  defp priv_src_dir do
    :code.priv_dir(:noizu_tessera)
    |> to_string()
    |> Path.join("tessera_holo/src")
  end

  defp esbuild!(paths, args) do
    # TESSERA_NO_MINIFY=1 builds readable bundles (spike debugging: real
    # function names / line numbers in browser stack traces).
    args = if System.get_env("TESSERA_NO_MINIFY"), do: List.delete(args, "--minify"), else: args

    case System.cmd(paths.esbuild, args,
           env: [{"NODE_PATH", paths.node_modules}],
           stderr_to_stdout: true
         ) do
      {_out, 0} ->
        :ok

      {out, _status} ->
        raise RuntimeError, message: "esbuild failed:\n\n#{out}"
    end
  end

  defp umd_wrap(iife_payload, global_name) do
    """
    (function (root, factory) {
      if (typeof exports === "object" && typeof module !== "undefined") {
        module.exports = factory();
      } else if (typeof define === "function" && define.amd) {
        define([], factory);
      } else {
        root.#{global_name} = root.#{global_name} || {};
        var api = factory();
        for (var key in api) root.#{global_name}[key] = api[key];
      }
    })(typeof self !== "undefined" ? self : this, function () {
    #{iife_payload}
    return #{global_name};
    });
    """
  end

  defp write_manifest(component_entries, ctx) do
    files =
      ctx.out_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".js"))
      |> Enum.sort()
      |> Enum.map(fn file ->
        bytes = Path.join(ctx.out_dir, file) |> File.read!()
        %{"file" => file, "raw" => byte_size(bytes), "gzip" => gzip_size(bytes)}
      end)

    manifest = %{
      "hologram_version" => hologram_version(),
      "generated_at" => DateTime.to_string(DateTime.utc_now()),
      "components" =>
        Enum.map(component_entries, fn entry ->
          Map.merge(entry.manifest, %{"base" => entry.base})
        end),
      "files" => files
    }

    File.write!(Path.join(ctx.out_dir, "manifest.json"), Jason.encode!(manifest, pretty: true))

    Enum.each(files, fn f ->
      IO.puts("[tessera-holo] #{String.pad_trailing(f["file"], 46)} #{f["raw"]} B raw / #{f["gzip"]} B gzip")
    end)

    manifest
  end

  defp hologram_version do
    to_string(Application.spec(:hologram, :vsn))
  end

  defp gzip_size(bytes) do
    bytes |> :zlib.gzip() |> byte_size()
  end

  defp short(path) do
    cwd = File.cwd!() |> Path.expand()

    case path do
      ^cwd <> "/" <> rest -> "./" <> rest
      other -> other
    end
  rescue
    _ -> path
  end
end
