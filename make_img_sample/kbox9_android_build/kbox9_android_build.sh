#!/bin/bash

# ******************************************************************************** #
# Copyright Kbox Technologies Co., Ltd. 2020-2020. All rights reserved.
# File Name: kbox9_android_build.sh
# Description: android镜像编译总调用脚本.
# Usage: bash kbox9_android_build.sh
# ******************************************************************************** #

# 脚本解释器 强制设置为 bash
if [ "$BASH" != "/bin/bash" ] && [ "$BASH" != "/usr/bin/bash" ]; then
   bash "$0" "$@"
   exit $?
fi

function error(){
    echo -e "\033[1;31m$1\033[0m"
    exit 1
}

# root权限执行此脚本
[ "${UID}" -ne 0 ] && error "请使用root权限执行"
# 默认工作目录
CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${CURRENT_DIR}" || exit
x86_workdir=$(cd "${CURRENT_DIR}"/../../../compile/ && pwd)
[ ! -e "${x86_workdir}" ] && exit

main(){
    bash 00_kbox_prepare.sh
    [ $? -ne 0 ] && error "00_kbox_prepare.sh执行失败"
    bash 01_apply_patch.sh
    [ $? -ne 0 ] && error "01_apply_patch.sh执行失败"
    bash 02_compile_aosp.sh
    [ $? -ne 0 ] && error "02_compile_aosp.sh执行失败"
}

main "$@"|tee kbox_image_build.txt
exit 0
