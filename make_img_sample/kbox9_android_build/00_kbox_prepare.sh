#!/bin/bash

# ******************************************************************************** #
# Copyright Kbox Technologies Co., Ltd. 2020-2020. All rights reserved.
# File Name: 00_kbox_prepare.sh
# Description: 源码相关准备.
# Usage: bash 00_kbox_prepare.sh
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
x86_workdir=$(cd "${CURRENT_DIR}"/../../../compile/ && pwd)
[ ! -e "${x86_workdir}" ] && exit
export GIT_SSL_NO_VERIFY=1
mkdir -p ~/bin
PATH=~/bin:$PATH
cpu_num=$(< /proc/cpuinfo grep -c "processor")

################################################################################
# Function Name: build_dependency
# Description  : 安装编译构建所需依赖。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function build_dependency(){
    apt update || exit
    apt -y install libgl1-mesa-dev g++-multilib
    apt -y install git flex bison gperf build-essential
    apt -y install tofrodos python-markdown xsltproc
    apt -y install dpkg-dev libsdl1.2-dev
    apt -y install git-core gnupg
    apt -y install zip curl zlib1g-dev gcc-multilib
    apt -y install libc6-dev-i386 libx11-dev libncurses5-dev
    apt -y install lib32ncurses5-dev x11proto-core-dev
    apt -y install libxml2-utils unzip m4
    apt -y install lib32z-dev ccache
    apt -y install libssl-dev gettext
    apt -y install python-mako
}

################################################################################
# Function Name: aosp_prepare
# Description  : 下载并清理aosp源码。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function aosp_prepare(){
    echo "---------清理并准备aosp源码----------"
    cd "${x86_workdir}" || exit
    if [ -e "aosp" ]
    then
        cd aosp || exit
        # 删除上次编译产生的目录
        rm -rf external/mesa
        rm -rf external/libdrm
        rm -rf external/llvm70
        rm -rf vendor
        # 删除纯净源码中external/mesa3d, external/libdrm, device/generic/arm64三个文件夹
        rm -rf external/mesa3d
        rm -rf external/libdrm
        rm -rf device/generic/arm64
    else
        error "---------缺少aosp源码----------"
    fi
}

################################################################################
# Function Name: replace_mesa
# Description  : 下载mesa及相关依赖，并替换到aosp源码中。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function replace_mesa(){
    echo "---------清理并准备mesa相关源码----------"
    cd "${x86_workdir}" || exit
    if [ ! -e "mesa-20.2.6" ]
    then
        error "---------缺少mesa-20.2.6相关源码----------"
    fi
    sleep 1
    cp -r ./mesa-20.2.6 "${x86_workdir}"/aosp/external/mesa

    cd "${x86_workdir}" || exit
    if [ ! -e "llvm-9.0.0.src" ]
    then
        error "---------缺少llvm-9.0.0.src相关源码----------"
    fi
    sleep 1
    cp -r ./llvm-9.0.0.src "${x86_workdir}"/aosp/external/llvm70

    cd "${x86_workdir}" || exit
    if [ ! -e "drm-libdrm-2.4.100" ]
    then
        error "---------缺少drm-libdrm-2.4.100相关源码----------"
    fi
    sleep 1
    cp -r ./drm-libdrm-2.4.100 "${x86_workdir}"/aosp/external/libdrm
}

main(){
    build_dependency
    aosp_prepare
    replace_mesa
}

main "$@"
exit 0
