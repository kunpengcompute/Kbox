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
service_file="Kbox-container-manager.service"
status_kcm=""
substatus_kcm=""
unitstatus_kcm=""
if [ -n "$(systemctl list-unit-files|grep -w Kbox-container-manager.service)" ]; then
    status_kcm=$(systemctl show --property=ActiveState Kbox-container-manager.service|awk -F '=' '{print $2}')
    substatus_kcm=$(systemctl show --property=SubState Kbox-container-manager.service|awk -F '=' '{print $2}')
    unitstatus_kcm=$(systemctl is-enabled Kbox-container-manager.service)
fi

function check_network(){
    echo "-------检查网络连接情况中--------"
    ping -c 3 www.baidu.com  > /dev/null 2>&1
    [ $? != 0 ] && error "网络连接异常"
}

function install_dependency(){
    apt update || exit 1
    apt -y install containerd.io docker-ce docker-ce-cli
    apt -y install lxcfs
    apt -y install libssl1.1 libcap2
}

function check_docker(){
    local docker_info_storagedriver
    docker_info_storagedriver=$(docker info |grep "Storage Driver" | awk '{print $3}')
    if [ "${docker_info_storagedriver}" = "overlay" ] || [ "${docker_info_storagedriver}" = "overlay2" ]
    then
        echo "Storage Driver: ${docker_info_storagedriver} ,不需要修改."
    else
        echo "DOCKER_OPTS= -s overlay" >> /etc/default/docker
        systemctl restart docker
    fi
}

function prepare(){
    cp -r "${CURRENT_DIR}"/pckbox-prepare.service /lib/systemd/system/
    cp -r "${CURRENT_DIR}"/pckbox_prepare.sh /usr/bin/
    ln -s /lib/systemd/system/pckbox-prepare.service /etc/systemd/system/
    chmod 755 /usr/bin/pckbox_prepare.sh
    if [ -e "kernel_modules.tar.gz" ]; then
        [ ! -d "kernel_modules" ] && tar -xvf kernel_modules.tar.gz
    fi
    if [ ! -d "/opt/kernel_modules" ]; then
        cp -r "${CURRENT_DIR}"/kernel_modules /opt/
    fi
    cpu_vendor="0x48"
    cpu_name=$(< /proc/cpuinfo grep implementer|head -n1|awk '{print $NF}')
    if [ "${cpu_vendor}" = "${cpu_name}" ]; then
        if [ -d "/opt/exagear" ]; then
           rm -rf /opt/exagear
        fi
        mkdir -p /opt/exagear
        cp "${CURRENT_DIR}"/kernel_modules/ubt_a32a64 /opt/exagear/
        chmod +x /opt/exagear/ubt_a32a64
    fi
    systemctl daemon-reload
    systemctl start pckbox-prepare.service
    systemctl enable pckbox-prepare.service
}

function check_modules(){
    local count_time=0
    while true
    do
        if [ -e /dev/binder2 ] && [ -e /dev/ashmem ]; then
            break
        fi
        # 20秒内核模块未注册成功超时退出
        if [ ${count_time} -le 20 ]
        then
            sleep 1
            (( count_time++ )) || true
        else
            error "kernel modules insmod failed"
        fi
    done
}


function kbox_user(){
    local count_time=0
    local kbox_number=0
    mkdir -p /var/lib/Kbox
    chmod 700 /var/lib/Kbox
    cp -r "${CURRENT_DIR}"/pckbox-init.service /lib/systemd/system/
    cp -r ${CURRENT_DIR}/pckbox-server.desktop /etc/xdg/autostart/
    cp -r ${CURRENT_DIR}/pckbox-server.service /usr/lib/systemd/user/
    cp -r "${CURRENT_DIR}"/pckbox-manager.service /lib/systemd/system/
    cp -r "${CURRENT_DIR}"/pckbox-daemon.service /lib/systemd/system/
    cp -r "${CURRENT_DIR}"/android.tar /var/lib/Kbox/
    cp -r "${CURRENT_DIR}"/android-appmgr.sh /usr/bin/
    chmod 644 /lib/systemd/system/pckbox-init.service
    chmod 644 /lib/systemd/system/pckbox-daemon.service
    chmod 644 /lib/systemd/system/pckbox-manager.service
    chmod 644 /usr/lib/systemd/user/pckbox-server.service
    chmod 644 /etc/xdg/autostart/pckbox-server.desktop
    ln -s /lib/systemd/system/pckbox-init.service /etc/systemd/system/
    ln -s /lib/systemd/system/pckbox-manager.service /etc/systemd/system/
    ln -s /lib/systemd/system/pckbox-daemon.service /etc/systemd/system/
    kbox_name=Kbox
    if [ -z "$(cat /etc/passwd|awk -F ':' '{print $1}'|grep -w ${kbox_name})" ];then
        useradd Kbox -M -s /usr/sbin/nologin
    else
    while true
    do
        if [ -z "$(cat /etc/passwd|awk -F ':' '{print $1}'|grep -w ${kbox_name}${kbox_number})" ];then
            useradd ${kbox_name}${kbox_number} -M -s /usr/sbin/nologin
            sed -i "s/User=Kbox/User=${kbox_name}${kbox_number}/g" /lib/systemd/system/pckbox-manager.service
            sed -i "s/User=Kbox/User=${kbox_name}${kbox_number}/g" /lib/systemd/system/pckbox-init.service
            sed -i "s/home\/Kbox/home\/${kbox_name}${kbox_number}/g" /lib/systemd/system/pckbox-daemon.service
        sed -i "s/User=Kbox/User=${kbox_name}${kbox_number}/g" /lib/systemd/system/pckbox-daemon.service
        sed -i "s/home\/Kbox/home\/${kbox_name}${kbox_number}/g" /usr/lib/systemd/user/pckbox-server.service
        kbox_name=Kbox${kbox_number}
        break
        fi
        sleep 1
        (( kbox_number++ )) || true    
        done
    fi
    chown ${kbox_name}:${kbox_name} /var/lib/Kbox
    cp "${CURRENT_DIR}"/containerRun.sh /var/lib/Kbox/
    chmod 700 /var/lib/Kbox/containerRun.sh
    chown ${kbox_name}:${kbox_name} /var/lib/Kbox/containerRun.sh
    chown ${kbox_name}:${kbox_name} /var/lib/Kbox/android.tar
    chmod 700 /var/lib/Kbox/android.tar
    chmod 755 /usr/bin/android-appmgr.sh
    cp -r "${CURRENT_DIR}"/Kbox /usr/bin/
    cp -r "${CURRENT_DIR}"/Kbox_init /usr/bin
    chmod 755 /usr/bin/Kbox
    chmod 755 /usr/bin/Kbox_init
    mkdir -p /home/${kbox_name}
    chmod 755 /home/${kbox_name}
    chown ${kbox_name}:${kbox_name} -R /home/${kbox_name}
    if [ -z "$(cat /etc/group |grep -w docker |grep -w ${kbox_name})" ];then
        usermod -a -G docker ${kbox_name}
    fi
    check_modules
    setcap cap_dac_override+eip /usr/bin/Kbox_init
    systemctl daemon-reload
    systemctl start pckbox-init.service
    systemctl enable pckbox-init.service
    while true
    do
        ps -ef|grep -v grep|grep -w Kbox_init
        if [ $? -eq 0 ]; then
            break
        fi
        # 10秒未成功启动超时退出
        if [ ${count_time} -le 10 ]
        then
            sleep 1
            (( count_time++ )) || true
        else
            error "pckbox init started failed"
        fi
    done
    sleep 2
    systemctl start pckbox-daemon.service
    systemctl enable pckbox-daemon.service
    sleep 2
    systemctl start pckbox-manager.service
    systemctl enable pckbox-manager.service
}

function kbox_service(){
    cp -r ${CURRENT_DIR}/pckbox_stop.sh /usr/bin/
    cp -r ${CURRENT_DIR}/pckbox_start.sh /usr/bin/
    chmod 755 /usr/bin/pckbox_start.sh
    chmod 755 /usr/bin/pckbox_stop.sh
    user=$(logname)
    su ${user} -s /bin/bash -c /usr/bin/pckbox_start.sh
}

function kbox_container(){
    if [ "enabled" = "${unitstatus_kcm}" ]; then
        systemctl disable ${service_file}
    fi

    if [ "active" = "${status_kcm}" ] || [ "running" = "${substatus_kcm}" ]; then
        systemctl stop ${service_file}
    fi
    if [ -e /proc/sys/fs/binfmt_misc/ubt_a32a64 ]; then
        echo -1 > /proc/sys/fs/binfmt_misc/ubt_a32a64
    fi
    if [ -n "$(systemctl list-unit-files|grep -w exagear.service)" ]; then
        systemctl stop exagear.service
        systemctl disable exagear.service
    fi
}

function android_package(){
    [ ! -d "/home/${kbox_name}/desktop/" ] && return
    package_list=$(ls /home/${kbox_name}/desktop/ |grep -w desktop |awk -F '.desktop' '{print $1}')
    for package in ${package_list}
    do
        /usr/bin/Kbox launcher createicon -n "${package}" -p /usr/share/applications/ > /dev/null 2>&1
    done
}

function check_boot_status(){
    local count_time=0
    while true
    do
        docker ps -a|awk '{print $NF}'|grep -wq android_1
        if [ $? -eq 0 ]
        then
            docker exec -i android_1 getprop sys.boot_completed|grep 1 > /dev/null 2>&1
            if [ $? -eq 0 ]
            then
                sleep 2
                echo "started successfully"
                break
            fi
        fi

        # 60秒未成功启动超时退出
        if [ ${count_time} -le 60 ]
        then
            sleep 1
            (( count_time++ )) || true
        else
            echo -e "\033[1;31mStart check timed out,unable to start\033[0m"
            error "started failed"
        fi
    done
}

function close_bridge(){
    local bridge
    local images_num
    local image_id
    bridge=$(docker network ls|awk '{print $2}'|grep -w bridge)
    if [ -n "${bridge}" ]; then
        images_num=$(docker images -a -q|wc -l)
        image_id=$(docker images -a -q -f "reference=kbox:10")
        if [ -n "${image_id}" ]; then
            images_num=$((images_num-1))
        fi
        if [ ${images_num} -le 0 ]; then
            touch "/etc/docker/daemon.json"
            echo -e "{\n\t\"bridge\":\"none\"\n}" > /etc/docker/daemon.json
            systemctl restart docker.service
        fi
    fi
}

main(){
    if [ ! -f "/boot/Kbox10_deployed" ]
    then
        check_network
        install_dependency
        check_docker
        touch /boot/kbox10_deployed
        echo "sp3" > /boot/kbox10_deployed
    fi
    if [ -n "$(systemctl list-unit-files|grep -w Kbox-container-manager.service)" ]; then
        kbox_container
    fi
    close_bridge
    prepare
    kbox_user
    sleep 2
    kbox_service
    check_boot_status
    sleep 3
    android_package
}
main "$@"
exit 0

