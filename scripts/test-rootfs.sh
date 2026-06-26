#!/bin/bash
# Test the built rootfs in a Docker container with aarch64 emulation.
# Usage: ./scripts/test-rootfs.sh [path-to-image.img]
#
# This extracts the squashfs SYSTEM partition from the built image
# and runs an interactive shell inside it via Docker multiarch.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

IMG="${1}"
SYSTEM_FILE="${2}"

if [ -z "$IMG" ] && [ -z "$SYSTEM_FILE" ]; then
  # Try to find the most recent build output
  IMG=$(find "$PROJECT_DIR/target" -name "*.img" -type f 2>/dev/null | sort -t/ -k1 | tail -1)
  SYSTEM_FILE=$(find "$PROJECT_DIR/target" -name "*.system" -type f 2>/dev/null | sort -t/ -k1 | tail -1)
fi

WORKDIR=$(mktemp -d)
ROOTFS="$WORKDIR/rootfs"
mkdir -p "$ROOTFS"

cleanup() {
  echo "Cleaning up $WORKDIR..."
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

if [ -n "$SYSTEM_FILE" ] && [ -f "$SYSTEM_FILE" ]; then
  echo "Using squashfs system file: $SYSTEM_FILE"
  unsquashfs -d "$ROOTFS" "$SYSTEM_FILE"
elif [ -n "$IMG" ] && [ -f "$IMG" ]; then
  echo "Extracting SYSTEM partition from: $IMG"
  # Find the SYSTEM partition (second partition typically)
  OFFSET=$(fdisk -l "$IMG" 2>/dev/null | grep -i "Linux" | awk '{print $2}' | tail -1)
  if [ -z "$OFFSET" ]; then
    echo "Could not find Linux partition in image. Trying to find .system file..."
    exit 1
  fi
  dd if="$IMG" of="$WORKDIR/system.raw" bs=512 skip="$OFFSET" 2>/dev/null
  unsquashfs -d "$ROOTFS" "$WORKDIR/system.raw"
else
  echo "No image or system file found."
  echo ""
  echo "Usage: $0 <path-to-.img or path-to-.system>"
  echo ""
  echo "After building, look in target/ for:"
  echo "  - AmberELEC-RG351P.aarch64-*.img"
  echo "  - AmberELEC-RG351P.aarch64-*.system (squashfs)"
  exit 1
fi

echo ""
echo "Rootfs extracted to $ROOTFS"
echo "Launching Docker container (linux/arm64)..."
echo ""

docker run --rm -it \
  --platform linux/arm64 \
  -v "$ROOTFS:/rootfs:ro" \
  ubuntu:22.04 \
  chroot /rootfs /bin/sh
