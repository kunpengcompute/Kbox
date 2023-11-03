package agent

import (
	"bufio"
	"errors"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"k8s.io/klog"
	"sigs.k8s.io/yaml"
)

const resctrlRoot = "/sys/fs/resctrl/"
const resctrlSchemataFile = "schemata"
const cgroupCpusetRoot = "/sys/fs/cgroup/cpuset/"
const tasksFile = "tasks"
const numclosidFile = "info/L3/num_closids"
const cbmmaskFile = "info/L3/cbm_mask"
const maxGroupnameLen = 64

var num_closids int
var cbm_mask string
var max_cbm_num uint64

// getNumclosids gets the maximun number of mpam groups
func getNumclosids() bool {
	path := filepath.Join(resctrlRoot, numclosidFile)
	if _, err := os.Stat(path); err != nil {
		klog.Errorf("%q is not exist: %v", path, err)
		klog.Warning("Please ensure mpam has been mounted")
		return false
	}

	closids, err := ioutil.ReadFile(path)
	if err != nil {
		klog.Errorf("Failed to read num_closids (%q): %v", path, err)
		klog.Warning("Please ensure mpam has been mounted")
		return false
	}

	if num_closids, err = strconv.Atoi(strings.Replace(string(closids), "\n", "", -1)); err != nil {
		klog.Errorf("string to int failed: %v", err)
		return false
	}

	klog.Info("maximun number of mpam groups is: ", num_closids)
	return true
}

// getCbmmask get the cbm_mask of L3 cache
func getCbmmask() bool {
	path := filepath.Join(resctrlRoot, cbmmaskFile)
	if _, err := os.Stat(path); err != nil {
		klog.Errorf("%q is not exist: %v", path, err)
		klog.Warning("Please ensure mpam has been mounted")
		return false
	}

	cbm_mask_string, err := ioutil.ReadFile(path)
	if err != nil {
		klog.Errorf("Failed to read ncbm_mask (%q): %v", path, err)
		klog.Warning("Please ensure mpam has been mounted")
		return false
	}

	cbm_mask = strings.Replace(string(cbm_mask_string), "\n", "", -1)
	klog.Info("cbm_mask is ", cbm_mask)

	if max_cbm_num, err = strconv.ParseUint("0x"+cbm_mask, 0, 0); err != nil {
		klog.Errorf("string to int failed: %v", err)
		return false
	}

	klog.Info("max_cbm_num is: ", max_cbm_num)
	return true
}

// cleanResctrlGroup removes resctrl group that not in 'groups'
func cleanResctrlGroup(groups []string) {
	fis, err := ioutil.ReadDir(resctrlRoot)
	if err != nil {
		klog.Errorf("resctrlRoot is not exist, please ensure resctrl fs has been mounted")
		return
	}
	for _, fi := range fis {
		if !fi.IsDir() {
			klog.Warning("fi ia not a dir")
			continue
		}
		found := false
		for _, group := range groups {
			if group == fi.Name() {
				found = true
				break
			}
		}

		if found {
			continue
		}

		path := filepath.Join(resctrlRoot, fi.Name(), resctrlSchemataFile)
		_, err := os.Lstat(path)
		if err == nil || os.IsExist(err) {
			os.Remove(filepath.Join(resctrlRoot, fi.Name()))
			klog.Info(filepath.Join(resctrlRoot, fi.Name()) + " is removed")
		}
	}
}

func updateResctrlGroup(dir, data string) {
	// create resctrl group if it doesn't exist
	if _, err := os.Lstat(dir); os.IsNotExist(err) {
		if err := os.MkdirAll(dir, 0755); err != nil {
			klog.Errorf("Failed to create directory %v: %v", dir, err)
			return
		}
	}

	if err := ioutil.WriteFile(filepath.Join(dir, resctrlSchemataFile), []byte(data+"\n"), 0600); err != nil {
		klog.Errorf("Failed to write %v to %v: %v", data, dir, err)
	}
}

func checkDataIsValid(data []string, cfgItem string) bool {
	if len(data) > 4 {
		return false
	}

	for _, numa_data := range data {
		cfg := strings.Split(numa_data, "=")
		if len(cfg) != 2 {
			return false
		}

		numa_id, err := strconv.Atoi(cfg[0])
		if err != nil || numa_id > 3 {
			return false
		}

		if strings.HasPrefix(cfgItem, "L3") {
			cache_num, err := strconv.ParseUint("0x"+cfg[1], 0, 0)
			if err != nil {
				return false
			}

			if cache_num <= 0 || cache_num > max_cbm_num {
				return false
			}
		} else if strings.HasPrefix(cfgItem, "MB") {
			percent, err := strconv.Atoi(cfg[1])
			if err != nil || (percent < 0 || percent > 100) {
				return false
			}
		}
	}
	return true
}

func checkConfig(rcdata string) bool {
	config := strings.Split(rcdata, ":")
	if len(config) > 2 {
		return false
	}

	if !strings.HasPrefix(config[0], "L3") && !strings.HasPrefix(config[0], "MB") {
		return false
	}

	data := strings.Split(config[1], ";")
	return checkDataIsValid(data, config[0])
}

func applyConfig(data *configData) {
	var mpamGroups []string

	if data == nil {
		cleanResctrlGroup(mpamGroups)
		return
	}

	// parse configuration data
	for _, val := range *data {
		conf := make(map[string]interface{})
		if err := yaml.Unmarshal([]byte(val), &conf); err != nil {
			klog.Errorf("Failed to unmarshal configuration data: %v", err)
			return
		}

		for key, val := range conf {
			switch {
			case key == "mpam":
				groups := val.(interface{}).(map[string]interface{})
				for grp, mpamconf := range groups {
					if len(grp) > maxGroupnameLen {
						klog.Warning("max len of group name is %v", maxGroupnameLen)
						continue
					}

					rc := mpamconf.(map[string]interface{})
					for _, v := range rc {
						rcdata := v.(interface{}).(string)
						if !checkConfig(rcdata) {
							klog.Warning("config %v is not right, please chck config", rcdata)
							continue
						}
						updateResctrlGroup(filepath.Join(resctrlRoot, grp), rcdata)
					}
					mpamGroups = append(mpamGroups, grp)
				}
			default:
				klog.Info("not mpam config")
			}
		}
	}

	if len(mpamGroups) > num_closids {
		klog.Warning("The number of groups to be created exceeds the upper limit,"+
			"only %v groups can be created", num_closids)
		mpamGroups = mpamGroups[:num_closids]
	}

	cleanResctrlGroup(mpamGroups)
}

// readPids reads pids from a cgroup's tasks file
func readPids(tasksFile string) ([]string, error) {
	var pids []string

	f, err := os.OpenFile(tasksFile, os.O_RDONLY, 0644)
	if err != nil {
		klog.Errorf("Failed to open %q: %v", tasksFile, err)
		return nil, fmt.Errorf("Failed to open %q: %v", tasksFile, err)
	}
	defer f.Close()

	s := bufio.NewScanner(f)
	for s.Scan() {
		pids = append(pids, s.Text())
	}
	if s.Err() != nil {
		klog.Errorf("Failed to read %q: %v", tasksFile, err)
		return nil, fmt.Errorf("Failed to read %q: %v", tasksFile, err)
	}

	return pids, nil
}

// writePids writes pids to a restctrl tasks file
func writePids(tasksFile string, pids []string) {
	f, err := os.OpenFile(tasksFile, os.O_WRONLY, 0644)
	if err != nil {
		klog.Errorf("Failed to write pids to %q: %v", tasksFile, err)
		return
	}
	defer f.Close()

	for _, pid := range pids {
		if _, err := f.Write([]byte(pid)); err != nil {
			if !errors.Is(err, syscall.ESRCH) {
				klog.Errorf("Failed to write pid %s to %q: %v", pid, tasksFile, err)
				return
			}
		}
	}
}

func assignMPAMControlGroup(dir, rcgroup string) {
	if fis, err := ioutil.ReadDir(dir); err == nil {
		path := filepath.Join(dir, tasksFile)
		if _, err := os.Lstat(path); err == nil || os.IsExist(err) {
			klog.Infof("assignMPAMControlGroup: %s, %s", path, rcgroup)
			if pids, err := readPids(path); err == nil {
				writePids(filepath.Join(resctrlRoot, rcgroup, tasksFile), pids)
			}
		}

		for _, fi := range fis {
			if fi.IsDir() {
				path := filepath.Join(dir, fi.Name())
				assignMPAMControlGroup(path, rcgroup)
			}
		}
	}
}

func findPodAndAssign(dir, uid, rcgroup string) {
	//	klog.Infof("findPodAndAssign: %s, %s, %s", dir, uid, rcgroup)
	if fis, err := ioutil.ReadDir(dir); err == nil {
		for _, fi := range fis {
			if fi.IsDir() {
				path := filepath.Join(dir, fi.Name())

				if strings.Contains(fi.Name(), uid) {
					assignMPAMControlGroup(path, rcgroup)
					continue
				}

				findPodAndAssign(path, uid, rcgroup)
			}
		}
	}
}

// assignControlGroup adds the tasks of a pod into a resctrl control group
func assignControlGroup(uid, rcgroup string) {
	//the newset containerd has changed cgroup path delimiter from "_" to "-", wo we try both
	id := strings.Replace(uid, "-", "_", -1)
	findPodAndAssign(cgroupCpusetRoot, id, rcgroup)

	findPodAndAssign(cgroupCpusetRoot, uid, rcgroup)
}
