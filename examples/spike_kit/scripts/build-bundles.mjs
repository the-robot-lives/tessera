// SPIKE (spike/elixir-to-lit) — esbuild packaging for the SpikeKit generated
// elements. Produces, per component (spike-counter shown; same for
// spike-toggle-chip):
//
//   dist/<tag>.esm.js            ESM, lit + @noizu/tessera-core INLINED
//                                (self-contained single file; import it from
//                                any host — auto-registers on import)
//   dist/<tag>.umd.js            UMD, same inlining; merges the component's
//                                exports into window.Tessera.<Component>
//                                (plain <script> tag; auto-registers on load)
//   dist/<tag>.runtime.esm.js    ESM VARIANT with `lit` + `@noizu/tessera-core`
//                                left external, resolved through an import map
//                                to the shared dist/tessera-runtime.esm.js —
//                                N components amortize one runtime copy
//   dist/tessera-runtime.esm.js  the shared runtime (re-exports lit +
//                                @noizu/tessera-core; one instance, so
//                                defineOnce's registry is a true singleton)
//
// Also copies the UMD + ESM files into demo/plain_html/dist/ so the plain
// demo's static server (which serves only its own dir) can ship them, and
// prints the raw + gzip size table that goes into
// docs/notes/spike-elixir-to-lit.md.
import { build } from "esbuild";
import { gzipSync } from "node:zlib";
import { copyFile, mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const dist = join(root, "dist");
const plainDist = join(root, "../../demo/plain_html/dist");

// component exports as window.Tessera.<Component>
const components = [
  { tag: "spike-counter", exportName: "Counter", moduleExport: "SpikeCounter" },
  { tag: "spike-toggle-chip", exportName: "ToggleChip", moduleExport: "SpikeToggleChip" },
  // directive-using surface (brief 1d step 4): its runtime bundle must
  // externalize `lit/directives/*.js` to the shared runtime instead of
  // inlining a second copy — proven by test/components/runtime_variant_test.mjs
  { tag: "spike-directive-demo", exportName: "DirectiveDemo", moduleExport: "SpikeDirectiveDemo" },
];

const common = { bundle: true, minify: true, target: ["es2020"], legalComments: "none" };

await mkdir(dist, { recursive: true });
await mkdir(plainDist, { recursive: true });

// shared runtime (import-map target for the .runtime.esm.js variants)
await build({
  ...common,
  entryPoints: [join(root, "scripts/entries/tessera-runtime.mjs")],
  // format is load-bearing: the default (iife) would emit no exports and the
  // import-map variant would fail with "does not provide an export named 'html'"
  format: "esm",
  outfile: join(dist, "tessera-runtime.esm.js"),
});

const outputs = [];

for (const { tag, exportName, moduleExport } of components) {
  const element = join(root, `lib/spike_kit/${tag}.element.generated.mjs`);

  // (1) ESM, everything inlined
  const esm = join(dist, `${tag}.esm.js`);
  await build({ ...common, entryPoints: [element], format: "esm", outfile: esm });

  // (2) UMD — esbuild has no UMD format, so build an IIFE (exports assigned
  // to a factory-local var) and wrap it in the standard UMD shell here. The
  // browser-global branch merges the component's exports into the shared
  // window.Tessera namespace (window.Tessera.<Component>); CJS and AMD
  // branches receive the same exports object untouched.
  const tmpIife = join(dist, `.tmp-${tag}.iife.js`);
  await build({
    ...common,
    entryPoints: [element],
    format: "iife",
    globalName: "__tsrExport",
    outfile: tmpIife,
  });
  const iife = await readFile(tmpIife, "utf8");
  const umd = join(dist, `${tag}.umd.js`);
  const umdText = [
    "(function (global, factory) {",
    '  if (typeof module !== "undefined" && module.exports) {',
    '    var mod = { exports: {} }; factory(mod.exports); module.exports = mod.exports;',
    "  } else if (typeof define === \"function\" && define.amd) {",
    '    define(["exports"], factory);',
    "  } else {",
    "    var ns = (global.Tessera = global.Tessera || {}); factory(ns);",
    "  }",
    '})(typeof self !== "undefined" ? self : this, function (exports) {',
    iife,
    "  Object.assign(exports, __tsrExport);",
    `  exports.${exportName} = __tsrExport.${moduleExport};`,
    "});",
    "",
  ].join("\n");
  await writeFile(umd, umdText);
  await rm(tmpIife);

  // (3) runtime variant — lit + core external (import map supplies them).
  // `lit/*` is load-bearing (brief 1d step 4): a bare `lit` external does NOT
  // match the `lit/directives/*.js` subpaths generated elements import, so
  // esbuild would silently inline a SECOND copy of the directive code into
  // every runtime-variant bundle — defeating the shared-runtime amortization.
  const runtimeEsm = join(dist, `${tag}.runtime.esm.js`);
  await build({
    ...common,
    entryPoints: [element],
    format: "esm",
    external: ["lit", "lit/*", "@noizu/tessera-core"],
    outfile: runtimeEsm,
  });

  // ship the browser-loadable artifacts to the plain demo dir
  for (const f of [esm, umd, runtimeEsm]) {
    await copyFile(f, join(plainDist, f.split("/").pop()));
  }
  outputs.push(
    { name: `${tag}.esm.js`, file: esm, note: "ESM, lit+core inlined" },
    { name: `${tag}.umd.js`, file: umd, note: `UMD, window.Tessera.${exportName}` },
    {
      name: `${tag}.runtime.esm.js`,
      file: runtimeEsm,
      note: "ESM, shared runtime via import map",
    },
  );
}

// copy the shared runtime once, after the loop
await copyFile(join(dist, "tessera-runtime.esm.js"), join(plainDist, "tessera-runtime.esm.js"));
outputs.push({
  name: "tessera-runtime.esm.js",
  file: join(dist, "tessera-runtime.esm.js"),
  note: "shared runtime (lit + core), amortized across components",
});

// size table (raw + gzip)
const rows = [];
for (const out of outputs) {
  const bytes = (await stat(out.file)).size;
  const gz = gzipSync(await readFile(out.file)).length;
  rows.push({ ...out, bytes, gz });
}
const kb = (n) => `${(n / 1024).toFixed(1)} KiB`;
const w = Math.max(...rows.map((r) => r.name.length));
console.log("\nSpikeKit bundles (raw / gzip):");
for (const r of rows) {
  console.log(`  ${r.name.padEnd(w)}  ${kb(r.bytes).padStart(9)}  ${kb(r.gz).padStart(8)}  — ${r.note}`);
}
const pair = rows.find((r) => r.name === "spike-counter.esm.js");
const pairRt = rows.find((r) => r.name === "spike-counter.runtime.esm.js");
const rt = rows.find((r) => r.name === "tessera-runtime.esm.js");
console.log(
  `\n  variant pair (spike-counter): inlined ${kb(pair.gz)} gz vs runtime-variant ${kb(pairRt.gz)} gz + shared runtime ${kb(rt.gz)} gz (→ N components amortize the runtime)`,
);
