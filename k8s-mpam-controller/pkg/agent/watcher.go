/*
Copyright (c) Huawei Technologies Co., Ltd. 2023-2023. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package agent

import (
	"context"
	"sync"

	core "k8s.io/api/core/v1"
	meta "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/watch"
	"k8s.io/client-go/kubernetes"

	"k8s.io/klog"
)

// the namespace of the ConfigMaps
const configMapNamespace = "rc-config"

// resource control configuration
type configData map[string]string

// nodeName contains the name of the k8s node we're running on
var nodeName string

type watcher struct {
	k8sCli *kubernetes.Clientset // k8s client interface

	groupConfigMapWatch watch.Interface

	sync.RWMutex

	// node-specific configuration. it's 'Data' field value of the ConfigMap
	// named rc-config.node.{NODE_NAME}
	nodeCfg *configData

	// group-specific configuration. If a node belong to a node group, it is
	// the 'Data' field value of the ConfigMap named rc-config.group.{GROUP_NAME},
	// otherwise it's the 'Data' field value of the ConfigMap named rc-config.default
	groupCfg *configData
}

var singleton_watcher *watcher

// getWatcher returns singleton k8s watcher instance.
func getWatcher(k8sCli *kubernetes.Clientset) *watcher {
	if singleton_watcher == nil {
		singleton_watcher = &watcher{
			k8sCli: k8sCli,
		}
	}

	return singleton_watcher
}

func (w *watcher) watchNode() {
	// watch this Node
	selector := meta.ListOptions{FieldSelector: "metadata.name=" + nodeName}
	k8w, err := w.k8sCli.CoreV1().Nodes().Watch(context.TODO(), selector)
	if err != nil {
		klog.Errorf("Failed to watch node (%q): %v", nodeName, err)
		return
	}

	go func(ev <-chan watch.Event, group string) {
		for e := range ev {
			switch e.Type {
			case watch.Added, watch.Modified:
				klog.Infof("node (%s) is updated", nodeName)
				label, _ := e.Object.(*core.Node).Labels["ngroup"]

				// if the node group is changed, we start to watch the config of the new node group
				if group != label {
					group = label
					klog.Infof("node group is set to %s", group)
					w.watchGroupConfigMap(group)
				}
			case watch.Deleted:
				klog.Warning("our node is removed...")
			default:
				klog.Info("other event type")
			}
		}

		klog.Warning("seems node watcher is closed, going to restart ...")
		w.watchNode()
		klog.Warning("node configMap watcher restarted")
	}(k8w.ResultChan(), "")
}

func (w *watcher) watchNodeConfigMap() {
	// watch "rc-config.node.{NODE_NAME}" ConfigMap
	selector := meta.ListOptions{FieldSelector: "metadata.name=" + "rc-config.node." + nodeName}
	k8w, err := w.k8sCli.CoreV1().ConfigMaps(configMapNamespace).Watch(context.TODO(), selector)
	if err != nil {
		klog.Errorf("Failed to watch ConfigMap rc-config.node.%q: %v", nodeName, err)
		return
	}

	go func(ev <-chan watch.Event) {
		for e := range ev {
			switch e.Type {
			case watch.Added, watch.Modified:
				klog.Info("ConfigMap rc-config.node." + nodeName + " is updated")
				cm, ok := e.Object.(*core.ConfigMap)
				if !ok {
					klog.Warning("It's not ok for type *core.ConfigMap")
					continue
				}
				w.setNodeConfig(&cm.Data)
			case watch.Deleted:
				klog.Info("ConfigMap rc-config.node." + nodeName + " is deleted")
				w.setNodeConfig(nil)
			default:
				klog.Info("other event type")
			}
		}

		klog.Warning("seems node configMap watcher is closed, going to restart ...")
		w.watchNodeConfigMap()
		klog.Warning("node configMap watcher restarted")
	}(k8w.ResultChan())
}

func (w *watcher) watchGroupConfigMap(group string) {
	if w.groupConfigMapWatch != nil {
		w.groupConfigMapWatch.Stop()
	}

	// watch group ConfigMap
	cmName := "rc-config.default"
	if group != "" {
		cmName = "rc-config.group." + group
	}
	selector := meta.ListOptions{FieldSelector: "metadata.name=" + cmName}
	k8w, err := w.k8sCli.CoreV1().ConfigMaps(configMapNamespace).Watch(context.TODO(), selector)
	if err != nil {
		klog.Errorf("Failed to watch group ConfigMap (%q): %v", cmName, err)
		return
	}

	w.groupConfigMapWatch = k8w
	klog.Info("start watching ConfigMap " + cmName)

	go func(ev <-chan watch.Event, group string) {
		for e := range ev {
			switch e.Type {
			case watch.Added, watch.Modified:
				cm, ok := e.Object.(*core.ConfigMap)
				if !ok {
					klog.Warning("It's not ok for type *core.ConfigMap")
					continue
				}
				klog.Infof("group ConfigMap (%s) is updated", cm.Name)
				w.setGroupConfig(&cm.Data)
			case watch.Deleted:
				cm, ok := e.Object.(*core.ConfigMap)
				if !ok {
					klog.Warning("It's not ok for type *core.ConfigMap")
					continue
				}
				klog.Infof("group ConfigMap (%s) is deleted", cm.Name)
				w.setGroupConfig(nil)
			default:
				klog.Info("other event type")
			}
		}

		klog.Warning("seems group configMap watcher is closed, going to restart ...")
		w.watchGroupConfigMap(group)
		klog.Warning("group configMap watcher is restarted")

	}(k8w.ResultChan(), group)
}

func (w *watcher) watchPods() {
	// watch Pods in all namespace
	k8w, err := w.k8sCli.CoreV1().Pods(meta.NamespaceAll).Watch(context.TODO(), meta.ListOptions{})
	if err != nil {
		klog.Errorf("watch Pods in all namespace failed")
		return
	}

	go func(ev <-chan watch.Event) {
		for e := range ev {
			switch e.Type {
			case watch.Added, watch.Modified:
				klog.Infof("pod (%s) is updated", e.Object.(*core.Pod).Name)
				if rcgroup, ok := e.Object.(*core.Pod).Labels["rcgroup"]; ok {
					klog.Infof("Pod: %s; rcgroup: %s", string(e.Object.(*core.Pod).UID), rcgroup)
					assignControlGroup(string(e.Object.(*core.Pod).UID), rcgroup)
				}

			case watch.Deleted:
				klog.Info("a pod is deleted " + e.Object.(*core.Pod).UID)
			default:
				klog.Info("other event type")
			}
		}

		klog.Warning("seems pod watcher is closed, going to restart ...")
		w.watchPods()
		klog.Warning("pod watcher is restarted")

	}(k8w.ResultChan())
}

func (w *watcher) start() {
	klog.Info("starting agent watcher ...")
	if nodeName == "" {
		klog.Warning("node name not set, NODE_NAME env variable should be set to match the name of this k8s Node")
		return
	}

	if !getNumclosids() {
		klog.Errorf("get num_closids failed, please ensure resctrl fs is mounted")
		return
	}

	if !getCbmmask() {
		klog.Errorf("get cbm_mask failed, please ensure resctrl fs is mounted")
		return
	}

	w.watchNodeConfigMap()
	w.watchGroupConfigMap("")
	w.watchNode()

	if direct {
		w.watchPods()
	}
}

// applyConfig applies the current configuration.
func (w *watcher) applyConfig() {
	klog.Info("apply configuration")

	config := w.groupCfg

	if w.nodeCfg != nil {
		config = w.nodeCfg
	}

	if config == nil {
		klog.Warning("There is no configuration")
	}

	applyConfig(config)
}

// set node-specific configuration
func (w *watcher) setNodeConfig(data *map[string]string) {
	w.Lock()
	defer w.Unlock()

	w.nodeCfg = (*configData)(data)
	w.applyConfig()
}

// set group-specific or default configuration
func (w *watcher) setGroupConfig(data *map[string]string) {
	w.Lock()
	defer w.Unlock()

	w.groupCfg = (*configData)(data)

	if w.nodeCfg == nil {
		w.applyConfig()
	}
}
