// Static server for the Tier 2 spike hosts (plain HTML + React) and the
// prebuilt tessera-holo bundles under dist/. Pattern lifted from
// demo/plain_html/serve.mjs — no dependencies.
import {createServer} from "node:http";
import {readFile} from "node:fs/promises";
import {extname, join, normalize} from "node:path";
import {fileURLToPath} from "node:url";

const root = fileURLToPath(new URL(".", import.meta.url));
const port = Number(process.env.PORT || 5589);

const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".css": "text/css; charset=utf-8",
};

createServer(async (req, res) => {
  try {
    let path = normalize(decodeURIComponent(new URL(req.url, "http://x").pathname));
    if (path.endsWith("/")) path += "index.html";
    const file = join(root, path);
    if (!file.startsWith(root)) throw new Error("traversal");
    const body = await readFile(file);
    res.writeHead(200, {
      "content-type": types[extname(file)] || "application/octet-stream",
      // spike server: always fresh — bundle filenames are stable across
      // rebuilds, so browser caching would serve stale globals
      "cache-control": "no-store",
    });
    res.end(body);
  } catch {
    res.writeHead(404, {"content-type": "text/plain"});
    res.end("not found");
  }
}).listen(port, "127.0.0.1", () => {
  console.log(`tier-2 hosts serving ${root} at http://localhost:${port} (/plain/ and /react/)`);
});
