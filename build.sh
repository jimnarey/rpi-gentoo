#!/bin/bash

# A script to create a Gentoo installation SD for the Raspberry Pi 5

# It can be used for previous versions but the --pagesize option for
# the mkswap command should be changed to 4096 for the Raspberry Pi 4
# or lower.

# It reproduces the instructions here: https://wiki.gentoo.org/wiki/Raspberry_Pi_Install_Guide#Tidy_up_and_Test_in_the_Pi
# It downloads the latest Gentoo tar from here: https://distfiles.gentoo.org/releases/arm64/autobuilds/

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as superuser (root)."
    exit 1
fi

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <block_device> <home_partition_size_in_GB>"
    exit 1
fi

block_device=$1
home_partition_size=$2

echo "Creating a GPT partition table on the block device..."
echo -e "g\nw\n" | fdisk $block_device

echo "Creating a 256MB partition at the start of the device..."
echo -e "n\n\n\n+256M\nw\n" | fdisk $block_device

echo "Creating the swap partition..."
echo -e "n\n\n\n+8G\nw\n" | fdisk $block_device

echo "Creating the home partition with size passed as argument..."
echo -e "n\n\n\n+${home_partition_size}G\nw\n" | fdisk $block_device

echo "Creating the root partition taking up all remaining space..."
echo -e "n\n\n\n\nw\n" | fdisk $block_device

echo "Setting the type of the first partition to FAT32..."
echo -e "t\n1\nb\nw\n" | fdisk $block_device

echo "Setting the type of the second partition to swap..."
echo -e "t\n2\n82\nw\n" | fdisk $block_device

echo "Creating a FAT32 filesystem on the first partition..."
mkfs -t vfat $block_device"1"

echo "Creating an ext4 filesystem in the home partition..."
mkfs -t ext4 $block_device"3"

echo "Creating an ext4 filesystem in the root partition..."
mkfs -t ext4 $block_device"4"

echo "Creating a swap filesystem in the swap partition..."
mkswap --pagesize 16384 $block_device"2"

echo "Creating a temporary directory..."
temp_dir=$(mktemp -d)

echo "Mounting the root partition to the temporary directory..."
mount $block_device"4" $temp_dir

echo "Changing directory to the root mount point..."
cd $temp_dir

echo "Downloading the stage3 file..."
stage3_file=$(wget -qO- https://distfiles.gentoo.org/releases/arm64/autobuilds/current-stage3-arm64-openrc/latest-stage3-arm64-openrc.txt | grep '^stage3')

echo "Downloading the stage3 file from the specified URL..."
wget -q "https://distfiles.gentoo.org/releases/arm64/autobuilds/current-stage3-arm64-openrc/$stage3_file"

echo "Extracting the stage3 file..."
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

echo "Mounting the boot and home partitions..."
mount $block_device"1" /mnt/gentoo/boot
mount $block_device"3" /mnt/gentoo/home

echo "Clone RPi firmware repository..."
git clone --depth=1 https://github.com/raspberrypi/firmware

echo "Copy the firmware files to the boot partition..."
cp -a firmware/boot/* /mnt/gentoo/boot/

echo "Copy the kernel modules to the root partition..."
cp -a firmware/modules /mnt/gentoo/lib/

echo "Clone the RPi nonfree firmware repository..."
git clone --depth=1 https://github.com/RPi-Distro/firmware-nonfree.git

echo "Create nonfree firmware directory..."
mkdir -p /mnt/gentoo/lib/firmware/brcm

echo "Copy the nonfree firmware files to the nonfree firmware directory..."
cp firmware-nonfree/debian/config/brcm80211/cypress/cyfmac43455-sdio-standard.bin /mnt/gentoo/lib/firmware/brcm/brcmfmac43455-sdio.bin
cp firmware-nonfree/debian/config/brcm80211/cypress/cyfmac43455-sdio.clm_blob /mnt/gentoo/lib/firmware/brcm/brcmfmac43455-sdio.clm_blob
cp firmware-nonfree/debian/config/brcm80211/brcm/brcmfmac43455-sdio.txt /mnt/gentoo/lib/firmware/brcm/

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
cp bluez-firmware/debian/firmware/broadcom/BCM4345C0.hcd /mnt/gentoo/lib/firmware/brcm/

echo "Create bluetooth firmware symbolic link..."
ln -s /mnt/gentoo/lib/firmware/brcm/BCM4345C0.hcd /mnt/gentoo/lib/firmware/brcm/BCM4345C0.raspberrypi,5-model-b.hcd

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
sed -i '1c\root:$6$xxPVR/Td5iP$/7Asdgq0ux2sgNkklnndcG4g3493kUYfrrdenBXjxBxEsoLneJpDAwOyX/kkpFB4pU5dl' $temp_dir/etc/shadow

echo "Set keymap to UK..."
echo "keymap=\"dvorak-uk\"" >> $temp_dir/etc/conf.d/keymaps

echo "Enable ssh for root..."
echo "PermitRootLogin yes" >> $temp_dir/etc/ssh/sshd_config

echo "Start the ssh service on boot..."
cd $temp_dir/etc/runlevels/default/
ln -s /etc/init.d/sshd sshd

echo "Unmount everything..."
umount $temp_dir/boot
umount $temp_dir/home
umount $temp_dir

