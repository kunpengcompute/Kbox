#!/bin/bash

# ******************************************************************************** #
# Copyright Kbox Technologies Co., Ltd. 2020-2020. All rights reserved.
# File Name: 02_compile_aosp.sh
# Description: android镜像编译及打包.
# Usage: bash 02_compile_aosp.sh
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
x86_workdir=$(cd "${CURRENT_DIR}"/../../Kbox_carrier/ && pwd)
[ ! -e "${x86_workdir}" ] && exit
cpu_num=$(< /proc/cpuinfo grep -c "processor")
hostmemory=$(< /proc/meminfo head -n1|awk '{print $2}')
hostmemory=$((hostmemory/1024/1024/4))
if [ "${cpu_num}" -gt "${hostmemory}" ]
then
    cpu_num=${hostmemory}
    echo "java limit j${hostmemory}"
fi

################################################################################
# Function Name: aosp_compile
# Description  : aosp编译。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function aosp_compile(){
    echo "-----------aosp源码编译-----------"
    cd "${x86_workdir}"/aosp || exit
    [ -e "${x86_workdir}" ] && rm -rf "${x86_workdir}"/aosp/out
    [ -e "${x86_workdir}" ] && rm -rf "${x86_workdir}"/aosp/create-package.sh
    source build/envsetup.sh || exit
    lunch kbox_arm64-userdebug || exit
    export LC_ALL=C
    echo "2" > /proc/sys/kernel/randomize_va_space  #可信需求
    make clean && make -j${cpu_num}
    [ $? -ne 0 ] && error "aosp编译失败" && make clean
    echo "---------Success----------"
}

################################################################################
# Function Name: create_package
# Description  : 镜像打tar包。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function create_package(){
    echo "-----------生成Android镜像包-----------"
    cp "${CURRENT_DIR}"/create-package.sh "${x86_workdir}"/aosp/
    cd "${x86_workdir}"/aosp || exit
    chmod 550 create-package.sh
    ./create-package.sh "${x86_workdir}"/aosp/out/target/product/arm64/ramdisk.img "${x86_workdir}"/aosp/out/target/product/arm64/system.img
    [ $? -ne 0 ] && error "生成Android镜像失败"
    echo "---------Success----------"
}

################################################################################
# Function Name: end_of_build
# Description  : 生成MD5文件及清理。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function end_of_build(){
    cd "${x86_workdir}"/aosp || exit
    md5sum android.tar > android.tar.md5
    echo "${x86_workdir}/aosp/android.tar"
    echo "---------End----------"
}

main(){
    aosp_compile
    create_package
    end_of_build
}

main "$@"
exit 0
