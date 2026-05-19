#!/usr/bin/env bash
set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ALPINE_VER="3.23.4"
IMG_SIZE_MB=1024           # 1 GiB raw disk image
IMG_SIZE_BYTES=$((IMG_SIZE_MB * 1024 * 1024))

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
echo -e "${BOLD}[1/4] Installing Node.js dependencies (v86 + Express + xterm)...${NC}"
npm install
echo -e "${GREEN}      ✓ Done${NC}"
echo ""

# ── 2. BIOS firmware ──────────────────────────────────────────────────────────
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

# ── 3. Alpine Linux disk image ────────────────────────────────────────────────
# We build a pre-installed Alpine 3.23.4 x86 raw disk image (NOT a live ISO).
# Booting from a proper ext4 install means:
#   • apk add / apk del work fully and persistently
#   • All package repositories are available immediately
#   • No squashfs / tmpfs overlay limiting writes
#
# The image is built inside a Docker container (--platform linux/386) so no
# native x86 hardware or QEMU is required on the host.  The container runs
# with --privileged so it can set up loop devices and write an MBR.

echo -e "${BOLD}[3/4] Building Alpine Linux ${ALPINE_VER} x86 disk image...${NC}"
mkdir -p images

ALPINE_IMG="images/alpine.img"

if [ -f "$ALPINE_IMG" ]; then
  echo -e "      ${YELLOW}⚠  $ALPINE_IMG exists, skipping.${NC}"
  echo -e "         Delete it and re-run if you want a fresh build."
  echo ""
else
  # ── Require Docker ────────────────────────────────────────────────────────
  if ! command -v docker &>/dev/null; then
    echo -e "  ${RED}✗ Docker is required to build the disk image but was not found.${NC}"
    echo ""
    echo -e "  Install Docker Desktop (Mac/Windows) or Docker Engine (Linux):"
    echo -e "  ${CYAN}https://docs.docker.com/get-docker/${NC}"
    echo ""
    echo -e "  Then re-run: ${CYAN}bash setup.sh${NC}"
    exit 1
  fi

  # ── Write Dockerfile ──────────────────────────────────────────────────────
  # Uses the official i386/alpine image so the resulting rootfs is genuinely
  # 32-bit Alpine — matching v86's x86 CPU emulation.
  cat > /tmp/Dockerfile.alpine-v86 << DOCKERFILE
FROM --platform=linux/386 alpine:${ALPINE_VER}

# Base system + kernel (linux-lts is the stable LTS kernel for Alpine 3.23)
RUN apk add --no-cache \\
    alpine-base \\
    openrc \\
    linux-lts \\
    linux-firmware-none \\
    syslinux \\
    e2fsprogs \\
    util-linux \\
    busybox-initscripts

# ── Root account — passwordless login ─────────────────────────────────────
RUN passwd -d root

# ── VGA console: autologin as root on tty1 ────────────────────────────────
RUN sed -i 's|getty 38400 tty1|agetty --autologin root tty1 linux|' /etc/inittab 2>/dev/null || \\
    sed -i 's|tty1::respawn:.*|tty1::respawn:/sbin/agetty --autologin root tty1 linux|' /etc/inittab

# ── Serial console: autologin on ttyS0 (v86 serial port) ─────────────────
RUN echo 'ttyS0::respawn:/sbin/agetty --autologin root -L ttyS0 115200 vt100' >> /etc/inittab

# ── Hostname ──────────────────────────────────────────────────────────────
RUN echo 'webos' > /etc/hostname

# ── APK repositories (main + community) ──────────────────────────────────
RUN printf 'https://dl-cdn.alpinelinux.org/alpine/v3.23/main\nhttps://dl-cdn.alpinelinux.org/alpine/v3.23/community\n' \\
    > /etc/apk/repositories

# ── Networking: DHCP on eth0 ──────────────────────────────────────────────
RUN printf 'auto lo\niface lo inet loopback\nauto eth0\niface eth0 inet dhcp\n' \\
    > /etc/network/interfaces

RUN rc-update add networking boot && \\
    rc-update add hostname boot

# ── /etc/fstab ────────────────────────────────────────────────────────────
RUN printf 'LABEL=/ / ext4 defaults,noatime 0 1\n' > /etc/fstab

COPY build-disk.sh /build-disk.sh
RUN chmod +x /build-disk.sh
DOCKERFILE

  # ── Write inner build script ──────────────────────────────────────────────
  # This runs inside the privileged container and produces the raw disk image.
  cat > /tmp/build-disk.sh << 'DISKSCRIPT'
#!/bin/sh
set -e

IMGFILE="/output/alpine.img"
IMG_MB=${IMG_SIZE_MB:-1024}

echo "[build-disk] Creating ${IMG_MB} MiB blank image..."
dd if=/dev/zero of="$IMGFILE" bs=1M count="$IMG_MB" status=none

echo "[build-disk] Partitioning (MBR, one Linux partition)..."
# sfdisk partition: start at 2048 sectors (1 MiB), fill rest, type 83 Linux
printf 'label: dos\nstart=2048, type=83, bootable\n' | sfdisk --no-reread -q "$IMGFILE"

echo "[build-disk] Setting up loop device..."
LOOP=$(losetup -f)
losetup -P "$LOOP" "$IMGFILE"
LOOP_PART="${LOOP}p1"

echo "[build-disk] Formatting ext4..."
mkfs.ext4 -q -L / "$LOOP_PART"

echo "[build-disk] Mounting and copying rootfs..."
mkdir -p /mnt/target
mount "$LOOP_PART" /mnt/target

# Copy the container's root filesystem — this IS the Alpine 3.23.4 install
rsync -aHAX --exclude=/proc --exclude=/sys --exclude=/dev \
      --exclude=/mnt --exclude=/output --exclude=/tmp \
      --exclude=/build-disk.sh \
      / /mnt/target/

# Recreate essential empty directories
mkdir -p /mnt/target/{proc,sys,dev,tmp,run}
chmod 1777 /mnt/target/tmp

echo "[build-disk] Installing extlinux bootloader..."
mkdir -p /mnt/target/boot/extlinux

# Copy required syslinux modules
for f in ldlinux.c32 libcom32.c32 libutil.c32 menu.c32; do
  src=$(find /usr/share/syslinux /usr/lib/syslinux -name "$f" 2>/dev/null | head -1)
  [ -n "$src" ] && cp "$src" /mnt/target/boot/extlinux/
done

extlinux --install /mnt/target/boot/extlinux/

echo "[build-disk] Writing MBR..."
MBR=$(find /usr/share/syslinux /usr/lib/syslinux -name "mbr.bin" 2>/dev/null | head -1)
dd if="$MBR" of="$LOOP" bs=440 count=1 conv=notrunc status=none

echo "[build-disk] Writing extlinux.conf..."
VMLINUZ=$(ls /mnt/target/boot/vmlinuz-* 2>/dev/null | head -1 | xargs basename 2>/dev/null)
INITRAMFS=$(ls /mnt/target/boot/initramfs-* 2>/dev/null | head -1 | xargs basename 2>/dev/null)

if [ -z "$VMLINUZ" ] || [ -z "$INITRAMFS" ]; then
  echo "ERROR: Could not find kernel or initramfs in /boot/" >&2
  ls /mnt/target/boot/ >&2
  exit 1
fi

cat > /mnt/target/boot/extlinux/extlinux.conf << CONF
DEFAULT linux
TIMEOUT 10
LABEL linux
  LINUX /boot/${VMLINUZ}
  INITRD /boot/${INITRAMFS}
  APPEND root=LABEL=/ rootfstype=ext4 modules=sd-mod,usb-storage,ext4 quiet rw console=ttyS0,115200 console=tty0 vga=791
CONF

echo "[build-disk] Syncing and unmounting..."
sync
umount /mnt/target
losetup -d "$LOOP"

SIZE=$(du -sh "$IMGFILE" | cut -f1)
echo "[build-disk] Done — $IMGFILE ($SIZE)"
DISKSCRIPT

  echo -e "      ${CYAN}Alpine ${ALPINE_VER} x86 — 1 GiB ext4 disk + extlinux bootloader${NC}"
  echo -e "      ${CYAN}This may take a few minutes (Docker pull + package install)...${NC}"
  echo ""

  # ── Build Docker image ────────────────────────────────────────────────────
  docker build \
    --platform linux/386 \
    -t alpine-v86-builder:${ALPINE_VER} \
    -f /tmp/Dockerfile.alpine-v86 \
    --build-arg ALPINE_VER="${ALPINE_VER}" \
    /tmp 2>&1 | sed 's/^/      /'

  echo ""
  echo -e "      Building disk image (requires --privileged for loop devices)..."

  # ── Run container to produce the image ───────────────────────────────────
  docker run --rm \
    --platform linux/386 \
    --privileged \
    -e IMG_SIZE_MB="${IMG_SIZE_MB}" \
    -v "$(pwd)/images:/output" \
    alpine-v86-builder:${ALPINE_VER} \
    /build-disk.sh 2>&1 | sed 's/^/      /'

  # ── Clean up temp files ───────────────────────────────────────────────────
  rm -f /tmp/Dockerfile.alpine-v86 /tmp/build-disk.sh

  if [ -f "$ALPINE_IMG" ]; then
    echo -e "${GREEN}      ✓ $(du -sh $ALPINE_IMG | cut -f1) Alpine disk image${NC}"
  else
    echo -e "  ${RED}✗ Disk image was not produced — check Docker output above.${NC}"
    exit 1
  fi
fi

# ── 4. Verify ─────────────────────────────────────────────────────────────────
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
  "images/alpine.img"
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
echo -e "  ${YELLOW}Alpine Linux login:${NC}  root  (autologin, no password)"
echo -e "  ${YELLOW}Install packages:${NC}    apk add nano vim htop python3 ..."
echo -e "  ${YELLOW}Networking:${NC}          wss://relay.widgetry.org (public relay)"
echo -e "  ${YELLOW}Disk:${NC}                1 GiB ext4 — changes persist across reboots"
echo ""
