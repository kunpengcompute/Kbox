#!/usr/bin/env python3
# -*- encoding:utf-8 -*-

import logging
import subprocess
from pathlib import Path
from shutil import make_archive
from shutil import copy
from shutil import rmtree
from shutil import copytree
from datetime import datetime
from tempfile import mkdtemp
import docker


class Resource(object):
    def __init__(self):
        self.__client = docker.from_env()
        self.res_path = Path(mkdtemp(suffix='_res', prefix='kbox_', dir=str(Path.cwd())))
        self.guestos_res_path = self.res_path / "guestos"
        self.hostos_res_path = self.res_path / "hostos"
        self.guestos_res_path.mkdir(parents=True, exist_ok=True)
        self.hostos_res_path.mkdir(parents=True, exist_ok=True)

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
            file_path = self.guestos_res_path / container.name / log_name
            file_path.write_text(output.decode())
        return True

    def _resource_one_container(self, container):
        container.reload()
        if container.status != 'running':
            print("container[short_id:{}, name:{}] is {}".format(
                container.short_id, container.name, container.status))
            return False

        container_res = self.guestos_res_path / container.name
        container_res.mkdir(parents=True, exist_ok=True)

        temp_res_path = "/data/" + self.res_path.parts[-1]
        ret_val = self._run_cmd(container, "mkdir -p " + temp_res_path) \
            and self._run_cmd(container, "cp -r /proc/cpuinfo " + temp_res_path) \
            and self._run_cmd(container, "dumpsys meminfo", to_file=True) \
            and self._run_cmd(container, "top -n1", to_file=True) \
            and self._run_cmd(container, "df -h", to_file=True) \
            and self._run_cmd(container, "lspci", to_file=True)
        
        src_path = "/root/mount/data/" + container.name + temp_res_path
        dst_path = str(container_res / "data")
        copytree(src_path, dst_path)

        return ret_val and self._run_cmd(container, "rm -rf " + temp_res_path)

    def resource_containers(self, containers):
        admgpu_pm_info_pathes = Path(
            "/sys/kernel/debug/dri/").glob('*/amdgpu_pm_info')
        for src_path in admgpu_pm_info_pathes:
            dst_path = self.hostos_res_path / \
                "amdgpu_pm_info_{}".format(src_path.parts[-2])
            copy(str(src_path), str(dst_path))

        if containers:
            containers_list = [self.__client.containers.get(
                container) for container in containers]
        else:
            containers_list = self.__client.containers.list(all=True)

        if not containers_list:
            logging.fatal("No container found")
            return

        res_failed_containers = []
        for container in containers_list:
            res_ok = self._resource_one_container(container)
            if not res_ok:
                res_failed_containers.append(container)

        print("===container resource report===\n")
        print("Total containers: {}\n".format(len(containers_list)))
        if res_failed_containers:
            print("resource failed containers name:")
            print([container.name for container in res_failed_containers])

        if len(containers_list) > 1:
            archive_path = Path.cwd() / \
                "cloudphone_res_{}".format(
                    datetime.utcnow().strftime("%Y%m%d%H%M%S"))
        else:
            archive_path = Path.cwd() / \
                "{}_res_{}".format(
                    containers_list[0].name,
                    datetime.utcnow().strftime("%Y%m%d%H%M%S"))

        make_archive(str(archive_path), "gztar", str(self.res_path))

        print("===resource stats finished===")
        rmtree(str(self.res_path))