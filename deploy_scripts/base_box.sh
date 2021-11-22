#!/bin/bash
# Copyright Huawei Technologies Co., Ltd. 2021-2021. All rights reserved.
function check_environment() {
    # root权限执行此脚本
    if [ "${UID}" -ne 0 ]; then
        echo  "请使用root权限执行"
        exit 1
    fi

    # 支持非当前目录执行
    CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    cd ${CURRENT_DIR}
}

function get_lxcfs_path() {
    local OS_NAME=$(cat /etc/os-release | grep -w "NAME" | cut -d '=' -f 2 | tr -d '"')
    local value
    if [ "${OS_NAME}" = "EulerOS" ]; then
        value="/var/lib/lxc/lxcfs"
    else
        value="/var/lib/lxcfs"
    fi

    if [ ! -d "$value" ]; then
        echo "error, fail to get lxcfs path"
        exit 1
    fi

    echo ${value}
}

function get_cpu_volume() {
    # SERVER_CPU_TAG_NUM：服务器中的CPU号
    # CONTAINER_CPU_TAG_NUM：映射到容器中的CPU号
    local SERVER_CPU_TAG_NUM=$1 CONTAINER_CPU_TAG_NUM=$2
    echo " --volume=/sys/devices/system/cpu/cpu$SERVER_CPU_TAG_NUM:/sys/devices/system/cpu/cpu$CONTAINER_CPU_TAG_NUM:ro "
}

function check_paras() {
    echo "------------------ Kbox Startup ------------------"

    local KBOX_NAME CPUS NUMAS GPUS_RENDER STORAGE_SIZE_GB RAM_SIZE_MB PORTS
    local BINDER_NODE HWBINDER_NODE VNDBINDER_NODE EXTRA_RUN_OPTION IMAGE_NAME
    local PARA_ERROR=""
    while :; do
        case $1 in
            start)              shift;;
            --name)             KBOX_NAME=$2;        echo "--name)               KBOX_NAME          : $2 "; shift;;
            --cpus)             CPUS=($2);           echo "--cpus)               CPUS               : $2 "; shift;;
            --numas)            NUMAS=($2);          echo "--numas)              NUMAS              : $2 "; shift;;
            --gpus)             GPUS_RENDER=($2);    echo "--gpus)               GPUS_RENDER        : $2 "; shift;;
            --storage_size_gb)  STORAGE_SIZE_GB=$2;  echo "--storage_size_gb)    STORAGE_SIZE_GB    : $2 "; shift;;
            --ram_size_mb)      RAM_SIZE_MB=$2;      echo "--ram_size_mb)        RAM_SIZE_MB        : $2 "; shift;;
            --binder_nodes)     BINDER_NODES=($2);   echo "--binder_nodes)       BINDER_NODES       : $2 "; shift;;
            --ports)            PORTS=($2);          echo "--ports)              PORTS              : $2 "; shift;;
            --extra_run_option) EXTRA_RUN_OPTION=$2; echo "--extra_run_option)   EXTRA_RUN_OPTION   : $2 "; shift;;
            --image)            IMAGE_NAME=$2;       echo "--image)              IMAGE_NAME         : $2 "; shift;;
            --)                 shift;               break;;
            -?*)                printf 'WARN: Unknown option: %s\n' "$1" >&2; exit 1;;
            *)   break
        esac

        shift
    done

    if [ -z $KBOX_NAME ]; then
        echo "\"--name\" option error, fail: need a kbox name!"
        PARA_ERROR="true"
    fi

    if [ ${#CPUS[@]} -eq 0 ]; then
        echo "\"--cpus\" option error, fail: para empty!"
        PARA_ERROR="true"
    fi
    local CPU
    for CPU in ${CPUS[@]}; do
        if [ -n "`echo "$CPU" | sed 's/[0-9]//g'`" ]; then
            echo "\"--cpus\" option error,  fail: cpu parameter must be number!"
            PARA_ERROR="true"
        fi
        if [ $CPU -ge  $(lscpu | grep -w "CPU(s)" | head -n 1 | awk '{print $2}') ] || \
           [ $CPU -lt 0 ]; then
            echo "\"--cpus\" option error, fail: cpu$CPUS not exist!"
        fi
    done

    if [ ${#NUMAS[@]} -eq 0 ]; then
        echo "\"--numas\" option error, fail: para empty!"
        PARA_ERROR="true"
    fi
    local NUMA
    for NUMA in ${NUMAS[@]}; do
        if [ -n "`echo "$NUMA" | sed 's/[0-9]//g'`" ]; then
            echo "\"--numas\" option error, fail: numa parameter must be number!"
            PARA_ERROR="true"
        fi
        
        if [ $NUMA -ge  $(lscpu | grep "NUMA node(s)" | awk '{print $3}') ] || \
           [ $NUMA -lt 0 ]; then
            echo " \"--numas\" fail: numa$NUMA not exist!"
            PARA_ERROR="true"
        fi
    done

    local GPU
    for GPU in ${GPUS_RENDER[@]}; do
        if [ ! -e $GPU ]; then
            echo "\"--gpus\"  error, fail: GPU device $GPU not exist!"
            PARA_ERROR="true"
        fi
    done

    if [ ${#BINDER_NODES[@]} -ne 3 ]; then
        echo "\"--binder_nodes\" option error, fail: \"--binder_nodes\" must have 3 parameters!"
        PARA_ERROR="true"
    fi
    local NODE
    for NODE in ${BINDER_NODES[@]}; do
        if [ -z $NODE ]; then
            echo "\"--binder_nodes\" option error, fail: \"--binder_nodes\" must have 3 parameters!"
            PARA_ERROR="true"
        elif [ ! -e $NODE ]; then
            echo "\"--binder_nodes\" option error, fail: binder node $NODE not exist!"
            PARA_ERROR="true"
        fi
    done

    if [ -z "`echo "$STORAGE_SIZE_GB" | sed 's/[0-9]//g'`" ]; then
        if [ -z $STORAGE_SIZE_GB ]; then
            echo "\"--storage_size_gb\" option error, fail: para empty!"
            PARA_ERROR="true"            
        elif [ $STORAGE_SIZE_GB -le 0 ]; then
            echo "\"--storage_size_gb\" option error, fail: storage size must greater than 0 GB!"
            PARA_ERROR="true"
        fi
    else
        echo "\"--storage_size_gb\" option error, fail: storage size must be number!"
        PARA_ERROR="true"
    fi
    
    if [ -z "`echo "$RAM_SIZE_MB" | sed 's/[0-9]//g'`" ]; then
        if [ -z $RAM_SIZE_MB ]; then
            echo "\"--ram_size_mb\" option error, fail: para empty!"
            PARA_ERROR="true"
        elif [ $RAM_SIZE_MB -le 0 ];then 
            echo "\"--ram_size_mb\" option error, fail: ram size must greater than 0 MB!"
            PARA_ERROR="true"
        fi
    else
        echo "\"--ram_size_mb\" option error, fail: ram size must be number!"
        PARA_ERROR="true"
    fi

    if [ ${#PORTS[@]} -eq 0 ]; then
        echo "\"--ports\" option error, fail: para empty!"
        PARA_ERROR="true"
    fi
    local PORT
    for PORT in ${PORTS[@]}; do
        if [[ "${PORT}" =~ ":" ]]; then
            local AGENT_PORT=$(echo ${PORT} | cut -d ':' -f1)
            local HOST_PORT=$(echo ${PORT} | cut -d ':' -f2)
            if [ -n "`echo "$AGENT_PORT" | sed 's/[0-9]//g'`" ]; then
                echo "\"--ports\" option error, fail: agent port must be number!"
                PARA_ERROR="true"
            fi

            if [ -n "`echo "$HOST_PORT" | sed 's/[0-9]//g'`" ]; then
                echo "\"--ports\" option error, fail: host port must be number!"
                PARA_ERROR="true"
            fi
        else 
            echo "\"--ports\" option error, fail: error port format!"
            PARA_ERROR="true"
        fi
    done

    if [[ "${IMAGE_NAME}" =~ ":" ]]; then
        local IMAGE_RE=$(echo ${IMAGE_NAME} | cut -d ':' -f1)
        tag=$(echo ${IMAGE_NAME} | cut -d ':' -f2)
        docker images | awk '{print $1" "$2}' | grep -w "${IMAGE_RE}" | grep -w "${tag}" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "\"--image\" option error, no image ${IMAGE_NAME}!"
            PARA_ERROR="true"
        fi
    else
        docker images | awk '{print $3}' | grep -w "${IMAGE_NAME}" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "\"--image\" option error, fail: no image ${IMAGE_NAME}!"
            PARA_ERROR="true"
        fi
    fi

    echo "---------------------------------------------------"
    if [ "$PARA_ERROR" = "true" ]; then
        echo "error: Kbox Start Fail!"
        exit 1
    fi
}

function start_box() {
    ########################## 1. 参数检查 ##########################
    check_paras "$@"
    ########################## 2. 参数解析 ##########################
    while :; do
        case $1 in 
            start)               shift;;
            --name)              local KBOX_NAME=$2;         shift;;
            --cpus)              local CPUS=($2);            shift;;
            --numas)             local NUMAS=($2);           shift;;
            --gpus)              local GPUS_RENDER=($2);     shift;;
            --storage_size_gb)   local STORAGE_SIZE_GB=$2;   shift;;
            --ram_size_mb)       local RAM_SIZE_MB=$2;       shift;;
            --binder_nodes)      local BINDER_NODES=($2);    shift;;
            --ports)             local PORTS=($2);           shift;;
            --extra_run_option)  local EXTRA_RUN_OPTION=$2;  shift;;
            --image)             local IMAGE_NAME=$2;        shift;;
            --)                  shift;                      break;;
            -?*) printf 'WARN: Unknown option: %s\n' "$1" >&2;;
            *)   break
        esac
        shift
    done 
    
    ########################## 3.环境初始化 ##########################
    # HOOK_PATH
    local HOOK_PATH=/var/lib/docker/hooks
    rm -rf ${HOOK_PATH}/${KBOX_NAME}
    mkdir -p ${HOOK_PATH}/${KBOX_NAME}

    # EVENT PATH 
    local INPUT_EVENT_PATH="/var/run/${KBOX_NAME}/input"
    mkdir -p $INPUT_EVENT_PATH"/event0"
    mkdir -p $INPUT_EVENT_PATH"/event1"

    # 重设容器内CPU核参数
    rm -rf "/var/run/docker/cpus/${KBOX_NAME}"
    mkdir -p "/var/run/docker/cpus/${KBOX_NAME}"
    echo "${#CPUS[@]}" >/var/run/docker/cpus/${KBOX_NAME}/kernel_max
    echo "0-$((${#CPUS[@]} - 1))" >/var/run/docker/cpus/${KBOX_NAME}/possible
    echo "0-$((${#CPUS[@]} - 1))" >/var/run/docker/cpus/${KBOX_NAME}/present

    # 存储隔离
    if [ ! -d "/root/mount/img" ]; then
        mkdir -p /root/mount/img
    fi
    local KBOX_IMG=/root/mount/img/$KBOX_NAME.img
    fallocate -l ${STORAGE_SIZE_GB}G $KBOX_IMG
    yes | mkfs -t ext4 $KBOX_IMG
    KBOX_DATA_PATH="/root/mount/data/$KBOX_NAME"
    mkdir -p $KBOX_DATA_PATH
    mount $KBOX_IMG $KBOX_DATA_PATH
    echo $(($STORAGE_SIZE_GB * 2 * 1024 * 1024)) >$KBOX_DATA_PATH/storage_size

    ########################## 4.容器启动 ##########################
    local RUN_OPTION=""
    RUN_OPTION+=" -d "
    RUN_OPTION+=" -it "
    RUN_OPTION+=" --cap-drop=ALL "
    RUN_OPTION+=" --cap-add=SETPCAP "
    RUN_OPTION+=" --cap-add=AUDIT_WRITE "
    RUN_OPTION+=" --cap-add=SYS_CHROOT "
    RUN_OPTION+=" --cap-add=CHOWN "
    RUN_OPTION+=" --cap-add=DAC_OVERRIDE "
    RUN_OPTION+=" --cap-add=FOWNER "
    RUN_OPTION+=" --cap-add=SETGID "
    RUN_OPTION+=" --cap-add=SETUID "
    RUN_OPTION+=" --cap-add=SYSLOG "
    RUN_OPTION+=" --cap-add=SYS_ADMIN "
    RUN_OPTION+=" --cap-add=WAKE_ALARM "
    RUN_OPTION+=" --cap-add=SYS_PTRACE "
    RUN_OPTION+=" --cap-add=BLOCK_SUSPEND "    
    RUN_OPTION+=" --cap-add=MKNOD "
    RUN_OPTION+=" --cap-add=KILL "
    RUN_OPTION+=" --cap-add=NET_RAW "
    RUN_OPTION+=" --cap-add=NET_ADMIN "
    RUN_OPTION+=" --security-opt="apparmor=unconfined" "
    RUN_OPTION+=" --security-opt=no-new-privileges "
    RUN_OPTION+="--name ${KBOX_NAME}"
    RUN_OPTION+=" -e DOCKER_NAME=${KBOX_NAME} "
    RUN_OPTION+=" -e PATH=/system/bin:/system/xbin "
    RUN_OPTION+=" --cidfile ${HOOK_PATH}/${KBOX_NAME}/docker_id.cid "
    RUN_OPTION+=" --cpu-shares=$(lscpu | grep -w "CPU(s)" | head -n 1 | awk '{print $2}') "
    
    local CPU NUMA TEMP
    for CPU in ${CPUS[@]}; do
        TEMP+=$CPU","
    done
    TEMP=${TEMP: 0: $((${#TEMP} - 1))}
    RUN_OPTION+=" --cpuset-cpus=$TEMP "
    
    TEMP=""
    for NUMA in ${NUMAS[@]}; do
       TEMP+=$NUMA","
    done
    TEMP=${TEMP: 0: $((${#TEMP} - 1))}
    RUN_OPTION+=" --cpuset-mems=$TEMP"

    RUN_OPTION+=" --memory=${RAM_SIZE_MB}M "
    RUN_OPTION+=" --device=${BINDER_NODES[0]}:/dev/binder:rwm "
    RUN_OPTION+=" --device=${BINDER_NODES[1]}:/dev/hwbinder:rwm "
    RUN_OPTION+=" --device=${BINDER_NODES[2]}:/dev/vndbinder:rwm "
    RUN_OPTION+=" --device=/dev/ashmem:/dev/ashmem:rwm "
    RUN_OPTION+=" --device=/dev/fuse:/dev/fuse:rwm "
    RUN_OPTION+=" --device=/dev/uinput:/dev/uinput:rwm "
    local i
    for (( i=0; i<${#GPUS_RENDER[@]};i++ )); do
        RUN_OPTION+=" --device=${GPUS_RENDER[$i]}:/dev/dri/renderD$((128 + $i)):rwm "
    done
    RUN_OPTION+=" --volume=$KBOX_DATA_PATH/cache:/cache:rw "
    RUN_OPTION+=" --volume=$KBOX_DATA_PATH/data:/data:rw "
    RUN_OPTION+=" --volume=$INPUT_EVENT_PATH/event0:/dev/input/event0:rw "
    RUN_OPTION+=" --volume=$INPUT_EVENT_PATH/event1:/dev/input/event1:rw "
    RUN_OPTION+=" --volume=$(get_lxcfs_path)/proc/cpuinfo:/proc/cpuinfo:ro "
    RUN_OPTION+=" --volume=$(get_lxcfs_path)/proc/diskstats:/proc/diskstats:ro "
    RUN_OPTION+=" --volume=$(get_lxcfs_path)/proc/meminfo:/proc/meminfo:ro "
    RUN_OPTION+=" --volume=$(get_lxcfs_path)/proc/stat:/proc/stat:ro "
    RUN_OPTION+=" --volume=$(get_lxcfs_path)/proc/swaps:/proc/swaps:ro "
    RUN_OPTION+=" --volume=$(get_lxcfs_path)/proc/uptime:/proc/uptime:ro "
    RUN_OPTION+=" --volume=/var/run/docker/cpus/${KBOX_NAME}:/sys/devices/system/cpu:rw "
    RUN_OPTION+=" --volume=$KBOX_DATA_PATH/storage_size:/storage_size:rw "
    for ((i=0; i<${#CPUS[@]}; i++))
    do
        RUN_OPTION+=$(get_cpu_volume ${CPUS[$i]} $i)
    done
    RUN_OPTION+=" --volume=/sys/devices/system/cpu/online:/sys/devices/system/cpu/online:ro "
    RUN_OPTION+=" --volume=/sys/devices/system/cpu/modalias:/sys/devices/system/cpu/modalias:ro "
    RUN_OPTION+=" --volume=/sys/devices/system/cpu/cpufreq:/sys/devices/system/cpu/cpufreq:ro "
    RUN_OPTION+=" --volume=/sys/devices/system/cpu/hotplug:/sys/devices/system/cpu/hotplug:ro "
    RUN_OPTION+=" --volume=/sys/devices/system/cpu/power:/sys/devices/system/cpu/power:ro "
    RUN_OPTION+=" --volume=/sys/devices/system/cpu/uevent:/sys/devices/system/cpu/uevent:ro "
    RUN_OPTION+=" --volume=/sys/devices/system/cpu/isolated:/sys/devices/system/cpu/isolated:ro "
    RUN_OPTION+=" --volume=/sys/devices/system/cpu/offline:/sys/devices/system/cpu/offline:ro "
    RUN_OPTION+=" --volume=/sys/devices/system/cpu/cpuidle:/sys/devices/system/cpu/cpuidle:ro "
    local PORT
    for PORT in ${PORTS[@]}; do
        RUN_OPTION+=" -p $PORT "    
    done
    
    RUN_OPTION+=" $EXTRA_RUN_OPTION "
    
    docker run $RUN_OPTION $IMAGE_NAME sh
}

function delete_box() {
    local KBOX_NAME=$1
    local RET="true"
    set +e
    # 删除容器
    if [ -n "$(docker ps -a --format {{.Names}} | grep "$KBOX_NAME$")" ]; then
        docker kill $KBOX_NAME > /dev/null 2>&1
        docker rm  $KBOX_NAME > /dev/null 2>&1
        [ $? -ne 0 ] && echo "fail to remove docker container $KBOX_NAME!" && RET="fail"
    fi

    # 删除数据文件
    if [ -d /root/mount/data/$KBOX_NAME ]; then
        umount /root/mount/data/$KBOX_NAME > /dev/null 2>&1
        [ $? -ne 0 ] && echo "$KBOX_NAME is already umounted!"
        rm -rf /root/mount/data/$KBOX_NAME > /dev/null 2>&1
        [ $? -ne 0 ] && echo "fail to remove data files /root/mount/data/$KBOX_NAME !" && RET="fail"
    fi

    # 删除数据img文件
    if [ -e /root/mount/img/$KBOX_NAME.img ]; then
        rm -rf /root/mount/img/$KBOX_NAME.img > /dev/null 2>&1
        [ $? -ne 0 ] && echo "fail to remove image file /root/mount/img/$KBOX_NAME.img !" && RET="fail"
    fi

    # 删除input event path
    if [ -d /var/run/$KBOX_NAME ]; then
        rm -rf /var/run/${KBOX_NAME} > /dev/null 2>&1
        [ $? -ne 0 ] && echo "fail to remove event path /var/run/${KBOX_NAME} !" && RET="fail"
    fi

    if [ $RET == "true" ];then
        echo "container ${KBOX_NAME} is deleted successfully."
    fi
}

function restart_box() {
    local KBOX_NAME=$1
    set +e
    mount |grep "${KBOX_NAME}.img"
    if [ $? -ne 0 ];then
        echo "mount ${KBOX_NAME}.img"
        mount /root/mount/img/${KBOX_NAME}.img /root/mount/data/${KBOX_NAME} >/dev/null
    fi
    docker inspect ${KBOX_NAME} >/dev/null
    if [ $? -ne 0 ]; then
        # 无容器判断
        break
    fi

    for i in $(seq 1 3)
    do
        docker stop -t 0 ${KBOX_NAME}
        docker start ${KBOX_NAME}
        for i in $(seq 1 3)
        do {
            docker inspect ${KBOX_NAME} --format {{.State.Status}} |grep running
            if [ $? -eq 0 ];then
                    # 等待容器状态为 running
                    break
            fi
            sleep 1
        } done
        docker exec -itd ${KBOX_NAME} /kbox-init.sh

        local count_time=0
        while true; do
            docker exec -i ${KBOX_NAME} getprop sys.boot_completed | grep 1 >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                # 等待容器启动完成
                break
            fi
            if [ ${count_time} -gt 50 ]; then
                echo -e "\033[1;31m reStart check timed out,${KBOX_NAME} unable to restart\033[0m"
                break
            fi
            sleep 1
            count_time=$((count_time + 1))
        done

        docker exec -it ${KBOX_NAME} logcat -d |grep "addInterfaceToNetwork() failed"
        if [ $? -ne 0 ];then
            # 无异常日志
            break
        fi
    done
}

check_environment
CMD=$1; shift
case $CMD in
    start)      start_box   "$@";;
    delete)     delete_box  "$@";;
    restart)    restart_box "$@";;
    *)          echo "command must be \"start\", \"delete\" or \"restart\" " ;;
esac
