# Post Installation

After the cluster has been installed, it's time to make adjustments and additions to make sure the cluster is funcioning correctly in a disconnected environment. Some of these tasks cause node reboots , so it's best to perform these steps after the 24 hour mark passes to ensure that any nodes that may be rebooted will have correct kubelet certificates granted to them.

This is commonly referrred to as `Day 2` operations. This only toughes on a few tasks that may or may-not need to be performed on your cluster. Reference the [Postinstallation configuration overview documention](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/postinstallation_configuration/post-install-configuration-overview){:target="_blank"} for more thorough instructions.

After installing OpenShift Container Platform, a cluster administrator can configure and customize the following components:

- Machine
- Bare metal
- Cluster
- Node
- Network
- Storage
- Users
- Alerts and notifications
