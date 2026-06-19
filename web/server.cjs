const http = require("http");
const fs = require("fs");
const path = require("path");
const root = __dirname;
const types = { ".html": "text/html", ".css": "text/css", ".svg": "image/svg+xml", ".js": "text/javascript", ".png": "image/png", ".jpeg": "image/jpeg", ".jpg": "image/jpeg", ".mp4": "video/mp4" };
http.createServer((req, res) => {
  let p;
  try { p = decodeURIComponent(req.url.split("?")[0]); }
  catch { res.writeHead(400); return res.end("bad request"); }
  if (p === "/") p = "/index.html";
  const file = path.resolve(root, "." + p);
  // Confine to root: the file must be root itself or sit beneath root + separator.
  // A plain startsWith(root) check is bypassable by a sibling dir that shares the
  // prefix (e.g. ".../web-evil" passes a ".../web" test), so anchor on the separator.
  const rootPrefix = root.endsWith(path.sep) ? root : root + path.sep;
  if ((file !== root && !file.startsWith(rootPrefix)) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
    res.writeHead(404); return res.end("not found");
  }
  res.writeHead(200, { "Content-Type": types[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
}).listen(4599, () => console.log("serving on 4599"));
