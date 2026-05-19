const express = require("express");
const path = require("path");
const fs = require("fs");

const app = express();
const PORT = process.env.PORT || 8080;

// ── Headers ─────────────────────────────────────────────────────────────────
// Wildcard CORS — every asset is fetchable from any origin.
// COOP + COEP unlock SharedArrayBuffer, which v86 requires for its JIT engine.
// CORP allows downstream embedders to load our resources cross-origin.
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "*");
  res.setHeader("Access-Control-Expose-Headers", "*");
  res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
  res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
  res.setHeader("Cross-Origin-Resource-Policy", "cross-origin");
  if (req.method === "OPTIONS") return res.sendStatus(200);
  next();
});

// ── Static routes ────────────────────────────────────────────────────────────

// v86 engine — latest npm package puts everything in build/
const v86Build = path.join(__dirname, "node_modules", "v86", "build");
if (!fs.existsSync(v86Build)) {
  console.error("\x1b[31m✗\x1b[0m v86 not found. Run \x1b[33mnpm install\x1b[0m first.");
}
app.use("/v86", express.static(v86Build));

// BIOS firmware — downloaded by setup.sh into ./bios/
// (Not bundled in the v86 npm package since 0.5.x)
const biosDir = path.join(__dirname, "bios");
if (!fs.existsSync(biosDir)) {
  console.warn("\x1b[33m⚠\x1b[0m  bios/ folder missing — run \x1b[33mbash setup.sh\x1b[0m");
}
app.use("/bios", express.static(biosDir));

// Disk/ISO images — range requests enabled for async v86 streaming
app.use("/images", express.static(path.join(__dirname, "images"), {
  acceptRanges: true,
  setHeaders(res) {
    res.setHeader("Accept-Ranges", "bytes");
    res.setHeader("Cache-Control", "public, max-age=86400");
  },
}));

// xterm.js — copied to public/lib/ by setup.sh (cp from node_modules).
// Serving as plain static files is more robust on Heroku/Koyeb where
// node_modules may be pruned or relocated after the build step.

// Front-end (includes public/lib/xterm.js, public/lib/xterm.css, etc.)
app.use(express.static(path.join(__dirname, "public")));

// ── Start ────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log("");
  console.log("  \x1b[32m██╗    ██╗███████╗██████╗  ██████╗ ███████╗\x1b[0m");
  console.log("  \x1b[32m██║    ██║██╔════╝██╔══██╗██╔═══██╗██╔════╝\x1b[0m");
  console.log("  \x1b[32m██║ █╗ ██║█████╗  ██████╔╝██║   ██║███████╗\x1b[0m");
  console.log("  \x1b[32m██║███╗██║██╔══╝  ██╔══██╗██║   ██║╚════██║\x1b[0m");
  console.log("  \x1b[32m╚███╔███╔╝███████╗██████╔╝╚██████╔╝███████║\x1b[0m");
  console.log("  \x1b[32m ╚══╝╚══╝ ╚══════╝╚═════╝  ╚═════╝ ╚══════╝\x1b[0m");
  console.log("");
  console.log(`  \x1b[32m✓\x1b[0m Running at \x1b[36mhttp://localhost:${PORT}\x1b[0m`);
  console.log(`  \x1b[90mCORS: *  |  COOP/COEP: enabled  |  SharedArrayBuffer: unlocked\x1b[0m`);
  console.log(`  \x1b[90mv86: 0.5.357  |  Alpine Linux x86  |  ~2 GB vRAM\x1b[0m`);
  console.log("");
});
