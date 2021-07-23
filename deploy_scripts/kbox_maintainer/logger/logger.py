#!/usr/bin/env python3
# -*- encoding:utf-8 -*-
# Copyright Huawei Technologies Co., Ltd. 2021-2021. All rights reserved.

import logging
import subprocess
from pathlib import Path
from shutil import make_archive
from shutil import rmtree
from datetime import datetime
from tempfile import mkdtemp
import docker


class Logger(object):
    def __init__(self):
        self.__client = docker.from_env()
        self.log_path = Path(mkdtemp(suffix='_log', prefix='kbox_', dir=str(Path.cwd())))
        self.guestos_log_path = self.log_path / "guestos"
        self.hostos_log_path = self.log_path / "hostos"
        self.guestos_log_path.mkdir(parents=True, exist_ok=True)
        self.hostos_log_path.mkdir(parents=True, exist_ok=True)

    def _run_cmd(self, container, cmd, to_file=False):
        if container.status != 'running':
            print("container[short_id:{}, name:{}] is {}".format(
                container.short_id, container.name, container.status))
            return False

        if not cmd:
            logging.error("invalid cmd")
            return False

        exit_code, output = container.exec_run(cmd)
        if exit_code != 0:
            logging.error("cmd[{}] run failed".format(cmd))
            return False

        if to_file:
            log_name = cmd.replace(" ", "_") + ".log"
            file_path = self.guestos_log_path / container.name / log_name
            file_path.write_text(output.decode())
        return True

    def _log_one_container(self, container):
        container.reload()
        if container.status != 'running':
            print("container[short_id:{}, name:{}] is {}".format(
                container.short_id, container.name, container.status))
            return False

        container_log = self.guestos_log_path / container.name
        container_log.mkdir(parents=True, exist_ok=True)
        docker_inspect_log = container_log / "docker_inspect.log"
        with docker_inspect_log.open(mode="w") as f:
            docker_inspect_proc = subprocess.run(
                ["docker", "inspect", container.name], stdout=f)
            if docker_inspect_proc.returncode != 0:
                logging.fatal("docker inspect failed")
                return False

        log_path = "/" + self.log_path.parts[-1]
        ret_val = self._run_cmd(container, "mkdir -p " + log_path) \
            and self._run_cmd(container, "logcat -d -f " + log_path + "/logcat.log") \
            and self._run_cmd(container, "cp -r /data/anr " + log_path) \
            and self._run_cmd(container, "getprop", to_file=True) \
            and self._run_cmd(container, "dumpsys activity", to_file=True) \
            and self._run_cmd(container, "dumpsys meminfo", to_file=True) \
            and self._run_cmd(container, "dumpsys input", to_file=True) \
            and self._run_cmd(container, "ps -a", to_file=True)

        log_inside_container_tar = container_log / \
            "log_{}.tar".format(container.name)
        with log_inside_container_tar.open(mode="wb") as f:
            bits, _ = container.get_archive(log_path)
            for chunk in bits:
                f.write(chunk)

        return ret_val and self._run_cmd(container, "rm -rf " + log_path)

    def log_containers(self, containers):
        var_log = self.hostos_log_path / "var_log"
        make_archive(str(var_log), "tar", '/var/log')

        dmesg_log = self.hostos_log_path / "dmesg.log"
        with dmesg_log.open(mode="w") as f:
            dmesg_proc = subprocess.run(["dmesg", "-T"], stdout=f)
            if dmesg_proc.returncode != 0:
                logging.fatal("dmesg failed")
                return

        docker_stats_log = self.hostos_log_path / "docker_stats.log"
        with docker_stats_log.open(mode="w") as f:
            docker_stats_proc = subprocess.run(
                ["docker", "stats", "--no-stream"], stdout=f)
            if docker_stats_proc.returncode != 0:
                logging.fatal("docker stats failed")
                return

        if containers:
            containers_list = [self.__client.containers.get(
                container) for container in containers]
        else:
            containers_list = self.__client.containers.list(all=True)

        if not containers_list:
            logging.fatal("No container found")
            return

        log_failed_containers = []
        for container in containers_list:
            log_ok = self._log_one_container(container)
            if not log_ok:
                log_failed_containers.append(container)

        print("===container log report===\n")
        print("Total containers: {}\n".format(len(containers_list)))
        if log_failed_containers:
            print("log failed containers name:")
            print([container.name for container in log_failed_containers])

        if len(containers_list) > 1:
            archive_path = Path.cwd() / \
                "cloudphone_log_{}".format(
                    datetime.utcnow().strftime("%Y%m%d%H%M%S"))
        else:
            archive_path = Path.cwd() / \
                "{}_log_{}".format(
                    containers_list[0].name,
                    datetime.utcnow().strftime("%Y%m%d%H%M%S"))

        make_archive(str(archive_path), "gztar", str(self.log_path))

        print("===log finished===")
        rmtree(str(self.log_path))
