#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as superuser (root)."
    exit 1
fi

if [ "$#" -ne 1 ]; then
    echo "Usage: sudo $0 TARGET_IMAGE"
    exit 1
fi

KERNEL=kernel_2712
LINUX_SRC_DIR="./pi-rt-kernel/build/linux"
BUILD_BOOT_DIR="./pi-rt-kernel/build/linux/arch/arm64/boot"
TARGET_IMAGE="$1"

if [ ! -f "$TARGET_IMAGE" ]; then
    echo "The target image file does not exist."
    exit 1
fi

TEMP_DIR=$(mktemp -d)
echo "Mount partitions to $TEMP_DIR"

LOOP_DEVICE=$(sudo losetup --show -f -P "$TARGET_IMAGE")

ROOT_MOUNT_POINT="${TEMP_DIR}/root"
BOOT_MOUNT_POINT="${TEMP_DIR}/boot"
mkdir -p "$ROOT_MOUNT_POINT"
mkdir -p "$BOOT_MOUNT_POINT"

ROOT_PART=$(blkid -o device -l -t LABEL="ROOT" | grep "^${LOOP_DEVICE}")
BOOT_PART=$(blkid -o device -l -t LABEL="BOOT" | grep "^${LOOP_DEVICE}")

if [ -n "$ROOT_PART" ]; then
    mount "$ROOT_PART" "$ROOT_MOUNT_POINT"
    echo "Mounted ROOT partition to $ROOT_MOUNT_POINT"
else
    echo "ROOT partition not found."
fi

if [ -n "$BOOT_PART" ]; then
    mount "$BOOT_PART" "$BOOT_MOUNT_POINT"
    echo "Mounted BOOT partition to $BOOT_MOUNT_POINT"
else
    echo "BOOT partition not found."
fi

echo "Install kernel.."

(cd "${LINUX_SRC_DIR}" && env PATH=$PATH make -j12 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="${ROOT_MOUNT_POINT}" modules_install)

cp "${BOOT_MOUNT_POINT}/$KERNEL.img" "${BOOT_MOUNT_POINT}/$KERNEL-backup.img"
cp "${BUILD_BOOT_DIR}/Image" "${BOOT_MOUNT_POINT}/$KERNEL.img"
cp "${BUILD_BOOT_DIR}/dts/broadcom/"*.dtb "${BOOT_MOUNT_POINT}"
cp "${BUILD_BOOT_DIR}/dts/overlays/"*.dtb* "${BOOT_MOUNT_POINT}/overlays/"
cp "${BUILD_BOOT_DIR}/dts/overlays/README" "${BOOT_MOUNT_POINT}/overlays/"

echo "Clean up..."

if mountpoint -q "$BOOT_MOUNT_POINT"; then
    echo "Unmount BOOT partition..."
    umount "$BOOT_MOUNT_POINT"
fi

if mountpoint -q "$ROOT_MOUNT_POINT"; then
    echo "Unmount ROOT partition..."
    umount "$ROOT_MOUNT_POINT"
fi

echo "Remove temporary directory..."
rm -rf "$TEMP_DIR"

if [ -n "$LOOP_DEVICE" ]; then
    echo "Detach loop device $LOOP_DEVICE..."
    losetup -d "$LOOP_DEVICE"
fi
