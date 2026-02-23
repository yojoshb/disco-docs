## Advanced Installation Examples

When creating the agent.iso using the agent-based installer, you can furthur customize your clusters deployment by editing/adding additional manifests.

### GitOps ZTP Manifests

[Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/installing_an_on-premise_cluster_with_the_agent-based_installer/installing-with-agent-based-installer#installing-ocp-agent-ztp_installing-with-agent-based-installer){:target="_blank"}

!!! note
    GitOps ZTP manifests can be generated with or without configuring the `install-config.yaml` and `agent-config.yaml` files beforehand. If you chose to configure the `install-config.yaml` and `agent-config.yaml` files, the configurations will be imported to the ZTP cluster manifests when they are generated.

- Before building the ISO, create the cluster manifests by running:
```bash
openshift-install agent create cluster-manifests --dir <installation_directory>
```

- Now, if you navigate to the installation directory, you can edit the cluster-manifests directly
```bash
cd <installation_directory>/cluster-manifests
```

#### GitOps ZTP: Set masters/control-plane to be schedulable

- Edit the `<installation_directory>/cluster-manifests/agent-cluster-install.yaml` and set:
```yaml
mastersSchedulable: true
```

- Now you can create the agent.iso
```bash
openshift-install agent create image --dir <installation_directory>
```

- If this needs to be reverted, you can patch the master nodes after the cluster is built and running:
```bash
oc patch schedulers.config.openshift.io cluster --type merge --patch '{"spec": {"mastersSchedulable": false}}'
```
