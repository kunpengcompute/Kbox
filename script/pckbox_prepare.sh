#!/bin/bash
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
cd "${CURRENT_DIR}" || exit 1
kernel_r=$(uname -r)
lxcfs_path="/var/lib/lxcfs"
cpu_vendor="0x48"

function set_a32a64(){
    echo "------------配置转码------------"
    cpu_name=$(< /proc/cpuinfo grep implementer|head -n1|awk '{print $NF}')
    if [ "${cpu_vendor}" != "${cpu_name}" ]; then
        return 0
    fi
    [ -e "/proc/sys/fs/binfmt_misc/ubt_a32a64" ] && echo -1 > /proc/sys/fs/binfmt_misc/ubt_a32a64
    if [ -x /opt/exagear/ubt_a32a64 ]; then
        echo ":ubt_a32a64:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\xfe\xff\xff\xff:/opt/exagear/ubt_a32a64:POCF" > /proc/sys/fs/binfmt_misc/register
        < /proc/sys/fs/binfmt_misc/ubt_a32a64 grep "enabled"
        [ $? -ne 0 ] && error "转码注册失败"
        return 0
    fi
    echo ":ubt_a32a64:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\xfe\xff\xff\xff:/opt/exagear/ubt_a32a64:POCF" > /proc/sys/fs/binfmt_misc/register
    < /proc/sys/fs/binfmt_misc/ubt_a32a64 grep "enabled"
    [ $? -ne 0 ] && error "转码注册失败"
}

function insmod_ashmem_binder(){
    echo "-------安装ashmem、binder模块--------"
    [ -e "/dev/binder" ] && rmmod binder_linux
    ls /opt/kernel_modules/binder |grep -w binder_linux.ko
    if [ $? -ne 0 ]
    then
        cd /opt/kernel_modules/binder || exit 1
        make clean
        make -C /lib/modules/"$(uname -r)"/build/ V=0 M=/opt/kernel_modules/binder
        [ $? -ne 0 ] && error "binder compile failed"
        insmod binder_linux.ko num_devices=3
    else
    cd /opt/kernel_modules/binder || exit 1
    insmod binder_linux.ko num_devices=3
    if [ $? -ne 0 ]
    then
        cd /opt/kernel_modules/binder || exit 1
            make clean
            make -C /lib/modules/"$(uname -r)"/build/ V=0 M=/opt/kernel_modules/binder
            [ $? -ne 0 ] && error "binder compile failed"
            insmod binder_linux.ko num_devices=3
    fi
    fi
    ls /opt/kernel_modules/ashmem |grep -w ashmem_linux.ko
    if [ $? -ne 0 ]
    then
        cd /opt/kernel_modules/ashmem || exit 1
        make clean
        make -C /lib/modules/"$(uname -r)"/build/ V=0 M=/opt/kernel_modules/ashmem
        [ $? -ne 0 ] && error "asdmem compile failed"
        insmod ashmem_linux.ko
    else
    cd /opt/kernel_modules/ashmem || exit 1
    insmod ashmem_linux.ko
    if [ $? -ne 0 ]
        then
            cd /opt/kernel_modules/ashmem || exit 1
            make clean
            make -C /lib/modules/"$(uname -r)"/build/ V=0 M=/opt/kernel_modules/ashmem
            [ $? -ne 0 ] && error "asdmem compile failed"
            insmod ashmem_linux.ko
    fi

    fi
    ls /opt/kernel_modules/smc_dri |grep -w smc_dri.ko
    if [ $? -ne 0 ]
    then
        cd /opt/kernel_modules/smc_dri || exit 1
        make clean
        make -C /lib/modules/"$(uname -r)"/build/ V=0 M=/opt/kernel_modules/smc_dri
        [ $? -ne 0 ] && error "smc_dri compile failed"
        insmod smc_dri.ko
    else 
    cd /opt/kernel_modules/smc_dri || exit 1
    insmod smc_dri.ko
        if [ $? -ne 0 ]
        then
            cd /opt/kernel_modules/smc_dri || exit 1
            make clean
            make -C /lib/modules/"$(uname -r)"/build/ V=0 M=/opt/kernel_modules/smc_dri
            [ $? -ne 0 ] && error "smc_dri compile failed"
            insmod smc_dri.ko
        fi
    fi
    lsmod |grep -w binder_linux
    [ $? -ne 0 ] && error "binder安装失败"
    lsmod |grep -w ashmem_linux
    [ $? -ne 0 ] && error "ashmem安装失败"
    lsmod |grep -w smc_dri
    [ $? -ne 0 ] && error "smc_dri安装失败"
}

function check_lxcfs(){
    local lxcfs_status
    lxcfs_status=$(systemctl is-active lxcfs.service)
    if [ "${lxcfs_status}" != "active" ]
    then
        systemctl restart lxcfs.service
    fi
    if [ ! -f "${lxcfs_path}/proc/cpuinfo" ]
    then
        rm -rf ${lxcfs_path:?}/*
        systemctl restart lxcfs.service
        [ $? -ne 0 ] && error "Failed to restart the lxcfs service. Check the lxcfs.service."
    fi
    echo "lxcfs.service is $(systemctl is-active lxcfs.service)"
}

main(){
    set_a32a64
    check_lxcfs
    insmod_ashmem_binder
}

main "$@"
exit 0
