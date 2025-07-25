## Booting the agent ISO and watching the installation process

1. Boot the agent.iso on your hardware. This example output is for a single node OpenShift install, the node is named `sno.cluster.example.com`. The commands are the same for whatever type of cluster your are installing with the agent based installer. Normally installs take around 45 minutes give or take.

!!! info
    
    When you boot your ISO, make sure to set the ISO as a one-time boot option. The node(s) will reboot automatically during install and you don't want them rebooting into the installation ISO accidentally.
    
    For FIPS, do the same thing but use the FIPS binary
    
    ```{ .bash }
    openshift-install-fips --dir my_cluster/ agent wait-for <command>
    ```

   - Watch for the bootstrap to complete and the Kube API initialization. These commands should tell you if there's anything worng during the installation.
    ```{ .bash }
    openshift-install --dir my_cluster/ agent wait-for bootstrap-complete --log-level=info
    ```
    ```{ . .no-copy title="Example Output" }
    INFO Waiting for cluster install to initialize. Sleeping for 30 seconds
    INFO Cluster is not ready for install. Check validations
    INFO Registered infra env
    INFO Host b6076a53-c453-4046-8d95-2dd2cfe96e25: Successfully registered
    WARNING Cluster validation: The cluster has hosts that are not ready to install.
    INFO Host 5ab09259-3ac4-4259-98b0-b5ddc033e701: Successfully registered
    WARNING Host sno.cluster.example.com validation: Host couldn't synchronize with any NTP server
    INFO Host sno.cluster.example.com validation: Host NTP is synced
    INFO Host sno.cluster.example.com: validation 'ntp-synced' is now fixed
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
    INFO Bootstrap Kube API Initialized
    INFO Bootstrap configMap status is complete
    INFO Bootstrap is complete
    INFO cluster bootstrap is complete
    ```
  - Once the bootstrap fully completes, the command will exit and dump you to back to the terminal. Now you can switch to waiting for the install to complete.
    ```{ .bash }
    openshift-install --dir my_cluster/ agent wait-for install-complete
    ```
    ```{ . .no-copy title="Example Output" }
    INFO Bootstrap Kube API Initialized
    INFO Bootstrap configMap status is complete
    INFO Bootstrap is complete
    INFO cluster bootstrap is complete
    INFO Cluster is installed
    INFO Install complete!
    INFO To access the cluster as the system:admin user when using 'oc', run
    INFO     export KUBECONFIG=/home/admin/my_cluster/auth/kubeconfig
    INFO Access the OpenShift web-console here: https://console-openshift-console.apps.cluster.example.com
    INFO Login to the console with user: "kubeadmin", and password: "gbEsF-FxsIQ-Y7zNt-P5xvv"
    ```


2. Now that the cluster is installed, use the information provided from the end of the log to access the API/WebGUI.
3. **Wait at least 24 hours before rebooting the cluster or making any changes that will reboot the nodes.** KubeAPI certificates will be propagated to all components in the cluster during the first 24 hours. If the nodes get rebooted before the certs get approved by all components, there is a high chance the cluster will not initilize correctly and be unhappy. You'll have to manually approve them on all the nodes through an SSH connection. 

## Troubleshooting
Things may not go as planned so sometimes manual intervention may be required. The `openshift-install --dir my_cluster/ agent wait-for` commands should let you know if an error occurs, but sometimes it's best to get directly on the nodes and troubleshoot.

#### Direct SSH access
- Since there's an SSH key injected into the ISO, you can SSH directly to the node using the public key
```{ .bash }
ssh core@sno.cluster.example.com
```
```{ .bash .no-copy title="Example Commands" }
...
# Become root
[core@sno ~]$ sudo -i
[root@sno ~]$

# From here we can poke around the system to view any potential issues
[root@sno ~]$ journalctl -f
```

#### KubeAPI Certificate Issues
If you powered down the cluster before 24 hours, or the cluster has been down for a extended amount of time (> 30 days), there may be some kubelet certificate issues that will cause the API fail to initialize. The kubeapi-server CA has likely expired and cannot issue certs on it's behalf. 

- SSH to the master node(s), then use the `localhost.kubeconfig` to inspect the Certificate Signing Requests (csr's) 
```{ .bash }
oc get csr --kubeconfig /etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig
```
```{ .bash .no-copy title="Example Output" }
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

- Since they are all pending, but there's no valid server CA to approve them, grab the names of the csr's and pipe it to `xargs` to approve all of them using the localhost.kubeconfig
```{ .bash }
oc get csr -o name --kubeconfig /etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig | xargs oc adm certificate approve --kubeconfig /etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig
```

- Wait a bit and you should see the cluster reconcile and become available