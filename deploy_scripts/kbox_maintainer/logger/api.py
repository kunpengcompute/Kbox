#!/usr/bin/env python3
# -*- encoding:utf-8 -*-

import sys
import logging
from kbox_maintainer.logger.logger import Logger


def log(containers):
    print(containers)
    if not sys.platform.startswith('linux'):
        logging.critical("This tool only support linux platform")
        exit(0)
    logger = Logger()
    logger.log_containers(containers)
