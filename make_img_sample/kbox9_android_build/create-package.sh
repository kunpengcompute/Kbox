#!/bin/bash

# ******************************************************************************** #
# Copyright Kbox Technologies Co., Ltd. 2020-2020. All rights reserved.
# File Name: create-package.sh
# Description: android镜像打tar包.
# Usage: create-package.sh
# ******************************************************************************** #

set -ex

ramdisk=$1
system=$2
destdir=$PWD

if [ -z "$ramdisk" ] || [ -z "$system" ]; then
    echo "Usage: $0 <ramdisk> <system image>"
    exit 1
fi

workdir=$(mktemp -d)
rootfs=$workdir/rootfs

mkdir -p "$rootfs"

# Extract ramdisk and preserve ownership of files
(cd "${rootfs}" ; cat "$ramdisk" | gzip -d | sudo cpio -i)

mkdir "$workdir"/system
sudo mount -o loop,ro "$system" "$workdir"/system
sudo cp -ar "$workdir"/system/* "$rootfs"/system
sudo umount "$workdir"/system

# FIXME
sudo chmod +x "$rootfs"/kbox-init.sh

if [ -e android.tar ]; then
    DATE=$(date +%F_%R)
    SAVETO=android-old-$DATE.tar

    echo "#########################################################"
    echo "# WARNING: Old android.tar still exists.                 "
    echo "#          Moving it to $SAVETO.                         "
    echo "#########################################################"

    mv android.tar "$SAVETO"
fi

#sudo mksquashfs $rootfs $destdir/android.img -comp xz -no-xattrs
cd "$rootfs"
sudo tar --numeric-owner -cf "$destdir"/android.tar ./
sudo chown "$USER":"$USER" "$destdir"/android.tar

cd "$destdir" 
sudo rm -rf "$workdir"
