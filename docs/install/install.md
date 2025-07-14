## Booting the agent ISO and watching the installation process

1. Boot the agent.iso on your hardware. This example output is for a single node OpenShift install, the node is named `sno.cluster.example.com`. The commands are the same for whatever type of cluster your are installing with the agent based installer.

!!! info
    For FIPS, do the same thing but use the FIPS binary
    
    ```bash
    $ openshift-install-fips --dir my-cluster/ agent wait-for <command>
    ```

   - We will watch for the bootstrap to complete and the Kube API initialization
    ```
    $ openshift-install --dir my-cluster/ agent wait-for bootstrap-complete --log-level=info
    INFO Waiting for cluster install to initialize. Sleeping for 30 seconds
    INFO Cluster is not ready for install. Check validations
    WARNING Cluster validation: The cluster has hosts that are not ready to install.
    INFO Host 5ab09259-3ac4-4259-98b0-b5ddc033e701: Successfully registered
    WARNING Host sno.cluster.example.com validation: Host couldn't synchronize with any NTP server
    WARNING Host sno.cluster.example.com: updated status from discovering to insufficient (Host cannot be installed due to following failing validation(s): Host couldn't synchronize with any NTP server)
    INFO Host sno.cluster.example.com: updated status from insufficient to known (Host is ready to be installed)
    INFO Cluster is ready for install
    INFO Cluster validation: All hosts in the cluster are ready to install.
    INFO Preparing cluster for installation
    INFO Host sno.cluster.example.com: updated status from known to preparing-for-installation (Host finished successfully to prepare for installation)
    INFO Host sno.cluster.example.com: updated status from preparing-for-installation to preparing-successful (Host finished successfully to prepare for installation)
    INFO Cluster installation in progress
    INFO Host sno.cluster.example.com: updated status from preparing-successful to installing (Installation is in progress)
    INFO Host: sno.cluster.example.com, reached installation stage Installing: bootstrap
    INFO Host: sno.cluster.example.com, reached installation stage Waiting for bootkube
    INFO Bootstrap Kube API Initialized
    ```
  - Once we see that the Kube API has inititalized we can switch to waiting for the install to complete. This will take some time.
    ```
    $ openshift-install --dir my-cluster/ agent wait-for install-complete
    INFO Cluster installation in progress
    WARNING Host sno.cluster.example.com validation: Host couldn't synchronize with any NTP server
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 6%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 12%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 19%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 25%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 35%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 40%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 45%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 51%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 58%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 64%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 70%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 76%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 82%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 88%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 93%
    INFO Host: sno.cluster.example.com, reached installation stage Writing image to disk: 100%
    INFO cluster bootstrap did not complete
    INFO Bootstrap Kube API Initialized
    INFO Bootstrap configMap status is complete
    INFO Bootstrap is complete
    INFO cluster bootstrap is complete
    INFO Cluster is installed
    INFO Install complete!
    INFO To access the cluster as the system:admin user when using 'oc', run
    INFO     export KUBECONFIG=/home/admin/openshift-install/my-cluster/auth/kubeconfig
    INFO Access the OpenShift web-console here: https://console-openshift-console.apps.cluster.example.com
    INFO Login to the console with user: "kubeadmin", and password: "gbEsF-FxsIQ-Y7zNt-P5xvv"
    ```


2. Now that the cluster is installed, use the information provided from the end of the log to access the API/WebGUI.
3. **Wait at least 24 hours before rebooting the cluster or making any changes that will reboot the nodes.** KubeAPI certificates will be propagated to all components in the cluster during the first 24 hours. If the nodes get rebooted before the certs get approved by all components, there is a high chance the cluster will not initilize correctly and be unhappy. You'll have to manually approve them on all the nodes through an SSH connection. 

## Troubleshooting
Things may not go as planned so sometimes manual intervention may be required. The `openshift-install --dir my-cluster/ agent wait-for` commands should let you know if an error occurs, but sometimes it's best to get directly on the nodes and troubleshoot.

#### Direct SSH access
- Since there's an SSH key injected into the ISO, you can SSH directly to the node
```bash
$ ssh core@sno.cluster.example.com
...
[core@sno ~]$ sudo -i
[root@sno ~]$
```

- From here we can poke around the system to view any potential issues
```bash
$ journalctl -f
```

#### KubeAPI Certificate Issues
If you powered down the cluster before 24 hours, or the cluster has been down for a extended amount of time (> 30 days), there may be some kubelet certificate issues that will cause the API to fail to initialize.

- SSH to the master node(s), then use the `localhost.kubeconfig` to inspect the Certificate Signing Requests (csr) 
```bash
$ oc get csr --kubeconfig /etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig
NAME        AGE     SIGNERNAME                                    REQUESTOR                                                                   REQUESTEDDURATION   CONDITION
csr-8dthq   91m     kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-92ngr   60m     kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-dkm6t   168m    kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-fqq68   13m     kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-g4mgs   137m    kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-g6hjc   106m    kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-h9hjd   3h34m   kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-hssjx   3h3m    kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-j2wbc   152m    kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-k7g7l   75m     kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-kgqnn   4h5m    kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-ln289   29m     kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-mx4pn   3h19m   kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-n9jf7   122m    kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-nll8c   3h50m   kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
csr-qvt5r   44m     kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending
```

- Since they are all pending, but there's no one to approve them, grab the name of the csr and pipe it to `xargs` to approve all of them.
```bash
$ oc get csr -o name --kubeconfig /etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig | xargs oc adm certificate approve --kubeconfig /etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig
```