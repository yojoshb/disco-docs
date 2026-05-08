When creating the agent.iso using the agent-based installer, you can furthur customize your clusters deployment by editing/adding additional manifests.

- [Docs: ZTP Manifests](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/installing_an_on-premise_cluster_with_the_agent-based_installer/installing-with-agent-based-installer#installing-ocp-agent-ztp_installing-with-agent-based-installer){:target="_blank"}
- [Docs: Additional Manifests](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/installing_an_on-premise_cluster_with_the_agent-based_installer/installing-with-agent-based-installer#installing-ocp-agent-opt-manifests_installing-with-agent-based-installer){:target="_blank"}

### GitOps ZTP Manifests

[Sample GitOps ZTP custom resources](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/installing_an_on-premise_cluster_with_the_agent-based_installer/installing-with-agent-based-installer#sample-ztp-custom-resources_installing-with-agent-based-installer){:target="_blank"}

!!! note
    GitOps ZTP manifests can be generated with or without configuring the `install-config.yaml` and `agent-config.yaml` files beforehand. If you chose to configure the `install-config.yaml` and `agent-config.yaml` files, the configurations will be imported to the ZTP cluster manifests when they are generated. It's easiest to configure both yaml files first so the core config data is captured in a simpler format.

- Before building the ISO, create the cluster manifests by running:
```{ .bash }
openshift-install agent create cluster-manifests --dir <installation_directory>
```

- Now, if you navigate to the installation directory, you can edit the cluster-manifests directly
```{ .bash }
cd <installation_directory>/cluster-manifests
```

#### GitOps ZTP: Set masters/control-plane to be schedulable

- Edit the `<installation_directory>/cluster-manifests/agent-cluster-install.yaml` and add the yaml below under `spec:`
```{ .yaml .copy }
mastersSchedulable: true
```

- Now you can create the agent.iso
```{ .bash }
openshift-install agent create image --dir <installation_directory>
```

- If this needs to be reverted, you can patch the master nodes after the cluster is built and running:
```{ .bash }
oc patch schedulers.config.openshift.io cluster --type merge --patch '{"spec": {"mastersSchedulable": false}}'
```

#### GitOps ZTP: Enable disk encryption using LUKS

[RH Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/installing_an_on-premise_cluster_with_the_agent-based_installer/installing-with-agent-based-installer#installing-ocp-agent-encrypt_installing-with-agent-based-installer){:target="_blank"}

[Additional Docs for TANG: primarily for installer-provisioned infrastructure, user-provisioned infrastructure, and Assisted Installer deployments](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html-single/installation_configuration/index#installation-special-config-storage_installing-customizing){:target="_blank"}

!!! note
    If using CLEVIS/TANG, DHCP is required for agent-based installs as there is no good way of passing static IP kernel args to the agent-installer currently. It's possible to patch this in during agent-bootstrap, but difficult.
    If you want a static-like IP deployment, you can still utilize static-dhcp reservations to get similar behavior

- Edit the `<installation_directory>/cluster-manifests/agent-cluster-install.yaml` and add the yaml below under `spec:`
```{ .yaml .copy }
diskEncryption:
  enableOn: all # Valid values are none, all, masters, and workers
  mode: tang    # Valid values are tpmv2 and tang
  tangServers: '[{"url": "http://tang-server:7500","thumbprint": "_91gvNqLpFotYLfIsdfgfvcbas4wESQRHB3_dk"}]' # Optional: only needed if using tang
```

- Now you can create the agent.iso
```{ .bash }
openshift-install agent create image --dir <installation_directory>
```


### Additional Manifests

#### Disabling default catalog sources, and adding your mirrored catalogs

You can add additional kubernetes manifests to further customize your cluster on day 0. This will need to be done, along with `ImageTagMirrorSet` and `ImageDigestMirrorSet` if you want to install Operators on day 0.

- Before building the ISO, create a new directory in your `<installation_directory>` called `openshift`
```{ .bash }
mkdir -p <installation_directory>/openshift
```

- Disabling default catalog sources
```{ .yaml .copy }
apiVersion: config.openshift.io/v1
kind: OperatorHub
metadata:
  name: cluster
spec:
  disableAllDefaultSources: true
```

- You can also disable the default Helm Chart Repository as it is configured to look for charts by default on the web
```{ .yaml .copy }
apiVersion: helm.openshift.io/v1beta1
kind: HelmChartRepository
metadata:
  name: openshift-helm-charts
spec:
  disabled: true
```

- Adding your mirrored catalogs. This is the same information that comes from the oc mirror `working-dir/cluster-resources`
```{ .yaml .copy }
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: redhat-operators
  namespace: openshift-marketplace
spec:
  image: registry.example.com:8443/ocp/redhat/redhat-operator-index:v4.20
  sourceType: grpc
  displayName: "Red Hat Operators Mirrored" # Optional 
```
```{ .yaml .copy }
apiVersion: olm.operatorframework.io/v1
kind: ClusterCatalog
metadata:
  name: redhat-operators
spec:
  priority: 0
  source:
    image:
      ref: registry.example.com:8443/ocp/redhat/redhat-operator-index:v4.20
    type: Image
```