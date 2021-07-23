#!/bin/bash
# Copyright Huawei Technologies Co., Ltd. 2020-2020. All rights reserved.

set -e

kbox_name=$1
if [ -z "$1" ]
then
echo no kbox_name
exit 1
fi

if [ ! -d ./1080pi ]
then
echo no 1080pi
exit 1 
else
mkdir -p backup/lib
mkdir -p backup/lib64
docker cp $kbox_name:/system/lib/hw/gralloc.gbm.so backup/lib/
docker cp $kbox_name:/system/vendor/lib/hw/hwcomposer.huawei.so backup/lib/
docker cp $kbox_name:/system/lib64/hw/gralloc.gbm.so backup/lib64/
docker cp $kbox_name:/system/vendor/lib64/hw/hwcomposer.huawei.so backup/lib64/

docker cp 1080pi/lib/gralloc.gbm.so $kbox_name:/system/lib/hw/
docker cp 1080pi/lib/hwcomposer.huawei.so $kbox_name:/system/vendor/lib/hw/
docker cp 1080pi/lib64/gralloc.gbm.so $kbox_name:/system/lib64/hw/
docker cp 1080pi/lib64/hwcomposer.huawei.so $kbox_name:/system/vendor/lib64/hw/
fi

docker restart $kbox_name

echo success