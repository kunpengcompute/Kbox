#!/usr/bin/env python3
# -*- encoding:utf-8 -*-

import logging
import subprocess
import stat
from pathlib import Path
import docker


class Checker(object):

    def __init__(self):
        self.__client = docker.from_env()

    @staticmethod
    def _check_one_container(container):
        container.reload()
        if container.status != 'running':
            print("container[short_id:{}, name:{}] is {}".format(
                container.short_id, container.name, container.status))
            return False

        exit_code, output = container.exec_run("getprop sys.boot_completed")
        if exit_code != 0:
            print("container[name:{}] getprop failed, exit_code={}".format(
                container.name, exit_code))
            return False

        if output != b'1\n':
            print("container[name:{}] system boot is incomplete!!!".format(
                container.name))
            return False

        return True

    def check_containers(self, containers):
        if containers:
            containers_list = [self.__client.containers.get(
                container) for container in containers]
        else:
            containers_list = self.__client.containers.list(all=True)

        unhealthy_containers = []
        for container in containers_list:
            healthy = Checker._check_one_container(container)
            if not healthy:
                unhealthy_containers.append(container)

        print("===container check report===\n")
        print("Total checked containers: {}\n".format(len(containers_list)))
        if unhealthy_containers:
            print("unhealth containers name:")
            print([container.name for container in unhealthy_containers])
        else:
            print("All the checked containers are healthy!")

        return unhealthy_containers

    @staticmethod
    def _recover_one_container(container):
        # exec android9_kbox.sh scripts
        container_no = container.name.split('_')[1]
        cmd = Path.cwd() / "android9_kbox.sh"
        base_cmd = Path.cwd() / "base_box.sh"
        if not cmd.is_file() or not base_cmd.is_file():
            logging.fatal("{} is not found".format(str(cmd)))
            return

        cmd.chmod(mode=cmd.stat().st_mode | stat.S_IXUSR)
        base_cmd.chmod(mode=base_cmd.stat().st_mode | stat.S_IXUSR)

        subprocess.run([str(cmd), "restart", container_no])

    def recover_containers(self, containers):
        unhealthy_containers = self.check_containers(containers)
        if not unhealthy_containers:
            return []

        for container in unhealthy_containers:
            Checker._recover_one_container(container)

        unrecover_containers = []
        for container in unhealthy_containers:
            if not Checker._check_one_container(container):
                unrecover_containers.append(container)

        print("===container recover report===\n")
        if unrecover_containers:
            print("unrecover containers name:")
            print([container.name for container in unrecover_containers])
        else:
            print("All the containers are recovered!")

        return unrecover_containers

    @staticmethod
    def check_exagear():
        exagear = Path("/proc/sys/fs/binfmt_misc/ubt_a32a64")
        return exagear.is_file() and exagear.read_text().startswith("enabled")

    @staticmethod
    def recover_exagear():
        # exec android9_kbox.sh scripts
        cmd = Path.cwd() / "android9_kbox.sh"
        base_cmd = Path.cwd() / "base_box.sh"
        if not cmd.is_file() or not base_cmd.is_file():
            logging.fatal("{} is not found".format(str(cmd)))
            return

        cmd.chmod(mode=cmd.stat().st_mode | stat.S_IXUSR)
        base_cmd.chmod(mode=base_cmd.stat().st_mode | stat.S_IXUSR)

        subprocess.run([str(cmd), "restart"])
        return Checker.check_exagear()

    @staticmethod
    def check_binder_ashmem():
        lsmod_proc = subprocess.run(["lsmod"], capture_output=True)
        check_ashmem = subprocess.run(
            ["grep", "ashmem"], input=lsmod_proc.stdout, capture_output=True)
        check_binder = subprocess.run(
            ["grep", "binder"], input=lsmod_proc.stdout, capture_output=True)

        return check_ashmem.returncode == 0 and check_binder.returncode == 0

    @staticmethod
    def recover_binder_ashmem():
        binder = Path("/lib/modules/5.4.30/kernel/lib/aosp9_binder_linux.ko")
        ashmem = Path("/lib/modules/5.4.30/kernel/lib/ashmem_linux.ko")

        if not (binder.is_file() and ashmem.is_file()):
            logging.error(".ko file not found")
            return False

        insmod_binder = subprocess.run(
            ["insmod", str(binder), "num_devices=400"])
        if insmod_binder.returncode != 0:
            logging.error("insmod binder failed")
            return False

        insmod_ashmem = subprocess.run(["insmod", str(ashmem)])
        if insmod_ashmem.returncode != 0:
            logging.error("insmod ashmem failed")
            return False

        return Checker.check_binder_ashmem()
