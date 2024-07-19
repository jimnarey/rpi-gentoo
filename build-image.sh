#!/bin/bash

# A script to create a Gentoo image for the Raspberry Pi 5

# It can be used for previous versions but the --pagesize option for
# the mkswap command should be changed to 4096 for the Raspberry Pi 4
# or lower.

# It reproduces the instructions here: https://wiki.gentoo.org/wiki/Raspberry_Pi_Install_Guide#Tidy_up_and_Test_in_the_Pi
# It downloads the latest Gentoo tar from here: https://distfiles.gentoo.org/releases/arm64/autobuilds/

# stage3-arm64-openrc-20240519T234838Z.tar.xz

# TODO -
# Enable setting of root password on image creation
# Enable setting of hostname on image creation
# Setup Gentoo repo
# Set USE variables
# Update @world set

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as superuser (root)."
    exit 1
fi

if ! command -v kpartx &> /dev/null; then
    echo "The kpartx command is not available. Please install it and try again."
    exit 1
fi

if ! command -v qemu-aarch64-static &> /dev/null; then
    echo "The qemu-aarch64-static command is not available. Please install it and try again."
    exit 1
fi

set -e

cleanup() {
    cd $CURRENT_DIR
    echo "Clean up..."
    if [ -n "$LOOP_DEVICE" ]; then
        echo "Detach loop device $LOOP_DEVICE..."
        losetup -d "$LOOP_DEVICE"
        echo "Remove device mappings..."
        kpartx -d "$LOOP_DEVICE"
    fi
    echo "Unmount everything..."
    if mountpoint -q "${TEMP_DIR}/dev/shm"; then
        umount -l ${TEMP_DIR}/dev/shm
    fi
    if mountpoint -q "${TEMP_DIR}/dev/pts"; then
        umount -l ${TEMP_DIR}/dev/pts
    fi
    if mountpoint -q "${TEMP_DIR}/sys"; then
        umount -R ${TEMP_DIR}/sys
    fi
    if mountpoint -q "${TEMP_DIR}/proc"; then
        umount ${TEMP_DIR}/proc
    fi
    if mountpoint -q "${TEMP_DIR}/boot"; then
        umount ${TEMP_DIR}/boot
    fi
    if mountpoint -q "${TEMP_DIR}/home"; then
        umount ${TEMP_DIR}/home
    fi
    if mountpoint -q "${TEMP_DIR}"; then
        umount ${TEMP_DIR}
    fi
    echo "Remove temporary directory..."
    rmdir $TEMP_DIR

}

CURRENT_DIR=$(pwd)

trap cleanup EXIT

TOTAL_SIZE=$(($2 * 1024))
HOME_SIZE=$(($3 * 1024))

if [ $TOTAL_SIZE -le $HOME_SIZE ]; then
    echo "Total size must be greater than the home partition size."
    echo "Usage: $0 <image_file_name> <total_size_in_GB> <home_partition_size_in_GB>"
    exit 1
fi

FILENAME=$1

echo "Create the image file..."
truncate -s ${TOTAL_SIZE}M $FILENAME

echo "Create a loop device..."
LOOP_DEVICE=$(losetup --show -f $FILENAME)

echo "Create partition table and partitons..."
parted $LOOP_DEVICE -- mklabel msdos
parted $LOOP_DEVICE -- mkpart primary fat32 1MiB 256MiB
parted $LOOP_DEVICE -- mkpart primary linux-swap 256MiB 8704MiB
parted $LOOP_DEVICE -- mkpart primary ext4 8704MiB $(($HOME_SIZE + 8704))MiB
parted $LOOP_DEVICE -- mkpart primary ext4 $(($HOME_SIZE + 8704))MiB 100%

echo "Create loop device mappings..."
kpartx -a $LOOP_DEVICE

echo "Get the loop device partitions..."
BOOT_PARTITION=/dev/mapper/$(basename $LOOP_DEVICE)p1
SWAP_PARTITION=/dev/mapper/$(basename $LOOP_DEVICE)p2
HOME_PARTITION=/dev/mapper/$(basename $LOOP_DEVICE)p3
ROOT_PARTITION=/dev/mapper/$(basename $LOOP_DEVICE)p4

echo "Formatting the partitions..."
mkfs.vfat $BOOT_PARTITION
mkswap $SWAP_PARTITION
mkfs.ext4 $HOME_PARTITION
mkfs.ext4 $ROOT_PARTITION

TEMP_DIR=$(mktemp -d)
mount $ROOT_PARTITION $TEMP_DIR

echo "Creating temp directory for boot fs and mouting..."
mkdir $TEMP_DIR/boot
mount $BOOT_PARTITION $TEMP_DIR/boot

echo "Creating temp directory for home fs and mouting..."
mkdir $TEMP_DIR/home
mount $HOME_PARTITION $TEMP_DIR/home

echo "Downloading stage3 file..."
CACHE_DIR=".cache"
mkdir -p $CACHE_DIR

STAGE3_FILE=$(wget -qO- https://distfiles.gentoo.org/releases/arm64/autobuilds/current-stage3-arm64-openrc/latest-stage3-arm64-openrc.txt | grep '^stage3' | awk '{print $1}')

if [ -f "$CACHE_DIR/$STAGE3_FILE" ]; then
    echo "File $STAGE3_FILE found in cache, skipping download."
else
    echo "File $STAGE3_FILE not found in cache, downloading..."
    wget -P $CACHE_DIR "https://distfiles.gentoo.org/releases/arm64/autobuilds/current-stage3-arm64-openrc/$STAGE3_FILE"
fi

echo "Copying the stage3 file to the temporary directory..."
cp $CACHE_DIR/$STAGE3_FILE $TEMP_DIR

echo "Changing directory to the root mount point..."
cd $TEMP_DIR

echo "Extracting the stage3 file..."
tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

echo "Deleting the stage3 file..."
rm stage3-*.tar.xz

echo "Changing directory to the home mount point..."
cd $TEMP_DIR/home

echo "Clone RPi firmware repository..."
git clone --depth=1 https://github.com/raspberrypi/firmware

echo "Copy the firmware files to the boot partition..."
cp -a firmware/boot/* $TEMP_DIR/boot/

echo "Copy the kernel modules to the root partition..."
cp -a firmware/modules $TEMP_DIR/lib/

echo "Clone the RPi nonfree firmware repository..."
git clone --depth=1 https://github.com/RPi-Distro/firmware-nonfree.git

echo "Create nonfree firmware directory..."
mkdir -p $TEMP_DIR/lib/firmware/brcm

echo "Copy the nonfree firmware files to the nonfree firmware directory..."
cp firmware-nonfree/debian/config/brcm80211/cypress/cyfmac43455-sdio-standard.bin $TEMP_DIR/lib/firmware/brcm/brcmfmac43455-sdio.bin
cp firmware-nonfree/debian/config/brcm80211/cypress/cyfmac43455-sdio.clm_blob $TEMP_DIR/lib/firmware/brcm/brcmfmac43455-sdio.clm_blob
cp firmware-nonfree/debian/config/brcm80211/brcm/brcmfmac43455-sdio.txt $TEMP_DIR/lib/firmware/brcm/

echo "Create nonfree firmware symbolic links..."
cd $TEMP_DIR/lib/firmware/brcm
ln -s brcmfmac43455-sdio.bin brcmfmac43455-sdio.raspberrypi,5-model-b.bin
ln -s brcmfmac43455-sdio.clm_blob brcmfmac43455-sdio.raspberrypi,5-model-b.clm_blob
ln -s brcmfmac43455-sdio.txt brcmfmac43455-sdio.raspberrypi,5-model-b.txt

echo "Changing directory back to the home mount point..."
cd $TEMP_DIR/home

echo "Clone bluetooth firmware repository..."
git clone --depth=1 https://github.com/RPi-Distro/bluez-firmware.git

echo "Copy the bluetooth firmware files to the firmware directory..."
cp bluez-firmware/debian/firmware/broadcom/BCM4345C0.hcd $TEMP_DIR/lib/firmware/brcm/

echo "Create bluetooth firmware symbolic link..."
ln -s $TEMP_DIR/lib/firmware/brcm/BCM4345C0.hcd $TEMP_DIR/lib/firmware/brcm/BCM4345C0.raspberrypi,5-model-b.hcd

echo "Create cmdline.txt..."
echo "dwc_otg.lpm_enable=0 console=tty root=/dev/mmcblk0p4 rootfstype=ext4 rootwait cma=256M@256M net.ifnames=0" > $TEMP_DIR/boot/cmdline.txt

echo "Create config.txt..."
echo -e "# If using arm64 on a Pi3, select a 64 bit kernel\narm_64bit=1\n\n# have a properly sized image\ndisable_overscan=1\n\n# Enable audio (loads snd_bcm2835)\ndtparam=audio=on" > $TEMP_DIR/boot/config.txt

echo "Remove downloaded kernel and firmware files..."
rm -rf $TEMP_DIR/home/*

echo "Create /etc/fstab..."
cat << EOF > $TEMP_DIR/etc/fstab
# <fs>                  <mountpoint>    <type>          <opts>          <dump> <pass>
#LABEL=boot             /boot           ext4            defaults        1 2
#UUID=58e72203-57d1-4497-81ad-97655bd56494              /               xfs             defaults                0 1
#LABEL=swap             none            swap            sw              0 0
#/dev/cdrom             /mnt/cdrom      auto            noauto,ro       0 0
/dev/mmcblk0p1          /boot           vfat            noatime,noauto,nodev,nosuid,noexec	1 2
/dev/mmcblk0p2          swap            swap            defaults                                0 0
/dev/mmcblk0p3          /home           ext4            noatime,nodev,nosuid,noexec             0 0
/dev/mmcblk0p4          /               ext4            noatime                                 0 0
EOF

echo "Set the root password to 'raspberry'..."
sed -i '1c\root:$6$xxPVR/Td5iP$/7Asdgq0ux2sgNkklnndcG4g3493kUYfrrdenBXjxBxEsoLneJpDAwOyX/kkpFB4pU5dlhHEyN0SK4eh/WpmO0::0:99999:7:::' $TEMP_DIR/etc/shadow

echo "Set keymap to UK..."
echo "keymap=\"dvorak-uk\"" >> $TEMP_DIR/etc/conf.d/keymaps

echo "Enable ssh for root..."
echo "PermitRootLogin yes" >> $TEMP_DIR/etc/ssh/sshd_config

echo "Start the ssh service on boot..."
cd $TEMP_DIR/etc/runlevels/default/
ln -s /etc/init.d/sshd sshd

echo "Add init scripts..."
cp $CURRENT_DIR/init-scripts/*.start $TEMP_DIR/etc/local.d/
chmod +x $TEMP_DIR/etc/local.d/*.start

mount --types proc /proc ${TEMP_DIR}/proc
mount --rbind /sys ${TEMP_DIR}/sys
mount --make-rslave ${TEMP_DIR}/sys
mount --rbind /dev ${TEMP_DIR}/dev
mount --make-rslave ${TEMP_DIR}/dev

cp $(which qemu-aarch64-static) ${TEMP_DIR}/usr/bin/

cp /etc/resolv.conf ${TEMP_DIR}/etc/

chroot ${TEMP_DIR} /usr/bin/qemu-aarch64-static /bin/bash <<'EOF'
source /etc/profile
export PS1="(chroot) $PS1"

emerge-webrsync

rm /etc/resolv.conf

exit
EOF
