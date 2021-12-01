#!/bin/bash

function check_environment() {
    # root权限执行此脚本
    if [ "${UID}" -ne 0 ]; then
        echo  "请使用root权限执行"
        exit 1
    fi

    # 支持非当前目录执行
    CURRENT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    echo "Current Path:$CURRENT_DIR"
    cd ${CURRENT_DIR}

    check_ashmem_binder
    check_exagear
}

function check_ashmem_binder() {
    # 已经加载无需恢复
    if [ ! -z $(lsmod | grep "aosp9_binder_linux" | awk '{print $1}') ] && 
       [ ! -z $(lsmod | grep "ashmem_linux" | awk '{print $1}') ]; then
        return
    fi

    if [ -z $(lsmod | grep "aosp9_binder_linux" | awk '{print $1}') ]; then
        if [ -e "/lib/modules/5.4.30/kernel/lib/aosp9_binder_linux.ko" ]; then
            insmod /lib/modules/5.4.30/kernel/lib/aosp9_binder_linux.ko num_devices=400
        else
            echo "can not find aosp9_binder_linux.ko"
            exit 1
        fi
    fi

    if [ -z $(lsmod | grep "ashmem_linux" | awk '{print $1}') ]; then
        if [ -e "/lib/modules/5.4.30/kernel/lib/ashmem_linux.ko" ]; then
            insmod /lib/modules/5.4.30/kernel/lib/ashmem_linux.ko
        else
            echo "can not find ashmem_linux.ko"
            exit 1
        fi
    fi
        
    chmod 600 /dev/aosp9_binder*
    chmod 600 /dev/ashmem 
    chmod 600 /dev/dri/* 
    chmod 600 /dev/input
}

function check_exagear() {
    # 已经注册，无需恢复
    if [ -e "/proc/sys/fs/binfmt_misc/ubt_a32a64" ];then
        return
    fi

    # 在归档路径下模糊查找
    local UBT_PATHS=($(ls /root/dependency/*/ubt_a32a64))
    if [ ${#UBT_PATHS[@]} -ne 1 ];then
        echo "No ubt_a32a64 file or many ubt_a32a64 files exist!"
        exit 1
    fi

    # 恢复exgear文件
    mkdir -p /opt/exagear
    chmod -R 700 /opt/exagear
    cp -rf ${UBT_PATHS[0]} /opt/exagear/
    cd /opt/exagear
    chmod +x ubt_a32a64

    # 注册转码 续行符后字符串顶格
    echo ":ubt_a32a64:M::\x7fELF\x01\x01\x01\x00\x00\x00\x0"\
"0\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xf"\
"f\xff\xff\xff\xff\x00\x00\x00\x00\x00\x00\x00\x00"\
"\x00\xfe\xff\xff\xff:/opt/exagear/ubt_a32a64:POCF" > /proc/sys/fs/binfmt_misc/register
}

function check_paras() {
    set +e
    
    if [ $# -eq 0 ];then
        echo "command must be \"start\", \"delete\" or \"restart\" "
        exit 1
    fi

    if [ $1 == "start" ]; then
        if [ $# -gt 4 ]; then
            echo "the number of parameters exceeds 4!"
            echo "Usage: "
            echo "./android9_kbox.sh start <image_id> <start_container_id> <end_container_id>"
            echo "./android9_kbox.sh start <image_id> <container_id>"
            exit 1;
        fi

        local IMAGE_ID=$2
        if [[ "${IMAGE_ID}" =~ ":" ]]; then
            local IMAGE_RE=$(echo ${IMAGE_ID} | cut -d ':' -f1)
            tag=$(echo ${IMAGE_ID} | cut -d ':' -f2)
            docker images | awk '{print $1" "$2}' | grep -w "${IMAGE_RE}" | grep -w "${tag}" >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo "no image ${IMAGE_ID}"
                exit 1
            fi
        else
            docker images | awk '{print $3}' | grep -w "${IMAGE_ID}" >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo "no image ${IMAGE_ID}"
                exit 1
            fi
        fi

        if [ -n "`echo "$3$4" | sed 's/[0-9]//g'`" ]; then
            echo "The third and fourth parameters must be numbers."
            exit 1
        fi

        local MIN=$3 MAX=$4
        if [ -z "$4" ];then
            MAX=$3
        fi

        if [ $MIN -gt $MAX ]; then
            echo "start_num must be less than or equal to end_num"
            exit 1
        fi
    elif [ $1 == "delete" ]; then
        if [ $# -gt 3 ]; then
            echo "the number of parameters exceeds 3!"
            echo "Usage: "
            echo "./android9_kbox.sh delete <start_container_id> <end_container_id>"
            echo "./android9_kbox.sh delete <container_id>"
            exit 1
        fi

        if [ -n "`echo "$2$3" | sed 's/[0-9]//g'`" ]; then
            echo "The second and third parameters must be numbers."
            exit 1
        fi

        local MIN=$2 MAX=$3
        if [ -z $3 ];then
            MAX=$2
        fi

        if [ $MIN -gt $MAX ]; then
            echo "start_num must be less than or equal to end_num"
            exit 1
        fi
    elif [ $1 == "restart" ]; then
        if [ $# -gt 3 ]; then
            echo "the number of parameters exceeds 3!"
            echo "Usage: "
            echo "./android9_kbox.sh restart <start_container_id> <end_container_id>"
            echo "./android9_kbox.sh restart <container_id>"
            exit 1
        fi

        if [ -n "`echo "$2$3" | sed 's/[0-9]//g'`" ]; then
            echo "The second and third paramelters must be numbers."
            exit 1
        fi

        local MIN=$2 MAX=$3
        if [ -z $3 ];then
            MAX=$2
        fi

        if [ $MIN -gt $MAX ]; then
            echo "start_num must be less than or equal to end_num"
            exit 1
        fi
    else
        echo "command must be \"start\", \"delete\" or \"restart\" "
    fi
}

function get_num_of_cpus() {
    echo $(lscpu | grep -w "CPU(s)" | head -n 1 | awk '{print $2}')
}

function get_gpu_info() {
    local PCI_IDS=$(lspci -D | grep "AMD" | grep "VGA" | awk '{print $1}')
    local GPU_DEV_NODE GPU_NUMA_NODE
    for ID in ${PCI_IDS}; do
        GPU_DEV_NODE=$(ls /sys/bus/pci/devices/$ID/drm/ | grep renderD)
        GPU_NUMA_NODE=$(cat /sys/bus/pci/devices/$ID/numa_node)
        echo $ID","$GPU_DEV_NODE","$GPU_NUMA_NODE
    done
    return
}

function get_closest_numas() {
    local NUM_OF_CPUS=$(lscpu | grep -w "CPU(s)" | head -n 1 | awk '{print $2}')
    local CPU t1=0 t2=0
    for CPU in $@; do
        if [ ${CPU} -lt $((${NUM_OF_CPUS} / 2)) ]; then
            t1=$((t1+1))
        else
            t2=$((t2+1))
        fi
    done

    local NUM_OF_NUMA=$(lscpu | grep "NUMA node(s)" | awk '{print $3}')
    if [ $t1 -gt $t2 ]; then
        NUMA_START=0
    else
        NUMA_START=$((${NUM_OF_NUMA} / 2))
    fi

    local NUMA MEM;
    for ((NUMA=NUMA_START; \
          NUMA < $((NUMA_START)) + $((${NUM_OF_NUMA}/2)); NUMA++))
    do
        echo $NUMA
    done
}

function get_closest_gpus() {
    local NUM_OF_CPUS=$(lscpu | grep -w "CPU(s)" | head -n 1 | awk '{print $2}')
    local CPU t1=0 t2=0
    for CPU in $@; do
        if [ ${CPU} -lt $((${NUM_OF_CPUS} / 2)) ]; then
            t1=$((t1+1))
        else
            t2=$((t2+1))
        fi
    done

    local PCI_IDS=($(lspci -D | grep "AMD" | grep "VGA" | awk '{print $1}'))
    local GPU_NUMA_NODES i
    local GPU_DEV_NODES GPU_NUMA_NODES
    for ((i=0; i<${#PCI_IDS[@]}; i++))
    do
        GPU_DEV_NODES[$i]=$(ls /sys/bus/pci/devices/${PCI_IDS[$i]}/drm/ | grep renderD)
        GPU_NUMA_NODES[$i]=$(cat /sys/bus/pci/devices/${PCI_IDS[$i]}/numa_node)
    done
    
    local NUM_OF_NUMAS=$(lscpu | grep "NUMA node(s)" | awk '{print $3}')
    for ((i=0; i<${#GPU_NUMA_NODES[@]}; i++))
    do
        if [ $t1 -gt $t2 ]; then
            if [ ${GPU_NUMA_NODES[$i]} -lt $((NUM_OF_NUMAS / 2)) ]; then
                echo "/dev/dri/"${GPU_DEV_NODES[$i]}
            fi
        else
            if [ ${GPU_NUMA_NODES[$i]} -ge $((NUM_OF_NUMAS / 2)) ]; then
                echo "/dev/dri/"${GPU_DEV_NODES[$i]}
            fi
        fi
    done
}

function get_cpus_by_id() {
    # TAG_NUMBER：容器标号, CPUS_NUM_PER_CNTR：每个容器分配的CPU数量
    local TAG_NUMBER=$1 CPUS_NUM_PER_CNTR=$2
    
    # 预留CPU
    local RESERVE_CPUS_WITH_NUMA0_1=$3
    local RESERVE_CPUS_WITH_NUMA2_3=$4
    local NUM_OF_CPUS=$(lscpu | grep -w "CPU(s)" | head -n 1 | awk '{print $2}')

    # 剩余可用CPU，不同的NUMA组分开
    local NUM_OF_CPUS_WITH_NUMA0_1=$(((${NUM_OF_CPUS} / 2) - ${RESERVE_CPUS_WITH_NUMA0_1}))
    local NUM_OF_CPUS_WITH_NUMA2_3=$(((${NUM_OF_CPUS} / 2) - ${RESERVE_CPUS_WITH_NUMA2_3}))

    # 三个核为一组
    local NUM_OF_CPU_GROUPS_WITH_NUMA0_1=$((${NUM_OF_CPUS_WITH_NUMA0_1} / 3))
    local NUM_OF_CPU_GROUPS_WITH_NUMA2_3=$((${NUM_OF_CPUS_WITH_NUMA2_3} / 3))

    # 计算总组数
    NUM_OF_CPU_GROUPS=$((${NUM_OF_CPU_GROUPS_WITH_NUMA0_1} + ${NUM_OF_CPU_GROUPS_WITH_NUMA2_3}))

    local MID=$(((${TAG_NUMBER} + 1) / 2))
    if [ $((($MID - 1) % ${NUM_OF_CPU_GROUPS})) -lt ${NUM_OF_CPU_GROUPS_WITH_NUMA0_1} ]; then
        CPU_START=$((((($MID - 1) % ${NUM_OF_CPU_GROUPS}) * 3) + ${RESERVE_CPUS_WITH_NUMA0_1}))
    else
        CPU_START=$((((($MID - 1) % ${NUM_OF_CPU_GROUPS}) * 3) + ${RESERVE_CPUS_WITH_NUMA2_3} + ${RESERVE_CPUS_WITH_NUMA0_1}))
    fi
    CPU_START=$((${CPU_START} + ${TAG_NUMBER} - ${MID} * 2))
    CPU_END=$((${CPU_START} + $CPUS_NUM_PER_CNTR - 1))

    local CPU CPUS
    for CPU in $(seq $CPU_START $CPU_END); do
        echo $CPU
    done

    return
}

function wait_container_ready() {
    local KBOX_NAME=$1
    docker exec -itd ${KBOX_NAME} /kbox-init.sh
    local starttime=$(date +'%Y-%m-%d %H:%M:%S')
    local start_seconds=$(date --date="${starttime}" +%s)
    if [ $? -eq 0 ]; then
        count_time=0
        set +e
        while true; do
            docker exec -i ${KBOX_NAME} getprop sys.boot_completed | grep 1 >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo "${KBOX_NAME} started successfully at $(date +'%Y-%m-%d %H:%M:%S')!"
                if [ -f "apk_init.sh" ]; then
                    sed -i "s/\r//" apk_init.sh
                    docker cp apk_init.sh ${KBOX_NAME}:/
                fi
                break
            fi
            # 30秒未成功启动超时跳过
            if [ ${count_time} -gt 50 ]; then
                echo -e "\033[1;31mStart check timed out,${KBOX_NAME} unable to start\033[0m"
                echo -e "\033[1;31m${KBOX_NAME} started failed\033[0m"
                break
            fi
            sleep 1
            count_time=$((count_time + 1))
        done
        set -e
    else
        error "${KBOX_NAME} started failed"
    fi
    local endtime=$(date +'%Y-%m-%d %H:%M:%S')
    local end_seconds=$(date --date="${endtime}" +%s)
    echo "time: "$((end_seconds - start_seconds))"s"
    echo -e "---------------------- done ----------------------\n"
}

function disable_ipv6_icmp() {
    # 更改容器内部accept_redirects参数配置，禁止ipv6的icmp重定向功能
    KBOX_NAME=$1
    temp=$(mktemp)
    echo 0 > $temp
    pid=$(docker inspect ${KBOX_NAME} | grep Pid | awk -F, '{print $1}' | sed -n '1p' | awk '{print $2}')
    nsenter -n -t ${pid} cp $temp /proc/sys/net/ipv6/conf/all/accept_redirects
    rm $temp
}

function start_box_by_id() {
    # 镜像名
    local IMAGE_NAME=$2

    # 容器编号
    local TAG_NUMBER=$3

    # 没有GPU不启动容器
    local GPUS_INFO=($(lspci -D | grep "AMD" | grep "VGA" | awk '{print $1}'))
    if [ ${#GPUS_INFO[@]} -eq 0 ]; then
        echo "No GPU exists on the host"
        exit 1
    fi

    local RESERVE_CPUS_WITH_NUMA0_1=4
    local RESERVE_CPUS_WITH_NUMA2_3=0

    # 不跨numa，没有GPU的numa对应的CPU全部保留不使用
    local NUM_OF_GPUS_WITH_NUMA0_1=$(get_gpu_info | grep -e ",0$" -e ",1$"| wc -l)
    if [ ${NUM_OF_GPUS_WITH_NUMA0_1} -eq 0 ]; then
        RESERVE_CPUS_WITH_NUMA0_1=$(($(get_num_of_cpus)/2))
    fi
    local NUM_OF_GPUS_WITH_NUMA2_3=$(get_gpu_info | grep -e ",2$" -e ",3$"| wc -l)
    if [ ${NUM_OF_GPUS_WITH_NUMA2_3} -eq 0 ]; then
        RESERVE_CPUS_WITH_NUMA2_3=$(($(get_num_of_cpus)/2))
    fi

    # 容器名
    local CONTAINER_NAME="kbox_$TAG_NUMBER"

    # CPUS
    local CPUS_NUM_PER_CNTR=2
    
    local CPUS=($(get_cpus_by_id $TAG_NUMBER $CPUS_NUM_PER_CNTR \
                  $RESERVE_CPUS_WITH_NUMA0_1 $RESERVE_CPUS_WITH_NUMA2_3))

    # 存储大小
    local STORAGE_SIZE_GB=16

    # 运行内存
    local RAM_SIZE_MB=4096

    # NUMA
    local NUMAS=($(get_closest_numas ${CPUS[@]}))

    # GPU
    local GPUS_RENDER=($(get_closest_gpus ${CPUS[@]}))
    GPUS_RENDER=(${GPUS_RENDER[$(($TAG_NUMBER % ${#GPUS_RENDER[@]}))]})

    # Binder
    local BINDER_NODES=("/dev/aosp9_binder$TAG_NUMBER" \
                        "/dev/aosp9_binder$(($TAG_NUMBER + 120))" \
                        "/dev/aosp9_binder$(($TAG_NUMBER + 240))")

    # 调试端口
    local PORTS=("$((8500+$TAG_NUMBER)):5555")

    # docker额外启动参数
    local EXTRA_RUN_OPTION

    bash $CURRENT_DIR/base_box.sh start \
    --name "$CONTAINER_NAME" \
    --cpus "${CPUS[*]}" \
    --numas "${NUMAS[*]}" \
    --gpus  "${GPUS_RENDER[*]}" \
    --storage_size_gb "$STORAGE_SIZE_GB" \
    --ram_size_mb "$RAM_SIZE_MB" \
    --binder_nodes "${BINDER_NODES[*]}" \
    --ports "${PORTS[*]}" \
    --extra_run_option "$EXTRA_RUN_OPTION" \
    --image "$IMAGE_NAME"

    # 调整vinput设备权限
    cid=$(docker ps | grep -w ${CONTAINER_NAME} | awk '{print $1}')
    echo "c 13:* rwm" >$(ls -d /sys/fs/cgroup/devices/docker/$cid*/devices.allow)

    if [ -n "$(docker ps -a --format {{.Names}} | grep "$CONTAINER_NAME$")" ]; then
        # 等待容器启动
        wait_container_ready ${CONTAINER_NAME}

        # 更改容器内部accept_redirects参数配置，禁止ipv6的icmp重定向功能
        disable_ipv6_icmp ${CONTAINER_NAME}
    fi
}

function main() {
    if [ ! -e "$CURRENT_DIR/base_box.sh" ]; then
        echo "Can not find file base_box.sh"
        exit 1
    fi

    if [ $1 = "start" ];then
        local MIN=$3 MAX=$4
        if [ -z $4 ];then
            MAX=$3
        fi

        local TAG_NUMBER
        for TAG_NUMBER in $(seq $MIN $MAX); do
            if [ -n "$(docker ps -a --format {{.Names}} | grep "kbox_$TAG_NUMBER$")" ]; then
                echo "kbox_$TAG_NUMBER exist!"
            else
                start_box_by_id $1 $2 $TAG_NUMBER
            fi
        done
    elif [ $1 = "delete" ];then
        local MIN=$2 MAX=$3
        if [ -z $3 ];then
            MAX=$2
        fi

        local TAG_NUMBER
        for TAG_NUMBER in $(seq $MIN $MAX);do
            if [ -z "$(docker ps -a --format {{.Names}} | grep "kbox_$TAG_NUMBER$")" ]; then
                echo "no container kbox_$TAG_NUMBER!"
            else
                bash $CURRENT_DIR/base_box.sh delete "kbox_$TAG_NUMBER"
            fi
        done
    elif [ $1 = "restart" ];then
        local MIN=$2 MAX=$3
        if [ -z $3 ];then
            MAX=$2
        fi
        local TAG_NUMBER
        for TAG_NUMBER in $(seq $MIN $MAX);do
            if [ -z "$(docker ps -a --format {{.Names}} | grep "kbox_$TAG_NUMBER$")" ]; then
                echo "no container kbox_$TAG_NUMBER!"
            else
                bash $CURRENT_DIR/base_box.sh restart "kbox_$TAG_NUMBER"
                # 调整vinput设备权限
                cid=$(docker ps | grep -w "kbox_$TAG_NUMBER" | awk '{print $1}')
                echo "c 13:* rwm" >$(ls -d /sys/fs/cgroup/devices/docker/$cid*/devices.allow)
            fi
        done
    fi
}

check_environment
check_paras $@
main "$@"