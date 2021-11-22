#!/bin/bash

# ******************************************************************************** #
# Copyright Kbox Technologies Co., Ltd. 2020-2020. All rights reserved.
# File Name: kbox9_iso_build.sh
# Description: ubuntu iso镜像生成总调用脚本.
# Usage: bash kbox9_iso_build.sh
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

CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${CURRENT_DIR}" || exit
package_dir=$(cd "${CURRENT_DIR}"/../../../ && pwd)
iso_file="ubuntu-20.04.1-live-server-arm64.iso"
export iso_file

main(){
    bash kbox9_kernel.sh
    if [ -f "${package_dir}/${iso_file}" ]
    then
        bash make_iso.sh
    fi
}

main "$@"
exit 0
