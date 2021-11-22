#!/bin/bash

# ******************************************************************************** #
# Copyright Kbox Technologies Co., Ltd. 2020-2020. All rights reserved.
# File Name: kbox9_kernel.sh
# Description: kbox9内核编译构建.
# Usage: bash kbox9_kernel.sh
# ******************************************************************************** #

#set -x
# 脚本解释器 强制设置为 bash
if [ "$BASH" != "/bin/bash" ] && [ "$BASH" != "/usr/bin/bash" ]; then
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
mkdir -p "${CURRENT_DIR}"/../../../kernel/
kernel_dir=$(cd "${CURRENT_DIR}"/../../../kernel/ && pwd)
chmod 755 "${kernel_dir}"
workdir=$(cd "${CURRENT_DIR}"/../../../compile/ && pwd)
[ ! -e "${workdir}" ] && exit
cpu_num=$(< /proc/cpuinfo grep -c "processor")


# 目标OS版本，针对此版本所有的内核补丁和适配的ashmem/binder补丁放在单独的目录下面
OS_VERSION=ubuntu_20.04

################################################################################
# Function Name: install_dependency
# Description  : 安装编译构建所需依赖。
# Parameter    :
# Returns      : 0 on success, otherwise on fail
################################################################################
function install_dependency(){
    apt update || exit
    apt install -y dpkg dpkg-dev libncurses5-dev libssl-dev libpciaccess0
    apt install -y libdrm-amdgpu1 xserver-xorg-video-amdgpu
    apt install -y build-essential
    apt install -y libncurses5-dev openssl libssl-dev
    apt install -y pkg-config
    apt install -y bison
    apt install -y flex
    apt install -y libelf-dev
}

################################################################################
# Function Name: modify_config
# Description  : .config文件修改。
# Parameter    :
# Returns      : 0 on success, otherwise on fail
################################################################################
function modify_config(){
    < .config grep -v "#"|grep -w "${1}"
    if [ $? -eq 0 ]
    then
        sed -i "s|${1}=.*|${1}=${2}|g" .config
    else
        echo "${1}=${2}" >> .config
    fi
    echo ">> $(< .config grep -v "#"|grep -w "${1}")"
}

################################################################################
# Function Name: build_init
# Description  : ubuntu内核源码准备。
# Parameter    :
# Returns      : 0 on success, otherwise on fail
################################################################################
function build_init(){
    echo "-------------------解压内核--------------------"
    cd "${kernel_dir}" || exit
    rm -rf linux-5.4.0
    if [ ! -e "linux_5.4.0.orig.tar.gz" ]
    then
        error "-------------------缺少linux_5.4.0.orig.tar.gz--------------------"
    fi

    if [ ! -e "linux_5.4.0-26.30.diff.gz" ]
    then
        error "-------------------缺少linux_5.4.0-26.30.diff.gz--------------------"
    fi

    if [ ! -e "linux_5.4.0-26.30.dsc" ]
    then
        error "-------------------缺少linux_5.4.0-26.30.dsc--------------------"
    fi

    dpkg-source -x linux_5.4.0-26.30.dsc || exit
}

################################################################################
# Function Name: apply_patch
# Description  : 转码及内核补丁合入。
# Parameter    :
# Returns      : 0 on success, otherwise on fail
################################################################################
function apply_patch(){
    echo "------------合入转码补丁及内核补丁------------------"
    cp -r "${workdir}"/src/patchForKernel/${OS_VERSION} "${kernel_dir}"/linux-5.4.0/ || exit
    cd "${kernel_dir}"/linux-5.4.0/ || exit
    echo "*--patching ubuntu-5.4.0-18.22.patch"
    patch -p1 < ${OS_VERSION}/kernel/ubuntu-5.4.0-18.22.patch || exit
    echo "*--5.4.30_mmap.patch"
    patch -p1 < ${OS_VERSION}/kernel/5.4.30_mmap.patch || exit
    echo "*--kernel.patch"
    patch -p1 < ${OS_VERSION}/kernel/kernel.patch || exit
    echo "*--pid_max_limit.patch"
    patch -p1 < ${OS_VERSION}/kernel/pid_max_limit.patch || exit
}

################################################################################
# Function Name: build_install_kernel
# Description  : 内核及内核模块编译。
# Parameter    :
# Returns      : 0 on success, otherwise on fail
################################################################################
function build_install_kernel(){
    echo "---------编译及安装kernel---------"
    echo "---------内核编译---------"
    cd "${kernel_dir}"/linux-5.4.0/ || exit
    (echo -e \'\\0x65\'; echo -e \'\\0x79\') | make menuconfig
    sleep 1
    [ ! -e ".config" ] && error "config file not found"
    modify_config "CONFIG_BINFMT_MISC" "y"
    modify_config "CONFIG_EXAGEAR_BT" "y"
    modify_config "CONFIG_CHECKPOINT_RESTORE" "y"
    modify_config "CONFIG_PROC_CHILDREN" "y"
    modify_config "CONFIG_VFAT_FS" "y"
    modify_config "CONFIG_INPUT_UINPUT" "y"
    modify_config "CONFIG_HISI_PMU" "y"

    echo "---------内核编译---------"
    make clean && make -j"${cpu_num}"
    [ $? -ne 0 ] && error "内核编译失败"
    echo "---------内核模块编译---------"
    make modules_install
    [ $? -ne 0 ] && error "内核模块编译失败"
    mkdir -p "${kernel_dir}"/output/boot
    INSTALL_PATH="${kernel_dir}"/output/boot/ make zinstall
    INSTALL_MOD_PATH="${kernel_dir}"/output/ make INSTALL_MOD_STRIP=1 modules_install -j8
    cp "${workdir}"/exagear/ExaGear_ARM32-ARM64/ubt_a32a64 "${kernel_dir}"/output/
}

################################################################################
# Function Name: build_ashmem_binder
# Description  : ashmem和binder两个内核模块编译。
# Parameter    :
# Returns      : 0 on success, otherwise on fail
################################################################################
function build_ashmem_binder(){
    cd "${package_dir}" || exit
    [ -e "${kernel_dir}/ashmem" ] && rm -rf "${kernel_dir}"/ashmem
    [ -e "${kernel_dir}/binder" ] && rm -rf "${kernel_dir}"/binder
    cp -r ashmem "${kernel_dir}"/
    cp -r binder "${kernel_dir}"/
    cd "${kernel_dir}" || exit
    patch -p1 < "${workdir}"/src/patchForKernel/"${OS_VERSION}"/ashmem_binder/ashmem.patch || exit
    patch -p1 < "${workdir}"/src/patchForKernel/"${OS_VERSION}"/ashmem_binder/binder.patch || exit
    echo "--------编译asdmem--------"
    cd "${kernel_dir}"/ashmem || exit
    make clean
    make -C "${kernel_dir}"/linux-5.4.0 V=0 M="${kernel_dir}"/ashmem
    [ $? -ne 0 ] && error "asdmem compile failed"
    cp ashmem_linux.ko "${kernel_dir}"/output/
    echo "---------编译binder--------"
    cd "${kernel_dir}"/binder || exit
    make clean
    make -C "${kernel_dir}"/linux-5.4.0 V=0 M="${kernel_dir}"/binder
    [ $? -ne 0 ] && error "binder compile failed"
    cp aosp9_binder_linux.ko "${kernel_dir}"/output/
}

main(){
    install_dependency
    build_init
    apply_patch
    build_install_kernel
    build_ashmem_binder
}

main "$@"
exit 0
