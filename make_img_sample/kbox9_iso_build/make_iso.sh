#!/bin/bash

# ******************************************************************************** #
# Copyright Kbox Technologies Co., Ltd. 2020-2020. All rights reserved.
# File Name: make_iso.sh
# Description: ubuntu iso镜像制作.
# Usage: bash make_iso.sh
# ******************************************************************************** #

#set -x
# 脚本解释器 强制设置为 bash
if [ "$BASH" != "/bin/bash" ] && [ "$BASH" != "/usr/bin/bash" ]
then
   bash "$0" "$@"
   exit $?
fi

function error(){
    echo -e "\033[1;31m$1\033[0m"
    exit 1
}

CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${CURRENT_DIR}" || exit
package_dir=$(cd "${CURRENT_DIR}"/../../../ && pwd)
[ ! -e "${CURRENT_DIR}/../../../kernel/output/" ] && exit
output_dir=$(cd "${CURRENT_DIR}"/../../../kernel/output/ && pwd)
[ ! -e "${CURRENT_DIR}/../../../iso_old/" ] && rm -rf "${CURRENT_DIR}"/../../../iso_old
mkdir -p "${CURRENT_DIR}"/../../../iso_old/
iso_dir_old=$(cd "${CURRENT_DIR}"/../../../iso_old/ && pwd)
iso_name="${iso_file:-ubuntu-20.04.1-live-server-arm64.iso}"

################################################################################
# Function Name: check_mount
# Description  : 检查并卸载旧ubuntu镜像的挂载。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function check_mount(){
    mount |grep "${iso_dir_old}" > /dev/null 2>&1
    [ $? -eq 0 ] && umount "${iso_dir_old}"
}

################################################################################
# Function Name: install_dependency
# Description  : 安装ubuntu iso镜像制作所需依赖。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function install_dependency(){
    apt update || exit
    apt install -y squashfs-tools genisoimage
    apt install -y cifs-utils
}

################################################################################
# Function Name: prepare
# Description  : 将ubuntu iso镜像安装启动后需要用到的文件预置入iso镜像。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function prepare(){
    cd "${package_dir}" || exit
    rm -rf ARM64_demo.iso
    chmod 755 "${iso_dir_old}"
    check_mount
    mount -o loop "${iso_name}" "${iso_dir_old}"
    rm -rf iso_new
    cp -rf "${iso_dir_old}" iso_new
    umount "${iso_dir_old}"
    rm -rf "${iso_dir_old}"
    cd iso_new || exit
    unsquashfs ./casper/filesystem.squashfs || exit
    mkdir -p squashfs-root/usr/new_file
    mkdir -p squashfs-root/usr/new_file/image
    cp -rf "${output_dir}"/boot squashfs-root/usr/new_file/
    cp -rf "${output_dir}"/lib squashfs-root/usr/new_file/
    cp -rf "${output_dir}"/ubt_a32a64 squashfs-root/usr/new_file/
    cp -rf "${output_dir}"/ashmem_linux.ko squashfs-root/usr/new_file/
    cp -rf "${output_dir}"/aosp9_binder_linux.ko squashfs-root/usr/new_file/
    cp -rf "${package_dir}"/android.tar squashfs-root/usr/new_file/image/
    cp -rf "${package_dir}"/Kbox-AOSP9/deploy_scripts squashfs-root/usr/new_file/
    cp -rf "${CURRENT_DIR}"/rc-local.service squashfs-root/etc/systemd/system/
    cp -rf "${CURRENT_DIR}"/rc.local squashfs-root/etc/
    chmod 750 squashfs-root/etc/rc.local
    chmod 750 squashfs-root/etc/systemd/system/rc-local.service
    cp -rf "${CURRENT_DIR}"/start.sh squashfs-root/usr/new_file/
    cp -rf "${package_dir}"/docker_deb squashfs-root/usr/new_file/
    cp -rf "${package_dir}"/lxcfs_deb squashfs-root/usr/new_file/
}

################################################################################
# Function Name: build_ios
# Description  : 打包生成ubuntu iso镜像。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function build_ios(){
    cd "${package_dir}"/iso_new || exit
    chroot squashfs-root dpkg-query -W --showformat='${Package} ${Version}\n' | sudo tee install/filesystem.manifest
    rm casper/filesystem.squashfs
    mksquashfs squashfs-root casper/filesystem.squashfs || exit
    printf "$(sudo du -sx --block-size=1 squashfs-root | cut -f1)" > install/filesystem.size
    sudo find . -type f -print0 | xargs -0 md5sum | grep -v "\./md5sum.txt" > md5sum.txt
    genisoimage -r -V "ARM64_demo" -o "${package_dir}"/ARM64_demo.iso -J -joliet-long -cache-inodes -c boot/boot.cat -e boot/grub/efi.img -no-emul-boot .
    cd "${package_dir}" || exit
    rm -rf iso_new
}

################################################################################
# Function Name: end_of_build
# Description  : 生成MD5文件及清理。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function end_of_build(){
    cd "${package_dir}" || exit
    md5sum ARM64_demo.iso > ARM64_demo.iso.md5
    echo "${package_dir}"/ARM64_demo.iso
    echo "---------End----------"
}

main(){
    install_dependency
    prepare
    build_ios
    end_of_build
}

main "$@"
exit 0
