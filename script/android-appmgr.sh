#!/bin/bash
# 脚本解释器 强制设置为 bash
if [ "$BASH" != "/bin/bash" ] && [ "$BASH" != "/usr/bin/bash" ]
then
   bash "$0" "$@"
   exit $?
fi
cmd=""
opt=$1
#命令为空退出
if [ "$opt" = "" ]; then
    echo "no cmd!"
    exit 3
fi
#creaticon
if [ "$opt" = "creat" ]; then
    pName=$2
    path=$3
    if [ -d "${path}" ] && [ -n "${pName}" ]; then
        cmd="/usr/bin/Kbox launcher createicon -n ${pName} -p ${path}"
    else
        echo "$path parameter error"
    fi
#install
elif [ "$opt" = "install" ]; then
    param=$2
    if [ "$param" = "-r" ]; then
        cmd="/usr/bin/Kbox launcher install -r y"
        param=$3
    else
        cmd="/usr/bin/Kbox launcher install"
    fi
    if [ -f "${param}" ]; then
        if [ "${param##*.}" = "apk" ]; then
            cmd="$cmd -p $param"
        else
            echo "\"$param\" file illegal"
            exit 4
        fi
    else
        echo "$param not found!"
        exit 5
    fi

# uninstall
elif [ "$opt" = "uninstall" ]; then
    cmd="/usr/bin/Kbox launcher uninstall"
    package=
    temp_opt="-n"
    mm=($*)
    for (( i=1; i < $#; i++ ))
    do
        param=${mm[$i]}
        if [ "${param:0:1}" = "-" ]; then
            for ((j=1; j<${#param}; j++)); do
                uninstall_opt=${param:j:1}
                if [ "$uninstall_opt" = "f" ]; then
                    temp_opt="-f"
                elif [ "$uninstall_opt" = "p" ]; then
                    temp_opt="-n"
                elif [ "$uninstall_opt" = "k" ]; then
                    cmd="$cmd -r y"
                else
                    echo "\"$uninstall_opt\" unknown uninstall type"
                fi
            done
        else
            break
        fi
    done
    if [ "$param" = "" ]; then
        echo "no file or package!"
        exit 6
    fi
#以快捷方式文件名为关键字卸载,通过解析快捷方式得到需要卸载的包名
    if [ "$temp_opt" = "f" ]; then
        if [ -f "${param}" ]; then
            content=$(cat "${param}")
        else
            echo "\"$param\" file not found!"
            exit 7
        fi
        temp=${content##*-n}
        package=${temp%% -c*}
    else
        package=$param
    fi
    cmd="$cmd $temp_opt $package"


#获取已安装应用
elif [ "$opt" = "package-list" ]; then
    cmd="/usr/bin/Kbox launcher listpackages"

#查看服务是否就绪
elif [ "$opt" = "checkready" ]; then
    cmd="/usr/bin/Kbox launcher checkready"

#查看某应用的版本
elif [ "$opt" = "package-version" ]; then
    if [ "$2" = "" ]; then
        echo "no package name"
        exit 8
    fi
    cmd="/usr/bin/Kbox launcher dumppackage -n $2"

#clean 不卸载app，删除应用的用户数据
elif [ "$opt" = "clean" ]; then
    if [ "$2" = "" ]; then
        echo "no package!"
        exit 9
    fi
#
    cmd="docker exec -it android_1 pm clear $2"
elif [ "$opt" = "shell" ]; then
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: You need to run this script as root!"
        exit 1
    fi
    cmd="sh"
    if [ "$2" != "" ]; then
        cmd=$2
    fi
    docker exec -it android_1 ${cmd}
else
    echo "\"$opt\" unknown cmd!"
    exit 10
fi

info=$($cmd >> /dev/stderr)

if [ "$opt" = "package-list" ]; then
    if [ $? != 0 ]; then
        echo "$opt failed! err-msg:$info"
        exit 11
    else
        echo "${info}"
    fi
fi

if [ "$opt" = "package-version" ]; then
   if [ $? != 0 ]; then
        echo "$opt failed! err-msg:$info"
        exit 11
    else
        echo "get version, ($2, ${info##*=})"
    fi
fi

if [ "$opt" = "shell" ]; then
    if [ $? != 0 ]; then
        echo "$opt failed! err-msg:$info"
        exit 11
    else
        echo "$opt success"
    fi
fi

exit 0
