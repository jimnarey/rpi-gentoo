#!/bin/bash

git clone --depth=1 --branch rpi-6.9.y https://github.com/raspberrypi/linux /build/linux
wget -c -P /build https://mirrors.edge.kernel.org/pub/linux/kernel/projects/rt/6.9/patch-6.9-rt5.patch.gz
gzip -cd /build/patch-6.9-rt5.patch.gz | patch -d /build/linux -p1 --verbose

cd /build/linux

export KERNEL=kernel_2712
export CONFIG_LOCALVERSION="-6.9-rt5-custom"

./scripts/config --disable CONFIG_VIRTUALIZATION
./scripts/config --enable CONFIG_PREEMPT_RT
./scripts/config --disable CONFIG_RCU_EXPERT
./scripts/config --enable CONFIG_RCU_BOOST
./scripts/config --set-val CONFIG_RCU_BOOST_DELAY 500

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2712_defconfig
make -j30 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image modules dtbs