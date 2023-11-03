package agent

import (
	"context"
	meta_v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	k8sclient "k8s.io/client-go/kubernetes"
	"os"

	"k8s.io/klog"
)

const mpamLabel = "MPAM"

// labelNodeMPAM label a node to indicate if it supports MPAM
func labelNodeMPAM(k8sCli *k8sclient.Clientset) bool {
	support := true

	// label the node
	node, err := k8sCli.CoreV1().Nodes().Get(context.TODO(), nodeName, meta_v1.GetOptions{})
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

	k8sCli.CoreV1().Nodes().Update(context.TODO(), node, meta_v1.UpdateOptions{})

	return support
}
