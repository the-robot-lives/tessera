/**
 * Guard for the two hard packaging rules: the core never imports lit, and
 * the shipped package has no runtime dependencies (lit is an OPTIONAL peer).
 * Runs before the browser tests in `npm test`.
 */
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const pkgDir = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "priv", "js");
const srcDir = join(pkgDir, "src");

const offenders = [];
const modules = [];
for (const file of readdirSync(srcDir)) {
  if (!file.endsWith(".mjs")) continue;
  modules.push(file);
  const text = readFileSync(join(srcDir, file), "utf8");
  if (/(^|[\s(})])(import|export)[^;]*?from\s*["']lit["']/.test(text) || /import\(\s*["']lit["']/.test(text)) {
    offenders.push(`src/${file} imports lit`);
  }
}

const pkg = JSON.parse(readFileSync(join(pkgDir, "package.json"), "utf8"));
for (const key of ["dependencies", "optionalDependencies"]) {
  const deps = pkg[key];
  if (deps && Object.keys(deps).length > 0) {
    offenders.push(`package.json has a non-empty "${key}" block (runtime dependency-free is required)`);
  }
}
if (pkg.peerDependenciesMeta?.lit?.optional !== true) {
  offenders.push('package.json must declare lit as an OPTIONAL peerDependency (peerDependenciesMeta.lit.optional === true)');
}

if (offenders.length > 0) {
  console.error("assert-no-lit FAILED:");
  for (const line of offenders) console.error(`  - ${line}`);
  process.exit(1);
}
console.log(`assert-no-lit ok: ${modules.length} src modules, no lit imports, no runtime deps.`);
