# WebOS — Browser Linux Emulation

A focused web OS built around **full x86 Linux emulation** in the browser.  
Powered by [v86](https://github.com/copy/v86) (x86 → WebAssembly) and [xterm.js](https://xtermjs.org/).

```
 ██╗    ██╗███████╗██████╗  ██████╗ ███████╗
 ██║    ██║██╔════╝██╔══██╗██╔═══██╗██╔════╝
 ██║ █╗ ██║█████╗  ██████╔╝██║   ██║███████╗
 ██║███╗██║██╔══╝  ██╔══██╗██║   ██║╚════██║
 ╚███╔███╔╝███████╗██████╔╝╚██████╔╝███████║
  ╚══╝╚══╝ ╚══════╝╚═════╝  ╚═════╝ ╚══════╝
```

---

## Features

| Feature | Detail |
|---|---|
| **Linux emulation** | Full x86 CPU via v86/WebAssembly — runs real Linux binaries |
| **Terminal** | xterm.js connected to the VM's serial console |
| **VGA mode** | Toggle between serial terminal and graphical VGA output |
| **Save / Load state** | Snapshot the entire VM state to a `.bin` file and restore it |
| **Wildcard CORS** | `Access-Control-Allow-Origin: *` on every response |
| **SharedArrayBuffer** | COOP + COEP headers unlock multi-threaded v86 performance |
| **No build step** | Plain HTML + Node.js server, zero bundlers |

---

## Quick Start

### Prerequisites

- **Node.js** 18 or newer
- `wget` or `curl` (for setup.sh)
- A modern browser (Chrome/Edge recommended; Firefox works)

### 1. Install & download assets

```bash
bash setup.sh
```

This does four things:

1. `npm install` — installs Express and v86
2. Downloads **xterm.js** locally (needed so COEP headers apply cleanly)
3. Downloads the **Buildroot Linux bzImage** (~5 MB, boots in ~2 seconds)
4. Verifies all v86 engine files (WASM + BIOS)

### 2. Start the server

```bash
npm start
```

### 3. Open your browser

```
http://localhost:8080
```

The boot splash plays, then Linux comes up on the serial console. You have a
full BusyBox shell — try `uname -a`, `ls /`, `cat /proc/cpuinfo`.

---

## HTTP Headers

Every response from the server includes:

```
Access-Control-Allow-Origin:  *
Access-Control-Allow-Methods: GET, HEAD, OPTIONS
Access-Control-Allow-Headers: *
Access-Control-Expose-Headers: *
Cross-Origin-Opener-Policy:   same-origin
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Resource-Policy: cross-origin
```

**Why COOP + COEP?**  
v86 uses `SharedArrayBuffer` for its JIT-compiled x86 emulation. Modern
browsers only permit `SharedArrayBuffer` in "cross-origin isolated" contexts,
which requires these two headers. The wildcard CORS header (`*`) is set
alongside them so the page and its assets can still be fetched from any origin.

---

## Customisation

All emulator settings live in the `V86({...})` config block at the bottom of
`public/index.html`. Common tweaks:

### Change RAM

```js
memory_size: 512 * 1024 * 1024,   // 512 MB
```

### Use Alpine Linux instead of Buildroot

1. Download the image:
   ```bash
   wget -O images/alpine.iso "https://copy.sh/v86/images/alpine-3.19.4.iso"
   ```
2. Update the config:
   ```js
   // Remove bzimage line, add:
   cdrom: { url: "/images/alpine.iso", async: true },
   cmdline: "console=ttyS0 console=tty0",
   ```

### Add a persistent disk

```js
hda: {
  url:   "/images/disk.img",   // create with: dd if=/dev/zero bs=1M count=512 > images/disk.img
  size:  512 * 1024 * 1024,
  async: true,
},
```

### Change kernel cmdline

```js
cmdline: "console=ttyS0 quiet loglevel=3 init=/bin/sh",
```

---

## Project Layout

```
webos/
├── server.js          ← Express server (CORS, COOP/COEP, static routes)
├── setup.sh           ← One-shot asset downloader
├── package.json
├── images/
│   └── bzimage        ← Linux kernel (downloaded by setup.sh)
└── public/
    ├── index.html     ← The entire OS UI
    └── lib/
        ├── xterm.js
        ├── xterm.css
        └── xterm-addon-fit.js
```

`node_modules/v86/` contains:
- `build/libv86.js` — the JS wrapper
- `build/v86.wasm`  — the x86 emulation engine
- `bios/seabios.bin`, `bios/vgabios.bin` — firmware

---

## Browser Notes

| Browser | Notes |
|---|---|
| Chrome / Edge | ✅ Full support, best performance |
| Firefox | ✅ Works, slightly slower JIT |
| Safari | ⚠️  SharedArrayBuffer may require additional flags |

---

## Credits

- **[v86](https://github.com/copy/v86)** by Fabian Hemmer — x86 emulator in JS/WASM
- **[xterm.js](https://xtermjs.org/)** — browser terminal emulator
- **[AnuraOS](https://github.com/MercuryWorkshop/anuraOS)** by Mercury Workshop — original inspiration
- **[Buildroot](https://buildroot.org/)** — the minimal Linux image
- **[SeaBIOS](https://seabios.org/)** — x86 BIOS firmware

---

## License

MIT — do whatever you want with this.
