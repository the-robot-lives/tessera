// Tiny static file server for the tessera gallery (no dependencies —
// `node serve.mjs` is the whole tool). Serves this directory on
// http://localhost:5588 with correct MIME types for .html/.js/.mjs/.json.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL(".", import.meta.url));
const port = Number(process.env.PORT || 5588);

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
    res.writeHead(200, {"content-type": types[extname(file)] || "application/octet-stream"});
    res.end(body);
  } catch {
    res.writeHead(404, {"content-type": "text/plain"});
    res.end("not found");
  }
}).listen(port, "127.0.0.1", () => {
  console.log(`tessera gallery serving ${root} at http://localhost:${port}`);
});
