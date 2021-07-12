#!/bin/bash
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

ALL_CPUS=$(cat /sys/devices/system/cpu/online)
MAX_NUM=8
GPU=""
pci_ids=$(lspci|grep "AMD"|grep "VGA"|grep -wE '230|520|550|340|430'|awk '{print $1}')
s=0
for pci_id in ${pci_ids}
do
    if [ -n "${pci_id}" ]; then
        if [ ${#pci_id} -eq 7 ]
        then
            r_pci_id="0000:${pci_id}"
        else
            r_pci_id="${pci_id}"
        fi
        gpu_node=$(ls /sys/bus/pci/devices/"${r_pci_id}"/drm/|grep renderD)
        all_gpu[s]=${gpu_node}
        let s++
    fi
    if [[ "${all_gpu[*]} " =~ "renderD128 " ]]; then
        GPU="renderD128"
    else
        GPU=${all_gpu[0]}
    fi
done

BINDERNODE=/dev/binder0
HWBINDERNODE=/dev/binder1
VNDBINDERNODE=/dev/binder2
box_data="/var/lib/Kbox"
lxcfs_path="/var/lib/lxcfs"
path_cpu="/sys/devices/system/cpu"
box_name=android_1

function getcpus(){
    local cpus_r
    local start
    local end
    cpus_r=$(echo ${ALL_CPUS}|sed 's/,/ /g')
    for cpu_r in ${cpus_r}
    do
        echo ${cpu_r}|grep "-" > /dev/null
        if [ $? -eq 0 ]; then
            start=$(echo ${cpu_r}|cut -d '-' -f1)
            end=$(echo ${cpu_r}|cut -d '-' -f2)
        else
            start=${cpu_r}
            end=${cpu_r}
        fi
        echo $(seq ${start} 1 ${end})
    done
}

function select_cpus(){
    local s
    local cpus
    local cpu_num
    cpus=($(getcpus))
    cpu_num=${#cpus[*]}
    if [ ${cpu_num} -gt ${MAX_NUM} ]
    then
        s=$((cpu_num - MAX_NUM))
        while (($s < $cpu_num))
        do
            echo "${cpus[s]}"
            (( s++ )) || true
        done
    else
        echo "${cpus[*]}"
    fi
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


function import_image(){
    image_id=$(docker images -a -q -f "reference=kbox:10")
    if [ -n "${image_id}" ]; then
        docker rmi ${image_id} || true
    fi
    docker import /var/lib/Kbox/android.tar kbox:10
}

function rm_image(){
    docker rmi kbox:10
}

function is_exist_container(){
    local containerid
    containerid=$(docker ps -a -q -f "name=${box_name}")
    if [ -n "${containerid}" ]; then
        echo "The ${box_name} exists" && return 0
    else
        echo "The ${box_name} does not exist" && return 1
    fi
}

function get_docker_gw(){
    local kbox_gw
    kbox_gw=$(cat /home/Kbox/network_gw)
    if [ -n "${kbox_gw}" ]; then
        echo -n "${kbox_gw}" && return 0
    else
        return 1
    fi
}

function create_container(){
    local scpus
    local bind_cpu
    local acnt
    local vcpus
    local containerid
    local gpu
    local gateway
    local kbox_net
    containerid=$(docker ps -a -q -f "name=${box_name}")
    if [ -n "${containerid}" ]; then
        echo "The ${box_name} exists,please rm ${box_name} first." && return 1
    fi
    import_image
    scpus=($(select_cpus))
    bind_cpu=$(echo "${scpus[*]}"|tr ' ' ',')
    acnt=0
    vcpus=""
    for a in ${scpus[*]}
    do
        vcpus=$vcpus" -v ${path_cpu}/cpu${a}:${path_cpu}/cpu${acnt}:rw"
        acnt=$((acnt+1))
    done
    gpu=""
    if [ -n "${GPU}" ]; then
        gpu=" --device=/dev/dri/${GPU}:/dev/dri/renderD128:rwm"
    fi
    gateway=$(get_docker_gw)
#    echo $gateway
    kbox_net=$(docker network inspect PC-Kbox|grep "Subnet"|grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}")
#    echo $kbox_net
    [ -d "/var/run/docker/cpus/${box_name}" ] &&  rm -rf "/var/run/docker/cpus/${box_name}"
    mkdir -p /var/run/docker/cpus/"${box_name}"
    docker run -d -it \
        --cap-add=ALL \
        --security-opt="apparmor=unconfined" \
        --security-opt="seccomp=unconfined" \
        --pids-limit=-1 \
        --cpuset-cpus "${bind_cpu}" \
        --hostname "localhost" \
        --name "${box_name}" \
        -e DOCKER_NAME="${box_name}" \
        -e PATH=/system/bin:/system/xbin \
        -e GATEWAY="${gateway}" \
        -e SUBNET="${kbox_net}" \
        --net PC-Kbox \
        --device=${BINDERNODE}:/dev/binder:rwm \
        --device=${HWBINDERNODE}:/dev/hwbinder:rwm \
        --device=${VNDBINDERNODE}:/dev/vndbinder:rwm \
        --device=/dev/ashmem:/dev/ashmem:rwm \
        --device=/dev/fuse:/dev/fuse:rwm \
        $gpu \
        --device=/dev/uinput:/dev/uinput:rwm \
        --device-cgroup-rule="c 13:* rwm" \
        --volume=${box_data}/cache:/cache:rw \
        --volume=${box_data}/data:/data:rw \
        --volume=/var/run/1/input/event0:/dev/input/event0:rw \
        --volume=/var/run/1/input/event1:/dev/input/event1:rw \
        -v /sys/devices/system/cpu/present:/sys/devices/system/cpu/present \
        -v /sys/devices/system/cpu/possible:/sys/devices/system/cpu/possible \
        -v ${lxcfs_path}/proc/cpuinfo:/proc/cpuinfo:rw \
        -v ${lxcfs_path}/proc/diskstats:/proc/diskstats:rw \
        -v ${lxcfs_path}/proc/meminfo:/proc/meminfo:rw \
        -v ${lxcfs_path}/proc/stat:/proc/stat:rw \
        -v ${lxcfs_path}/proc/swaps:/proc/swaps:rw \
        -v ${lxcfs_path}/proc/uptime:/proc/uptime:rw \
        -v /var/run/docker/cpus/"${box_name}":/sys/devices/system/cpu:rw \
        $vcpus \
        -v $path_cpu/online:$path_cpu/online:rw \
        -v $path_cpu/modalias:$path_cpu/modalias:rw \
        -v $path_cpu/cpufreq:$path_cpu/cpufreq:rw \
        -v $path_cpu/hotplug:$path_cpu/hotplug:rw \
        -v $path_cpu/power:$path_cpu/power:rw \
        -v $path_cpu/uevent:$path_cpu/uevent:rw \
        -v $path_cpu/isolated:$path_cpu/isolated:rw \
        -v $path_cpu/offline:$path_cpu/offline:rw \
        -v $path_cpu/cpuidle:$path_cpu/cpuidle:rw \
        kbox:10  /PC_Kbox_init.sh
}

function stop_container(){
    docker stop ${box_name}
}

function restart_container(){
    local gpu_now
    is_exist_container
    if [ $? -ne 0 ]; then
        create_container
        return $?
    fi
    gpu_now=$(docker inspect -f '{{range .HostConfig.Devices}}{{.PathOnHost}}{{println}}{{end}}' ${box_name}|grep renderD|awk -F '/' '{print $NF}')
    if [ -z "${gpu_now}" ]; then
        if [ -n "${GPU}" ]; then
            rm_container
            create_container
        else
            docker restart ${box_name}
        fi
    else
        if [[ "${all_gpu[*]} " =~ "${gpu_now} " ]]; then
            docker restart ${box_name}
        else
            rm_container
            create_container
        fi
    fi
}

function rm_container(){
    docker rm -f ${box_name}
}

function Status_container(){
    local status
    #running/exited/created 除running状态都返回非0
    status=$(docker inspect -f {{.State.Status}} ${box_name})
    if [ "${status}" = "running" ]
    then
        echo "The ${box_name} is running" && return 0
    else
        echo "The ${box_name} is ${status}" && return 1
    fi
}

function get_ip(){
    local containerip
    containerip=$(docker inspect -f '{{index .NetworkSettings.Networks "PC-Kbox" "IPAddress"}}' ${box_name})
    if [ -n "${containerip}" ]; then
        echo -n "${containerip}" && return 0
    else
        return 1
    fi
}

function get_net(){
    local net
    local net_172_used
    net_172_used=$(ip route|grep -v "default"|grep -w "^172"|awk '{print $1}'|awk -F '.' '{print $2}')
    for net in $(seq 16 31)
    do
        if [[ ! "$net_172_used" =~ ${net} ]];then
            echo "${net}"
            return 0
        fi
    done
}
function check_docker_net(){
    local net_set
    local net
    local net_used
    local gateway_set
    local kbox_net

    if [[ -z $(docker network ls |awk '{print $2}'|grep -w "PC-Kbox") ]]; then
        net_useds=$(ip route|grep -v "default"|awk '{print $1}')
    else
        net_useds=$(ip route|grep -v "default"|grep -v "$(docker network ls|awk '{print $1" "$2}'|grep "PC-Kbox"|awk '{print "br-"$1}')"|awk '{print $1}')
    fi
    if [ -f "/home/Kbox/network/gateway" ]; then
        net_set=$(< /home/Kbox/network/gateway grep "Subnet"|awk -F '=' '{print $2}')
    else
        net_set=""
    fi
    if [ -n "${net_set}" ]; then
        for net_used in ${net_useds}
        do
            comp_res=$(python3 -c "import ipaddress;net1=ipaddress.ip_network(\"${net_set}\");net2=ipaddress.ip_network(\"${net_used}\");print(net1.subnet_of(net2))")
            if [ "${comp_res}" = "True" ];then
                return 1
            fi
        done
        gateway_set="${net_set%.*}.1"
        if [[ -z $(docker network ls |awk '{print $2}'|grep -w "PC-Kbox") ]]; then
            is_exist_container
            if [ $? -eq 0 ]; then
                rm_container
            fi
            docker network create --driver bridge --subnet="${net_set}" --gateway="${gateway_set}" PC-Kbox
        else
            kbox_net=$(docker network inspect PC-Kbox|grep "Subnet"|grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}")
            if [ "${net_set}" != "${kbox_net}" ];then
                is_exist_container
                if [ $? -eq 0 ]; then
                    rm_container
                fi
                docker network rm PC-Kbox
                docker network create --driver bridge --subnet="${net_set}" --gateway="${gateway_set}" PC-Kbox
            fi
        fi
    else
        if [[ -n $(docker network ls |awk '{print $2}'|grep -w "PC-Kbox") ]]; then
            kbox_net=$(docker network inspect PC-Kbox|grep "Subnet"|grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}")
            for net_used in ${net_useds}
            do
                comp_res=$(python3 -c "import ipaddress;net1=ipaddress.ip_network(\"${kbox_net}\");net2=ipaddress.ip_network(\"${net_used}\");print(net1.subnet_of(net2))")
                if [ "${comp_res}" = "True" ];then
                    net=$(get_net)
                    net_set="172.${net}.200.0/24"
                    gateway_set="172.${net}.200.1"
                    is_exist_container
                    if [ $? -eq 0 ]; then
                        rm_container
                    fi
                    docker network rm PC-Kbox
                    docker network create --driver bridge --subnet="${net_set}" --gateway="${gateway_set}" PC-Kbox
                    return $?
                fi
            done
        else
            net=$(get_net)
            net_set="172.${net}.200.0/24"
            gateway_set="172.${net}.200.1"
            is_exist_container
            if [ $? -eq 0 ]; then
                rm_container
            fi
            docker network create --driver bridge --subnet="${net_set}" --gateway="${gateway_set}" PC-Kbox
        fi
    fi
    if [ -n "${gateway_set}" ];then
        echo "${gateway_set}" > /home/Kbox/network_gw
        chmod 644 /home/Kbox/network_gw
    fi
}

main(){
    action=$1
    case $action in
        create)
            check_modules
            create_container
        ;;
        stop)
            stop_container
        ;;
        restart)
            check_modules
            restart_container
        ;;
        rm)
            rm_container
        ;;
        rmi)
            rm_image
        ;;
        status)
            Status_container
        ;;
        is-exist)
            is_exist_container
        ;;
        getip)
            get_ip
        ;;
        check_net)
            check_docker_net
        ;;
        *)
            echo "unknown action"
            return 1
        ;;
    esac
}
main "$@"
exit $?
