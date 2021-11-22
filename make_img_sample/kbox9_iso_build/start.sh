#!/bin/bash

# ******************************************************************************** #
# Copyright Kbox Technologies Co., Ltd. 2020-2020. All rights reserved.
# File Name: start.sh
# Description: ubuntu iso镜像安装启动后环境部署脚本.
# Usage: bash start.sh
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
new_file_dir="/usr/new_file"
lxcfs_path="/var/lib/lxcfs"
kernel_r=$(uname -r)

################################################################################
# Function Name: install_docker
# Description  : 安装预置的docker-*.tgz包。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function install_docker(){
    local docker_info_StorageDriver
    cd ${new_file_dir}/docker_deb || exit
    tar xvpf docker-*.tgz
    cp -p docker/* /usr/bin
    cat >/usr/lib/systemd/system/docker.service <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.com
After=network.target docker.socket
[Service]
Type=notify
EnvironmentFile=-/run/flannel/docker
WorkingDirectory=/usr/local/bin
ExecStart=/usr/bin/dockerd -H tcp://0.0.0.0:4243 -H unix:///var/run/docker.sock --selinux-enabled=false --log-opt max-size=1g
ExecReload=/bin/kill -s HUP $MAINPID
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
# Uncomment TasksMax if your systemd version supports it.
# Only systemd 226 and above support this version.
#TasksMax=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl restart docker
    systemctl enable docker

    docker_info_StorageDriver=$(docker info |grep "Storage Driver" | awk '{print $3}')
    if [ "${docker_info_StorageDriver}" = "overlay2" ]
    then
        echo "Storage Driver: ${docker_info_StorageDriver} ,不需要修改."
    else
        echo "DOCKER_OPTS= -s overlay2" >> /etc/default/docker
        systemctl restart docker
    fi
}

################################################################################
# Function Name: install_kernel
# Description  : 新ubuntu内核安装。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function install_kernel(){
    if [ "${kernel_r}" != "5.4.30" ]
    then
        install_docker
        echo -e "\033[32m内核安装更换，系统将会重启\033[0m"
        < /boot/grub/grub.cfg grep "Ubuntu, with Linux"|awk -F \' '{print i++ ":"$2}'|grep -v "recovery mode"|grep -w "5.4.30$" > /dev/null 2>&1
        if [ $? -ne 0 ]
        then
            cd ${new_file_dir} || exit
            cp -r boot/* /boot/
            cp -r lib/* /lib/
            mkinitramfs -o /boot/initrd.img-5.4.30 5.4.30
        fi
        cd /boot/grub || exit
        grub_default=$(< /boot/grub/grub.cfg grep "Ubuntu, with Linux"|awk -F \' '{print i++ ":"$2}'|grep -v "recovery mode"|grep -w "5.4.30$"|awk -F ':' '{print $1}')
        sed -i "s/GRUB_DEFAULT=.*/GRUB_DEFAULT=\"1\> ${grub_default}\"/g" /etc/default/grub
        sed -i "s/GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/g" /etc/default/grub
        sed -i "s/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"cgroup_enable=memory swapaccount=1\"/g" /etc/default/grub
        sudo update-grub2
        optimize_conf
        reboot
    fi
        systemctl daemon-reload
        systemctl restart docker
        systemctl enable docker
}

################################################################################
# Function Name: set_amdgpu_performance
# Description  : 设置AMD显卡性能模式。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function set_amdgpu_performance(){
    local pci_ids
    local r_pci_id
    local card
    echo "------------设置AMD显卡性能模式--------------"
    pci_ids=("$(lspci|grep "AMD"|grep "VGA"|awk '{print $1}')")
    for pci_id in ${pci_ids[*]}
    do
        if [ ${#pci_id} -eq 7 ]
        then
            r_pci_id="0000:${pci_id}"
        else
            r_pci_id="${pci_id}"
        fi
        card=$(ls /sys/bus/pci/devices/"${r_pci_id}"/drm/|grep card)
        echo high > /sys/class/drm/"${card}"/device/power_dpm_force_performance_level
    done
}

################################################################################
# Function Name: set_a32a64
# Description  : 转码使能。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function set_a32a64(){
    if [ -e "/proc/sys/fs/binfmt_misc/ubt_a32a64" ]
    then
        < /proc/sys/fs/binfmt_misc/ubt_a32a64 grep "enabled" > /dev/null 2>&1
        [ $? -eq 0 ] && return 0
    fi
    echo "------------配置转码------------"
    [ -e "/proc/sys/fs/binfmt_misc/ubt_a32a64" ] && echo -1 > /proc/sys/fs/binfmt_misc/ubt_a32a64
    rm -rf /opt/exagear/ubt_a32a64
    mount |grep "binfmt_misc on" > /dev/null 2>&1
    [ $? -ne 0 ] && mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc
    mkdir -p /opt/exagear
    cp ${new_file_dir}/ubt_a32a64 /opt/exagear/
    chmod +x /opt/exagear/ubt_a32a64
    echo ":ubt_a32a64:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\x00\x00\x00\x00\x00\x00\x00\x00\xfe\xff\xff\xff:/opt/exagear/ubt_a32a64:POCF" > /proc/sys/fs/binfmt_misc/register
    < /proc/sys/fs/binfmt_misc/ubt_a32a64 grep "enabled"
    [ $? -ne 0 ] && error "tango规则是否注册失败"
}

################################################################################
# Function Name: insmod_ashmem_binder
# Description  : 安装ashmem、binder两个内核模块。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function insmod_ashmem_binder(){
    local count_time=0
    local binder_num
    echo "-------安装ashmem、binder模块--------"
    cd ${new_file_dir} || exit
    lsmod |grep -w aosp9_binder_linux
    if [ $? -ne 0 ]
    then
        insmod aosp9_binder_linux.ko num_devices=400
        lsmod |grep -w aosp9_binder_linux
        [ $? -ne 0 ] && error "binder安装失败"
    fi
    cd ${new_file_dir} || exit
    lsmod |grep -w ashmem_linux
    if [ $? -ne 0 ]
    then
        insmod ashmem_linux.ko
        lsmod |grep -w ashmem_linux
        [ $? -ne 0 ] && error "ashmem安装失败"
    fi
    while true
    do
        sleep 1
        binder_num=$(ls /dev/|grep -c "^aosp9_binder[0-9]\{1,3\}$")
        [ "${binder_num}" -eq 400 ] && break
        if [ ${count_time} -gt 15 ]
        then
            echo -e "\033[1;31m insmod aosp9_binder failed\033[0m"
            break
        fi
        (( count_time++ )) || true
    done
    echo "--------配置dev可执行权限--------"
    chmod 600 /dev/aosp9_binder*
    chmod 600 /dev/ashmem
    chmod 600 /dev/dri/*
    chmod 600 /dev/input
}

################################################################################
# Function Name: modify_kv_config
# Description  : key=value类型配置文件修改。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function modify_kv_config(){
    local conf_file=$1
    local item=$2
    local value=$3
    local kv_num
    local kv_v
    local kv_vr
    kv=$(< "${conf_file}" grep -v "^#"|grep -E "^${item}[[:space:]]*=")
    kv_num=$(< "${conf_file}" grep -v "^#"|grep -cE "^${item}[[:space:]]*=")
    if [ "${kv_num}" -gt 1 ]
    then
        sed -i "/${item}/d" "${conf_file}"
        echo "${item}=${value}" >> "${conf_file}"
    elif [ "${kv_num}" -le 0 ]
    then
        echo "${item}=${value}" >> "${conf_file}"
    else
        kv_v=$(echo "${kv}"|awk -F '=' '{print $2}')
        kv_vr=$(eval echo "${kv_v}")
        if [ "${kv_vr}" != "${value}" ]
        then
            sed -i "s|^${item}[[:space:]]*=.*|${item}=${value}|g" "${conf_file}"
        fi
    fi
}

################################################################################
# Function Name: modify_ns_config
# Description  : key value类型配置文件修改。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function modify_ns_config(){
    local conf_file=$1
    local item=$2
    local value=$3
    local ns
    local ns_num
    local ns_v
    local ns_vr
    ns=$(< "${conf_file}" grep -v "^#"|grep -w "^${item}")
    ns_num=$(< "${conf_file}" grep -v "^#"|grep -wc "^${item}")
    if [ "${ns_num}" -gt 1 ]
    then
        sed -i "/${item}/d" "${conf_file}"
        echo "${item} ${value}" >> "${conf_file}"
    elif [ "${ns_num}" -le 0 ]
    then
        echo "${item} ${value}" >> "${conf_file}"
    else
        ns_v=$(echo "${ns}"|awk '{print $NF}')
        ns_vr=$(eval echo "${ns_v}")
        if [ "${ns_vr}" != "${value}" ]
        then
            sed -i "s|^${item}.*|${item} ${value}|g" "${conf_file}"
        fi
    fi
}

################################################################################
# Function Name: optimize_conf
# Description  : 系统优化配置。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function optimize_conf(){
    #间隔只有一个空格（格式统一）
    sed -i 's/^[[:space:]]\+//g' /etc/sysctl.conf
    sed -i '/^[^#]/s/[[:space:]]\+/ /g' /etc/sysctl.conf
    sed -i 's/^[[:space:]]\+//g' /etc/security/limits.conf
    sed -i '/^[^#]/s/[[:space:]]\+/ /g' /etc/security/limits.conf
    modify_kv_config /etc/sysctl.conf kernel.pid_max 4119481
    modify_kv_config /etc/sysctl.conf kernel.threads-max 4119481
    modify_kv_config /etc/sysctl.conf fs.inotify.max_user_instances 81920
    modify_kv_config /etc/sysctl.conf net.ipv4.ip_forward 1
    ulimit -u 2059740
    modify_ns_config /etc/security/limits.conf "* soft core" 0
    modify_ns_config /etc/security/limits.conf "* hard core" 0
    modify_ns_config /etc/security/limits.conf "root soft nofile" 165535
    modify_ns_config /etc/security/limits.conf "root hard nofile" 165535
}

################################################################################
# Function Name: set_mapping_node
# Description  : 设置映射到容器内的节点，主要解决部分游戏会根据这个节点来开启渲染线程，
#                如不设置，默认根据CPU数量来开启渲染线程，这样的话，渲染线程就会开启的
#                太多，影响游戏运行。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function set_mapping_node(){
    mkdir -p /root/vpresent
    [ -d "/root/vpresent/possible" ] && rm -rf /root/vpresent/possible
    [ -d "/root/vpresent/present" ] && rm -rf /root/vpresent/present
    touch /root/vpresent/possible
    touch /root/vpresent/present
    echo 0-1 > /root/vpresent/possible
    echo 0-1 > /root/vpresent/present
    chmod 600 /root/vpresent/*
}

################################################################################
# Function Name: install_lxcfs
# Description  : 安装lxcfs服务。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function install_lxcfs(){
    cd ${new_file_dir}/lxcfs_deb || exit
    dpkg -i lxcfs_*_arm64.deb
    dpkg -i liblxc-common_*_arm64.deb
    local lxcfs_status
    lxcfs_status=$(systemctl is-active lxcfs.service)
    if [ "${lxcfs_status}" = "inactive" ]
    then
        systemctl restart lxcfs
    fi
    if [ ! -f "${lxcfs_path}/proc/cpuinfo" ]
    then
        rm -rf ${lxcfs_path:?}/*
        /usr/bin/lxcfs ${lxcfs_path}/
        sleep 2
        systemctl restart lxcfs.service
        [ $? -ne 0 ] && error "Failed to restart the lxcfs service. Check the lxcfs service."
    fi
    echo "lxcfs.service is $(systemctl is-active lxcfs.service)"
}

################################################################################
# Function Name: import_android_image
# Description  : 导入android镜像到docker。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function import_android_image(){
    cd ${new_file_dir} || exit
    docker images|awk '{print $1" "$2}'|grep -w "kbox9_exagear"|grep -w "new" > /dev/null 2>&1
    [ $? -eq 0 ] && return 0
    if [ -f "image/android.tar" ]
    then
        docker import image/android.tar  kbox9_exagear:new || exit
    fi
}

################################################################################
# Function Name: start_kbox_default
# Description  : 尝试启动一个kbox9，判断环境是否已经配置好。
# Parameter    : 
# Returns      : 0 on success, otherwise on fail
################################################################################
function start_kbox_default(){
    local kbox_name
    local count_time=0
    local boot_state
    cd ${new_file_dir}/deploy_scripts || exit
    docker ps -a|awk '{print $(NF-1)" "$NF}'|grep -E "8501|kbox_1" > /dev/null 2>&1
    [ $? -eq 0 ] && return 0
    sh aosp9_start_box.sh kbox9_exagear:new 1 1 2 > /dev/null 2>&1
    kbox_name=kbox_1
    docker exec -i ${kbox_name} sh -c "getprop sys.boot_completed"|grep 1
    if [ $? -ne 0 ]
    then
        echo "${kbox_name} 启动失败，请重新检查环境。"
    fi
}

main(){
    install_kernel
    set_amdgpu_performance
    set_a32a64
    insmod_ashmem_binder
    import_android_image
    set_mapping_node
    install_lxcfs
    start_kbox_default
}

main "$@"
exit 0
