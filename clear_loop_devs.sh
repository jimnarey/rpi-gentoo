#!/bin/bash

# Clears loop devices and device mappings for a provided image file

if [ "$#" -ne 1 ]; then
    echo "Incorrect number of arguments supplied."
    echo "Usage: $0 <image_file_name>"
    exit 1
fi

filename=$1

for loop_device in $(losetup -j $filename | cut -d: -f1); do
    echo "Deleting device mappings for $loop_device..."
    kpartx -d $loop_device
done

for loop_device in $(losetup -j $filename | cut -d: -f1); do
    echo "Detaching $loop_device..."
    losetup -d $loop_device
done
