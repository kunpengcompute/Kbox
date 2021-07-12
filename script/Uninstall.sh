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
cd "${CURRENT_DIR}" || exit

function detele_android_image(){
    docker ps -a|awk '{print $NF" "$((NF-1))}'|grep -wE "8501|android_1" > /dev/null 2>&1
    if [ $? -eq 0 ]
    then
        docker rm -f android_1
        sleep 2
    fi
    old_imgs=$(docker images|grep -w "kbox"|awk '{print $3}')
    for old_img in ${old_imgs}
    do
        docker rmi "${old_img}"
    done
}

function detele_kboxservice(){
    oldkbox_pids=$(pgrep -x Kbox)
    for oldkbox_pid in ${oldkbox_pids}
    do
        kill -9 "${oldkbox_pid}"
    done
}

function detele_modules(){
    lsmod |grep -w binder_linux
    if [ $? -eq 0 ]
    then
        rmmod binder_linux
    fi
    lsmod |grep -w ashmem_linux
    if [ $? -eq 0 ]
    then
        rmmod ashmem_linux
    fi
    lsmod |grep -w smc_dri
    if [ $? -eq 0 ]
    then
        rmmod smc_dri
    fi
}

function detele_exagear(){
    if [ -e /proc/sys/fs/binfmt_misc/ubt_a32a64 ]; then
        echo -1 > /proc/sys/fs/binfmt_misc/ubt_a32a64
    fi
}

function detele_docker_network(){
    if [[ -n $(docker network ls |awk '{print $2}'|grep -w "PC-Kbox") ]]; then
        docker network rm PC-Kbox
    fi
}

function detele_icons(){
    [ ! -d "/home/Kbox/desktop/" ] && return
    icons=$(ls /home/Kbox/desktop/*.desktop 2> /dev/null)
    for icon in ${icons}
    do
        [ -f /usr/share/applications/"${icon##*/}" ] && rm -rf /usr/share/applications/"${icon##*/}"
    done
}

function detele_user(){
	if [ -n "$(ls /lib/systemd/system/ |grep -w pckbox-daemon.service)" ];then
		user=$(cat /lib/systemd/system/pckbox-daemon.service |grep -w User | awk -F '=' '{print $2}')
		if [ -n "$(cat /etc/passwd |grep -w ${user} |grep -w nologin)" ];then
			userdel ${user}
			rm -rf /home/${user}
                        if [ -n "$(cat /etc/passwd |grep -w Kbox |grep -w nologin)" ];then
                            userdel Kbox 
                        fi
		fi
	fi
}

function detele_olduser(){
        if [ -n "$(ls /etc/systemd/system/ |grep -w pckbox-daemon.service)" ];then
                user=$(cat /etc/systemd/system/pckbox-daemon.service |grep -w User | awk -F '=' '{print $2}')
                if [ -n "$(cat /etc/passwd |grep -w ${user} |grep -w nologin)" ];then
                        userdel ${user}
                        rm -rf /home/${user}
                        if [ -n "$(cat /etc/passwd |grep -w Kbox |grep -w nologin)" ];then
                            userdel Kbox 
                        fi
                fi
        fi
}
main(){
    systemctl disable pckbox-init
    systemctl stop pckbox-init
    systemctl disable pckbox-daemon
    systemctl stop pckbox-daemon
    systemctl disable pckbox-prepare
    systemctl stop pckbox-prepare
    systemctl disable pckbox-manager
    systemctl stop pckbox-manager
    user=$(logname)
    su ${user} -s /bin/bash -c /usr/bin/pckbox_stop.sh
    detele_kboxservice
    detele_android_image
    detele_modules
    detele_exagear
    detele_docker_network
    if [ -d "/opt/exagear" ]; then
        rm -rf /opt/exagear
    fi
    detele_icons
    detele_user
    detele_olduser
    if [ -n "$(ls /etc/systemd/system/ |grep -w pckbox-daemon.service)" ];then
	    rm -rf /etc/systemd/system/pckbox-daemon.service
    fi
    if [ -n "$(ls /etc/systemd/system/ |grep -w pckbox-manager.service)" ];then
	    rm -rf /etc/systemd/system/pckbox-manager.service
    fi
    if [ -n "$(ls /etc/systemd/system/ |grep -w pckbox-init.service)" ];then
	    rm -rf /etc/systemd/system/pckbox-init.service
    fi
    if [ -n "$(ls /etc/systemd/system/ |grep -w pckbox-prepare.service)" ];then
	    rm -rf /etc/systemd/system/pckbox-prepare.service
    fi
    rm -rf /usr/lib/systemd/user/pckbox-server.service
    rm -rf /etc/xdg/autostart/pckbox-server.desktop
    rm -rf /lib/systemd/system/pckbox-daemon.service
    rm -rf /lib/systemd/system/pckbox-prepare.service
    rm -rf /lib/systemd/system/pckbox-manager.service
    rm -rf /lib/systemd/system/pckbox-init.service
    systemctl daemon-reload
    rm -rf /boot/kbox10_deployed
    rm -rf /usr/bin/Kbox
    rm -rf /usr/bin/Kbox_init
    rm -rf /usr/bin/Kbox/android-appmgr.sh
    rm -rf /usr/bin/pckbox_stop.sh
    rm -rf /usr/bin/pckbox_start.sh
    rm -rf /opt/kernel_modules
	
	
}

main "$@"
exit 0
