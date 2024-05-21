#!/bin/bash

# A script to create a Gentoo image for the Raspberry Pi 5

# It can be used for previous versions but the --pagesize option for
# the mkswap command should be changed to 4096 for the Raspberry Pi 4
# or lower.

# It reproduces the instructions here: https://wiki.gentoo.org/wiki/Raspberry_Pi_Install_Guide#Tidy_up_and_Test_in_the_Pi
# It downloads the latest Gentoo tar from here: https://distfiles.gentoo.org/releases/arm64/autobuilds/

# stage3-arm64-openrc-20240519T234838Z.tar.xz

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as superuser (root)."
    exit 1
fi

if ! command -v kpartx &> /dev/null; then
    echo "The kpartx command is not available. Please install it and try again."
    exit 1
fi

set -e

cleanup() {
    echo "Cleaning up..."
    if [ -n "$loop_device" ]; then
        echo "Detaching loop device $loop_device..."
        sudo losetup -d "$loop_device"
    fi
    echo "Removing device mappings..."
    sudo kpartx -d "$loop_device"
}

current_dir=$(pwd)

trap cleanup EXIT

total_size=$(($2 * 1024))
home_size=$(($3 * 1024))

if [ $total_size -le $home_size ]; then
    echo "Total size must be greater than the home partition size."
    echo "Usage: $0 <image_file_name> <total_size_in_GB> <home_partition_size_in_GB>"
    exit 1
fi

filename=$1

echo "Create the image file..."
truncate -s ${total_size}M $filename

echo "Create a loop device..."
loop_device=$(losetup --show -f $filename)

echo "Create partition table and partitons..."
parted $loop_device -- mklabel msdos
parted $loop_device -- mkpart primary fat32 1MiB 256MiB
parted $loop_device -- mkpart primary linux-swap 256MiB 8704MiB
parted $loop_device -- mkpart primary ext4 8704MiB $(($home_size + 8704))MiB
parted $loop_device -- mkpart primary ext4 $(($home_size + 8704))MiB 100%

echo "Create loop device mappings..."
kpartx -a $loop_device

echo "Get the loop device partitions..."
boot_partition=/dev/mapper/$(basename $loop_device)p1
swap_partition=/dev/mapper/$(basename $loop_device)p2
home_partition=/dev/mapper/$(basename $loop_device)p3
root_partition=/dev/mapper/$(basename $loop_device)p4

echo "Formatting the partitions..."
mkfs.vfat $boot_partition
mkswap $swap_partition
mkfs.ext4 $home_partition
mkfs.ext4 $root_partition

temp_dir=$(mktemp -d)
mount $root_partition $temp_dir

echo "Creating temp directory for boot fs and mouting..."
mkdir $temp_dir/boot
mount $boot_partition $temp_dir/boot

echo "Creating temp directory for home fs and mouting..."
mkdir $temp_dir/home
mount $home_partition $temp_dir/home

echo "Downloading stage3 file..."
cache_dir=".cache"
mkdir -p $cache_dir

stage3_file=$(wget -qO- https://distfiles.gentoo.org/releases/arm64/autobuilds/current-stage3-arm64-openrc/latest-stage3-arm64-openrc.txt | grep '^stage3' | awk '{print $1}')

if [ -f "$cache_dir/$stage3_file" ]; then
    echo "File $stage3_file found in cache, skipping download."
else
    echo "File $stage3_file not found in cache, downloading..."
    wget -P $cache_dir "https://distfiles.gentoo.org/releases/arm64/autobuilds/current-stage3-arm64-openrc/$stage3_file"
fi

echo "Copying the stage3 file to the temporary directory..."
cp $cache_dir/$stage3_file $temp_dir

echo "Changing directory to the root mount point..."
cd $temp_dir

echo "Extracting the stage3 file..."
tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

echo "Clone RPi firmware repository..."
git clone --depth=1 https://github.com/raspberrypi/firmware

echo "Copy the firmware files to the boot partition..."
cp -a firmware/boot/* $temp_dir/boot/

echo "Copy the kernel modules to the root partition..."
cp -a firmware/modules $temp_dir/lib/

echo "Clone the RPi nonfree firmware repository..."
git clone --depth=1 https://github.com/RPi-Distro/firmware-nonfree.git

echo "Create nonfree firmware directory..."
mkdir -p $temp_dir/lib/firmware/brcm

echo "Copy the nonfree firmware files to the nonfree firmware directory..."
cp firmware-nonfree/debian/config/brcm80211/cypress/cyfmac43455-sdio-standard.bin $temp_dir/lib/firmware/brcm/brcmfmac43455-sdio.bin
cp firmware-nonfree/debian/config/brcm80211/cypress/cyfmac43455-sdio.clm_blob $temp_dir/lib/firmware/brcm/brcmfmac43455-sdio.clm_blob
cp firmware-nonfree/debian/config/brcm80211/brcm/brcmfmac43455-sdio.txt $temp_dir/lib/firmware/brcm/

echo "Create nonfree firmware symbolic links..."
cd $temp_dir/lib/firmware/brcm
ln -s brcmfmac43455-sdio.bin brcmfmac43455-sdio.raspberrypi,5-model-b.bin
ln -s brcmfmac43455-sdio.clm_blob brcmfmac43455-sdio.raspberrypi,5-model-b.clm_blob
ln -s brcmfmac43455-sdio.txt brcmfmac43455-sdio.raspberrypi,5-model-b.txt

echo "Changing directory back to the root mount point..."
cd $temp_dir

echo "Clone bluetooth firmware repository..."
git clone --depth=1 https://github.com/RPi-Distro/bluez-firmware.git

echo "Copy the bluetooth firmware files to the firmware directory..."
mkdir -p $temp_dir/lib/firmware/brcm
cp bluez-firmware/debian/firmware/broadcom/BCM4345C0.hcd $temp_dir/lib/firmware/brcm/

echo "Create bluetooth firmware symbolic link..."
ln -s $temp_dir/lib/firmware/brcm/BCM4345C0.hcd $temp_dir/lib/firmware/brcm/BCM4345C0.raspberrypi,5-model-b.hcd

echo "Create cmdline.txt..."
echo "dwc_otg.lpm_enable=0 console=tty root=/dev/mmcblk0p4 rootfstype=ext4 rootwait cma=256M@256M net.ifnames=0" > $temp_dir/boot/cmdline.txt

echo "Create config.txt..."
echo -e "# If using arm64 on a Pi3, select a 64 bit kernel\narm_64bit=1\n\n# have a properly sized image\ndisable_overscan=1\n\n# Enable audio (loads snd_bcm2835)\ndtparam=audio=on" > $temp_dir/boot/config.txt

echo "Create /etc/fstab..."
cat << EOF > $temp_dir/etc/fstab
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
sed -i '1c\root:$6$xxPVR/Td5iP$/7Asdgq0ux2sgNkklnndcG4g3493kUYfrrdenBXjxBxEsoLneJpDAwOyX/kkpFB4pU5dlhHEyN0SK4eh/WpmO0::0:99999:7:::' $temp_dir/etc/shadow

cat $temp_dir/etc/shadow

echo "Set keymap to UK..."
echo "keymap=\"dvorak-uk\"" >> $temp_dir/etc/conf.d/keymaps

echo "Enable ssh for root..."
echo "PermitRootLogin yes" >> $temp_dir/etc/ssh/sshd_config

echo "Start the ssh service on boot..."
cd $temp_dir/etc/runlevels/default/
ln -s /etc/init.d/sshd sshd

echo "Unmount everything..."
cd $current_dir
umount $temp_dir/boot
umount $temp_dir/home
umount $temp_dir
rmdir $temp_dir
