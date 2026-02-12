# Post Installation

After the cluster has been installed, it's time to make adjustments and additions to make sure the cluster is funcioning correctly in a disconnected environment. Some of these tasks cause node reboots , so it's best to perform these steps after the 24 hour mark passes to ensure that any nodes that may be rebooted will have correct kubelet certificates granted to them.

This is commonly referrred to as `Day 2` operations. This only touches on a few tasks that may or may not need to be performed on your cluster. Reference the [Postinstallation configuration overview documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/postinstallation_configuration/post-install-configuration-overview){:target="_blank"} for more thorough instructions.

After installing OpenShift Container Platform, a cluster administrator can configure and customize the following components:

- Machine
- Bare metal
- Cluster
- Node
- Network
- Storage
- Users
- Alerts and notifications

---

Best to [enable tab completion](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/cli_tools/openshift-cli-oc#cli-enabling-tab-completion){:target="_blank"} on the `oc` command line tool. It makes navigating through the resources much easier. Check the link above if you are using a different shell, as the example below is for bash.
```{ .bash }
oc completion bash > oc_bash_completion
```
Then make it availble system-wide or you can just source it from your `.bashrc`
```{ .bash }
sudo cp oc_bash_completion /etc/bash_completion.d/
```