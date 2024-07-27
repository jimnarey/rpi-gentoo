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
# Enable setting timezone on image creation (see ...set-time.start for harcoded use of GMT)
# Review USE variables after work on application(s)
# Update @world set
# Fix errant loop devices

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

SWAP_SIZE=2048
ROOT_SIZE=8192
HOME_SIZE=2048

# Parse options
while getopts "s:r:u:" opt; do
  case $opt in
    s) SWAP_SIZE=$OPTARG ;;
    r) ROOT_SIZE=$OPTARG ;;
    u) HOME_SIZE=$OPTARG ;;
    \?) echo "Invalid option -$OPTARG" >&2
        exit 1
        ;;
  esac
done

echo "SWAP_SIZE: $SWAP_SIZE"
echo "ROOT_SIZE: $ROOT_SIZE"
echo "HOME_SIZE: $HOME_SIZE"

cleanup() {
    set +e
    cd $CURRENT_DIR
    echo "Clean up..."
    echo "Kill processes..."
    fuser -k ${TEMP_DIR} || true
    echo "Wait..."
    sleep 2

    echo "Unmount everything..."

    echo "Unmount dev..."
    umount -R ${TEMP_DIR}/dev || umount -R -l ${TEMP_DIR}/dev

    echo "Unmount sys..."
    umount -R ${TEMP_DIR}/sys || umount -R -l ${TEMP_DIR}/sys

    echo "Unmount proc..."
    umount ${TEMP_DIR}/proc || umount -l ${TEMP_DIR}/proc

    echo "Unmount boot..."
    umount ${TEMP_DIR}/boot || umount -l ${TEMP_DIR}/boot

    echo "Unmount home..."
    umount ${TEMP_DIR}/home || umount -l ${TEMP_DIR}/home

    echo "Unmount root..."
        umount ${TEMP_DIR} || umount ${TEMP_DIR}

    echo "Remove temporary directory..."
    rmdir $TEMP_DIR

    if [ -n "$LOOP_DEVICE" ]; then
        echo "Detach loop device $LOOP_DEVICE..."
        losetup -d "$LOOP_DEVICE"
        echo "Remove device mappings..."
        kpartx -d "$LOOP_DEVICE"
    fi

}

CURRENT_DIR=$(pwd)

trap cleanup EXIT

TOTAL_SIZE=$(($HOME_SIZE + $ROOT_SIZE + $SWAP_SIZE + 256))

FILENAME=$1

echo "Create the image file..."
truncate -s ${TOTAL_SIZE}M $FILENAME

echo "Create a loop device..."
LOOP_DEVICE=$(losetup --show -f $FILENAME)

echo "Create partition table and partitons..."
parted $LOOP_DEVICE -- mklabel msdos
parted $LOOP_DEVICE -- mkpart primary fat32 1MiB 256MiB
parted $LOOP_DEVICE -- mkpart primary linux-swap 256MiB $(($SWAP_SIZE + 256))MiB
parted $LOOP_DEVICE -- mkpart primary ext4 $(($SWAP_SIZE + 256))MiB $(($SWAP_SIZE + $HOME_SIZE + 256))MiB
parted $LOOP_DEVICE -- mkpart primary ext4 $(($SWAP_SIZE + $HOME_SIZE + 256))MiB 100%

echo "Create loop device mappings..."
kpartx -a $LOOP_DEVICE

echo "Get the loop device partitions..."
BOOT_PARTITION=/dev/mapper/$(basename $LOOP_DEVICE)p1
SWAP_PARTITION=/dev/mapper/$(basename $LOOP_DEVICE)p2
HOME_PARTITION=/dev/mapper/$(basename $LOOP_DEVICE)p3
ROOT_PARTITION=/dev/mapper/$(basename $LOOP_DEVICE)p4

echo "Formatting the partitions..."
mkfs.vfat -n BOOT $BOOT_PARTITION
mkswap -L SWAP $SWAP_PARTITION
mkfs.ext4 -L HOME $HOME_PARTITION
mkfs.ext4 -L ROOT $ROOT_PARTITION

TEMP_DIR=$(mktemp -d)
mount $ROOT_PARTITION $TEMP_DIR

echo "Creating temp directory for boot fs and mounting..."
mkdir $TEMP_DIR/boot
mount $BOOT_PARTITION $TEMP_DIR/boot

echo "Creating temp directory for home fs and mounting..."
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
/dev/mmcblk0p1          /boot           vfat            noatime,nodev,nosuid,noexec	1 2
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

echo "Add install scripts..."
cp -r $CURRENT_DIR/install-scripts $TEMP_DIR/root/
chmod +x $TEMP_DIR/root/install-scripts/*.sh

echo "Add scripts to /usr/local/bin..."
cp $CURRENT_DIR/bin/*.sh $TEMP_DIR/usr/local/bin/
chmod +x $TEMP_DIR/usr/local/bin/*.sh

echo "Add client ssh keys..."
mkdir -p $TEMP_DIR/root/.ssh

if [[ ! -f "${CURRENT_DIR}/ssh/id_ed25519" || ! -f "${CURRENT_DIR}/ssh/id_ed25519.pub" ]]; then
    echo "Create new ssh keys..."
    rm -rf "${CURRENT_DIR}/ssh/"*
    mkdir -p "${CURRENT_DIR}/ssh"
    ssh-keygen -t ed25519 -N "" -f "${CURRENT_DIR}/ssh/id_ed25519" -q
else
    echo "Use existing ssh keys..."
fi

cp "${CURRENT_DIR}/ssh/id_ed25519" "${TEMP_DIR}/root/.ssh/"
cp "${CURRENT_DIR}/ssh/id_ed25519.pub" "${TEMP_DIR}/root/.ssh/"


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
eselect news read > /dev/null 2>&1
eselect news purge

emerge --sync

rm /etc/resolv.conf

exit
EOF

rm ${TEMP_DIR}/usr/bin/qemu-aarch64-static
