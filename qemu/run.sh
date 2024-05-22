#!/bin/bash

if [ ! -d "/image" ]; then
    echo "Error: root directory 'image' does not exist."
    exit 1
fi

IMAGE_PATH="/image/$IMAGE_FILE"

TEMP_DIR=$(mktemp -d)

CURRENT_SIZE=$(stat -c%s "${IMAGE_PATH}")

NEW_SIZE=$(next_power_of_two.py ${CURRENT_SIZE})

qemu-img resize "${IMAGE_PATH}" "${NEW_SIZE}"

OFFSET=$(fdisk -lu ${IMAGE_PATH} | awk '/^Sector size/ {sector_size=$4} /FAT32 \(LBA\)/ {print $2 * sector_size}')

if [ -z "$OFFSET" ]; then
    echo "Error: FAT32 not found in disk image"
    exit 1; 
fi

echo "FAT32 partition offset: ${OFFSET}"

# Setup mtools config to extract files from the partition
echo "drive x: file=\"${IMAGE_PATH}\" offset=${OFFSET}" > ~/.mtoolsrc

mcopy x:/bcm2710-rpi-3-b-plus.dtb ${TEMP_DIR}
mcopy x:/kernel8.img ${TEMP_DIR}

qemu-system-aarch64 -machine raspi3b \
                    -cpu cortex-a72 \
                    -nographic -dtb ${TEMP_DIR}/bcm2710-rpi-3-b-plus.dtb \
                    -m 1G \
                    -smp 4 \
                    -kernel ${TEMP_DIR}/kernel8.img \
                    -sd ${IMAGE_PATH} \
                    -append "rw earlyprintk loglevel=8 console=ttyAMA0,115200 dwc_otg.lpm_enable=0 root=/dev/mmcblk0p4 rootdelay=1" \
                    # -device usb-net,netdev=net0 \
                    # -netdev user,id=net0,hostfwd=tcp::2222-:22
                    -device usb-net,netdev=ulan,mac=02:ca:fe:f0:0d:01 \
                    -netdev user,id=ulan,hostfwd=tcp::2222-:22