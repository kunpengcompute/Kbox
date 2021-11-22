#!/bin/bash
set -e
# ******************************************************************************** #
# Copyright Kbox Technologies Co., Ltd. 2020-2020. All rights reserved.
# File Name: unpack.sh
# Description: Unpack package.
# Usage: bash unpack.sh
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
chmod -R 750 ./*
package_dir=$(cd "${CURRENT_DIR}"/../../ && pwd)

################################################################################
# Function Name: clean
# Description  : Clean Files.
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function clean(){
    cd "${package_dir}" || exit
    rm -rf patches
    rm -rf product_prebuilt
    rm -rf image
    rm -rf Patch_*.tar.gz
    rm -rf Patch_*.tar.gz.asc
    rm -rf ExaGear_ARM32-ARM64_*.tar.gz
    rm -rf ExaGear_ARM32-ARM64_*.tar.gz.asc
}

################################################################################
# Function Name: unpack
# Description  : Unpack package.
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function unpack(){
    cd "${package_dir}" || exit
    BoostKit_package=$(ls BoostKit-kbox_*.zip)
    unzip "${BoostKit_package}"
    binary_packages=$(ls Kbox-*-*-binary.zip)
    unzip "${binary_packages}"
}

################################################################################
# Function Name: prepare_dir
# Description  : Move the file to the corresponding folder.
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function prepare_dir(){
    cd "${package_dir}" || exit
    # 准备patch文件
    rm -rf compile/src
    mkdir -p compile/src
    mv Kbox-AOSP9/patchForAndroid compile/src/
    mv Kbox-AOSP9/patchForKernel compile/src/
    # 准备二进制文件
    rm -rf compile/product_prebuilt
    rm -rf compile/products
    mv product_prebuilt compile/
    mv products compile/
    # 准备exagear文件
    rm -rf compile/exagear
    mkdir -p compile/exagear
    cp ExaGear_ARM32-ARM64_*.tar.gz compile/exagear/
    cp Patch_*.tar.gz compile/exagear/
    cd compile/exagear/ || exit
    tar -zxvf ExaGear_ARM32-ARM64_*.tar.gz
    rm -rf ExaGear_ARM32-ARM64_*.tar.gz
    mv ExaGear_ARM32-ARM64_* ExaGear_ARM32-ARM64
    tar -zxvf Patch_*.tar.gz
    rm -rf Patch_*.tar.gz
    mv Patch_* Patch
}

################################################################################
# Function Name: main
# Description  : main function
# Parameter    : command line params
# Returns      : 0 on success, otherwise on fail
################################################################################
function main(){
    unpack
    prepare_dir
}

main "$@"
exit 0
