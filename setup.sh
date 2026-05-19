#!/usr/bin/env bash
set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${GREEN}  WebOS Setup${NC}"
echo -e "${GREEN}  ─────────────────────────────────${NC}"
echo ""

download() {
  local url="$1" out="$2"
  if command -v curl &>/dev/null; then
    curl -L --progress-bar "$url" -o "$out"
  else
    wget -q --show-progress "$url" -O "$out"
  fi
}

# ── 1. npm install ────────────────────────────────────────────────────────────
# @xterm/xterm and @xterm/addon-fit are now proper npm dependencies.
# They ship UMD bundles that the Express server routes directly from node_modules,
# so there are no fragile CDN curl downloads to break under COEP headers.
echo -e "${BOLD}[1/4] Installing Node.js dependencies (v86 0.5.357 + Express + xterm)...${NC}"
npm install
echo -e "${GREEN}      ✓ Done${NC}"
echo ""

# ── 2. BIOS firmware ──────────────────────────────────────────────────────────
# The v86 npm package (0.5.x+) no longer bundles BIOS files.
# We fetch them from the official v86 GitHub repository.
echo -e "${BOLD}[2/4] Downloading BIOS firmware (SeaBIOS + VGA BIOS)...${NC}"
mkdir -p bios

V86_BIOS_BASE="https://raw.githubusercontent.com/copy/v86/master/bios"

if [ ! -f "bios/seabios.bin" ]; then
  download "${V86_BIOS_BASE}/seabios.bin" "bios/seabios.bin"
  echo -e "${GREEN}      ✓ seabios.bin  ($(du -sh bios/seabios.bin | cut -f1))${NC}"
else
  echo -e "      ${YELLOW}⚠  bios/seabios.bin exists, skipping${NC}"
fi

if [ ! -f "bios/vgabios.bin" ]; then
  download "${V86_BIOS_BASE}/vgabios.bin" "bios/vgabios.bin"
  echo -e "${GREEN}      ✓ vgabios.bin  ($(du -sh bios/vgabios.bin | cut -f1))${NC}"
else
  echo -e "      ${YELLOW}⚠  bios/vgabios.bin exists, skipping${NC}"
fi
echo ""

# ── 4. Alpine Linux ISO ───────────────────────────────────────────────────────
echo -e "${BOLD}[3/4] Downloading Alpine Linux x86 ISO...${NC}"
echo -e "      ${CYAN}Alpine 3.19 x86 standard — ~175 MB${NC}"
echo -e "      ${CYAN}Supports apk, X11 apps, and nearly all Linux tools.${NC}"
mkdir -p images

ALPINE_VER="3.19.4"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86/alpine-standard-${ALPINE_VER}-x86.iso"
ALPINE_OUT="images/alpine.iso"

if [ -f "$ALPINE_OUT" ]; then
  echo -e "      ${YELLOW}⚠  images/alpine.iso exists, skipping.${NC}"
  echo -e "         Delete it and re-run if you want a fresh copy."
else
  download "$ALPINE_URL" "$ALPINE_OUT"
  echo -e "${GREEN}      ✓ $(du -sh $ALPINE_OUT | cut -f1) Alpine ISO${NC}"
fi
echo ""

# ── 5. Verify ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}[4/4] Verifying all required files...${NC}"
ok=true
for f in \
  "node_modules/v86/build/libv86.js" \
  "node_modules/v86/build/v86.wasm" \
  "node_modules/v86/build/v86-fallback.wasm" \
  "node_modules/@xterm/xterm/lib/xterm.js" \
  "node_modules/@xterm/xterm/css/xterm.css" \
  "node_modules/@xterm/addon-fit/lib/addon-fit.js" \
  "bios/seabios.bin" \
  "bios/vgabios.bin" \
  "images/alpine.iso"
do
  if [ -f "$f" ]; then
    echo -e "      ${GREEN}✓${NC} $f"
  else
    echo -e "      ${RED}✗${NC} $f  ${RED}← MISSING${NC}"
    ok=false
  fi
done

if [ "$ok" = false ]; then
  echo ""
  echo -e "  ${RED}Some files are missing. Re-run setup.sh to retry.${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}  ─────────────────────────────────${NC}"
echo -e "${GREEN}  Setup complete! 🐧${NC}"
echo ""
echo -e "  Start the server:  ${CYAN}npm start${NC}"
echo -e "  Open browser:      ${CYAN}http://localhost:8080${NC}"
echo ""
echo -e "  ${YELLOW}Alpine Linux login:${NC}  root  (no password)"
echo -e "  ${YELLOW}Install packages:${NC}    apk add nano vim htop python3 ..."
echo -e "  ${YELLOW}Networking:${NC}          wss://relay.widgetry.org (public relay)"
echo ""
