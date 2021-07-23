#!/usr/bin/env python3
# -*- encoding:utf-8 -*-
# Copyright Huawei Technologies Co., Ltd. 2021-2021. All rights reserved.

import sys
import logging
from kbox_maintainer.resource.resource import Resource


def resource(containers):
    print(containers)
    if not sys.platform.startswith('linux'):
        logging.critical("This tool only support linux platform")
        exit(0)
    res = Resource()
    res.resource_containers(containers)
