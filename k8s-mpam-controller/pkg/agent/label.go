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
	"os"

	meta "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"

	"k8s.io/klog"
)

const mpamLabel = "MPAM"

// labelNodeMPAM label a node to indicate if it supports MPAM
func labelNodeMPAM(k8sCli *kubernetes.Clientset) bool {
	support = true

	// label the node
	node, err := k8sCli.CoreV1().Nodes().Get(context.TODO(), nodeName, meta.GetOptions{})
	if err != nil || node == nil {
		klog.Errorf("Failed to get node: %v", err)
		klog.Warning("please ensure environment variable NODE_NAME has been set!")
		return false
	}

	// check if resctrl is supported
	if _, err := os.Stat("/sys/fs/resctrl"); err != nil {
		node.Labels[mpamLabel] = "no"
		support = false
	} else {
		// check if resctrl fs has been mounted
		if _, err := os.Stat("/sys/fs/resctrl/schemata"); err != nil {
			node.Labels[mpamLabel] = "disabled"
			support = false
		} else {
			node.Labels[mpamLabel] = "enabled"
		}
	}

	k8sCli.CoreV1().Nodes().Update(context.TODO(), node, meta.UpdateOptions{})

	return support
}
