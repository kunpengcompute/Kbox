#!/usr/bin/env python3
# -*- encoding:utf-8 -*-
# Copyright Huawei Technologies Co., Ltd. 2021-2021. All rights reserved.

import sys
import logging
from kbox_maintainer.checker.checker import Checker


def check(containers):
    print(containers)
    if not sys.platform.startswith('linux'):
        logging.critical("This tool only support linux platform")
        exit(0)

    if not Checker.check_binder_ashmem():
        logging.error(
            "binder ashmem not insmod, using [kbox_maintainer.py recover]")
        return

    if not Checker.check_exagear():
        logging.error(
            "exagear not register, using [kbox_maintainer.py recover]")
        return

    checker = Checker()
    checker.check_containers(containers)


def recover(containers):
    print(containers)
    if not sys.platform.startswith('linux'):
        logging.critical("This tool only support linux platform")
        exit(0)

    if not Checker.check_binder_ashmem() and not Checker.recover_binder_ashmem():
        logging.fatal("binder ashmem cannot insmod!!!")
        return

    if not Checker.check_exagear() and not Checker.recover_exagear():
        logging.fatal(
            "exagear cannot recover!!!")
        return

    checker = Checker()
    checker.recover_containers(containers)
