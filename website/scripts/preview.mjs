// Local preview for Next's static export. Use a static host for deployment.
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { resolve, extname, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { gzip } from "node:zlib";
import { promisify } from "node:util";

const root = fileURLToPath(new URL("../out/", import.meta.url));
const port = Number(process.env.PORT || 3000);
const types = { ".html": "text/html; charset=utf-8", ".css": "text/css", ".js": "text/javascript", ".json": "application/json", ".webp": "image/webp", ".png": "image/png", ".woff2": "font/woff2", ".txt": "text/plain" };
const compress = promisify(gzip);
await stat(resolve(root, "index.html"));
createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url || "/", "http://localhost").pathname);
    let path = resolve(root, `.${pathname}`);
    if (path !== resolve(root) && !path.startsWith(root.endsWith(sep) ? root : `${root}${sep}`)) throw new Error("Invalid path");
    if ((await stat(path)).isDirectory()) path = resolve(path, "index.html");
    let body = await readFile(path);
    const headers = { "Content-Type": types[extname(path)] || "application/octet-stream", "Cache-Control": path.includes(`${sep}_next${sep}static${sep}`) ? "public, max-age=31536000, immutable" : extname(path) === ".html" ? "no-cache" : "public, max-age=3600" };
    if (/\bgzip\b/.test(request.headers["accept-encoding"] || "") && [".html", ".css", ".js", ".json"].includes(extname(path))) {
      body = await compress(body); headers["Content-Encoding"] = "gzip"; headers.Vary = "Accept-Encoding";
    }
    response.writeHead(200, headers);
    response.end(request.method === "HEAD" ? undefined : body);
  } catch { response.writeHead(404); response.end("Not found"); }
}).listen(port, "127.0.0.1", () => process.stdout.write(`Keep website: http://127.0.0.1:${port}\n`));
