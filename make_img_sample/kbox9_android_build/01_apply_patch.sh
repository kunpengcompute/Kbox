#!/bin/bash

# ******************************************************************************** #
# Copyright Kbox Technologies Co., Ltd. 2020-2020. All rights reserved.
# File Name: 01_apply_patch.sh
# Description: 合入相关修改补丁及源码.
# Usage: bash 01_apply_patch.sh
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
x86_workdir=$(cd "${CURRENT_DIR}"/../../Kbox_carrier/ && pwd)
[ ! -e "${x86_workdir}" ] && exit

################################################################################
# Function Name: apply_exagear
# Description  : 合入转码补丁及文件。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function apply_exagear(){
    echo "---------合入转码补丁----------"
    [ ! -e "${x86_workdir}/exagear/Patch" ] && error "转码补丁目录${x86_workdir}/exagear/Patch未找到"
    cd "${x86_workdir}"/aosp/ || exit 
    rm -rf vendor
    echo "*--patching android-9.0.0_r55.patch"
    patch -p1 < "${x86_workdir}"/exagear/Patch/Android/android-9.0.0_r55-docker/android-9.0.0_r55.patch || exit
    # aosp目录中没有vendor目录，直接将vendor目录拷贝到aosp源码下
    cp -r "${x86_workdir}"/exagear/Patch/Android/android-9.0.0_r55-docker/vendor "${x86_workdir}"/aosp/ || exit
    echo "---------Success----------"
}

################################################################################
# Function Name: apply_patch
# Description  : 合入kbox aosp补丁。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function apply_patch(){
    local patche_nums
    local patch
    local patch_name
    local patch_dir
    echo "---------合入kbox aosp补丁----------"
    [ ! -e "${x86_workdir}/src/patchForAndroid" ] && error "kbox aosp补丁目录${x86_workdir}/src/patchForAndroid未找到"
    cd "${x86_workdir}"/src/patchForAndroid || exit
    # 获取补丁数字编号列表并排序
    patche_nums=$(ls *.patch|cut -d '.' -f1|awk -F '-' '{print $NF}'|sort -n)
    for patch_num in ${patche_nums}
    do
        patch=$(ls "${x86_workdir}"/src/patchForAndroid/*"${patch_num}".patch)
        echo "*--patching $(basename "${patch}")"
        # 去除后缀和数字编号的补丁名称
        patch_name=$(basename "${patch%-*}")
        # 补丁名中带的目录路径
        patch_dir=${patch_name//-/\/}
        [ ! -e "${x86_workdir}/aosp/${patch_dir}" ] && mkdir -p "${x86_workdir}"/aosp/"${patch_dir}"
        cd "${x86_workdir}"/aosp/"${patch_dir}" || exit
        patch -p1 < "${patch}" || exit
    done
    echo "---------Success----------"
}

################################################################################
# Function Name: product_prebuilt
# Description  : 合入kbox自研二进制相关源码及补丁。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function product_prebuilt(){
    echo "---------合入二进制内容补丁----------"
    cp -r "${x86_workdir}"/product_prebuilt "${x86_workdir}"/aosp/ || exit
    mkdir -p "${x86_workdir}"/aosp/vendor/kbox
    chmod -R 700 "${x86_workdir}"/aosp/vendor/kbox
    cp -r "${x86_workdir}"/products "${x86_workdir}"/aosp/vendor/kbox || exit
    echo "---------Success----------"
}

main(){
    apply_exagear
    apply_patch
    product_prebuilt
}

main "$@"
exit 0
