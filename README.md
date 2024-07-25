# Raspberry Pi 5 Gentoo Image Builder

The scripts in this repository can be used to create a Gentoo installation for the Raspberry Pi 5, optionally including a real-time kernel (v6.9).

## Requirements

These scripts should work on pretty much any Linux distribution running on x86/amd64 but were tested on Ubuntu 22. Additionally, Docker and the following command line tools are required:
- `git`
- `kpartx`
- `qemu-aarch64-static`

## Instructions

Clone the repository.

To create a bootable Gentoo image which can be flashed to an SD card, run:

```
sudo ./build-image.sh pi-gentoo.img
```

This will create an image approx 12GB in size with a 2GB swap partition, a 2GB home partition and an 8GB root partition. Alternative values can be set (in MB) with the `-s`, `-u` and `-r` options. 

Note that the minimum size of the root partition, required for the initial `emerge-webrsync` run is not much less than 8GB. If it is set too small the script will fail.

The image contains a complete but basic Gentoo installation with OpenRC. Any additional packages needed will have to be installed on the Pi itself with `emerge`.

## Helper scripts

The image includes a `set-datetime.sh` script. Installing packages requires the date and time to be set and the image doesn't include any NTP packages.

Within `/root/install-scripts` there is an `install-python.sh` script which installs pyenv and Python 10 (the latest version for which there is compatible PyPy version).

## Real-time kernel

A Docker container is used to apply the real-time patches to the kernel source, set the required config options and compile the kernel. To build the container image run:

```
make build
```

To compile the kernel run:

```
make run
```

To remove the cloned kernel source and any build artifacts, run:

```
make clean
```

To install the compiled kernel into an image already built with `build-image.sh` run:

```
sudo add-kernel.sh ./pi-gentoo.img
```

## Limitations

The chief one is that this is designed for the Raspberry Pi 5 only. It would not take a great deal of adaptation to get the scripts working for other Raspberry Pi versions, especially those capable of running (or requiring) an arm64 OS.

The `build-image.sh` script doesn't install any packages. It creates and image and copies the base installation files into it, then uses `qemu-aarch64-static` to run `emerge-webrsync` within a chroot which downloads the Gentoo repository and enables packages to be installed.

However, things start to unravel when attempting to install packages using this method as Gentoo, by default, compiles packages at the point of installation and the script is running on x86. This is [probably fixable](https://forums.gentoo.org/viewtopic-t-1092314-start-0.html).

## To do

- Fix issue where the `build-image.sh` script intermittently leaves orphan loop devices on the system. These are harmless but pollute the output of commands such as `lsblk`. They are caused by the final part of the script which creates the chroot and mounts several pseudo filesystems within it.
- The `-j` options passed to `make` when the kernel is compiled and modules installed (`Dockerfile` and `add-kernel.sh`) are hardcoded. The one that really matters is the former, which is set to `-j30` for a machine which reports 20 from `nproc`.
- The version of the Gentoo stage3 file downloaded by the script is not pinned.
- The stage3 file is cached but the cloned Raspberry Pi firmware and non-free firmware repositories are not, so are re-cloned on each run (and not pinned).
- There isn't an option to specify additional config options when the kernel is compiled, or re-compile if options are changed without starting from scratch.
- The kernel and RT patch versions are hardcoded.
- Add better usage output to both scripts.
- Some more trivial things included in comments at the top of `build-image.sh`.


