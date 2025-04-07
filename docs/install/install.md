## Booting the agent ISO and watching the installation process

1. Run the `openshift-install` binary against the directory that contains your cluster config files. This example is for a single node OpenShift install, the node is named `sno.cluster.example.com`
   - We will watch for the bootstrap to complete and the Kube API initialization
    ```bash
    $ ./openshift-install --dir my-cluster/ agent wait-for bootstrap-complete --log-level=info
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
    ```bash
    $ ./openshift-install --dir my-cluster/ agent wait-for install-complete
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
3. **Wait at least 24 hours before rebooting the cluster or making any changes that will reboot the nodes.** KubeAPI certificates will be propagated to all components in the cluster during the first 24 hours and this takes time.