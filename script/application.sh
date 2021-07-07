#!/bin/bash
opt=$1
#命令为空退出
if [ "$opt" = "" ]; then
    echo "no cmd!"
    exit 3
fi

user=$(logname)
su ${user} -s /bin/bash -c "/usr/bin/android-appmgr.sh $1 $2 $3"
sleep 5
package_list=$(ls /home/Kbox/desktop/ |grep desktop |awk -F '.desktop' '{print $1}')
for package in ${package_list}
do      
    /usr/bin/Kbox launcher createicon -n "${package}" -p /usr/share/applications/ >/dev/null || true 
done
exit 0
