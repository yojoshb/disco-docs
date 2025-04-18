## Examples of imageset-config.yaml files

Various examples of common imageset-configs (ISC) including Operators. Sub in your data as appropriate.

[Red Hat Blog about Operators in disconnected environments](https://www.redhat.com/en/blog/deploying-red-hat-openshift-operators-disconnected-environment){:target="_blank"}

To prune through the various catalogs, use the following commands

- OpenShift Releases
```bash
# Output OpenShift release versions
$ oc mirror list releases
  
# Output all OpenShift release channels list for a release
$ oc mirror list releases --version=4.17
  
# List all OpenShift versions in a specified channel
$ oc mirror list releases --channel=stable-4.17
  
# List all OpenShift channels for a specific version
$ oc mirror list releases --channels --version=4.17
  
# List OpenShift channels for a specific version and one or more release architecture. 
# Valid architectures: amd64 (default), arm64, ppc64le, s390x, multi.
$ oc mirror list releases --channels --version=4.17 --filter-by-archs amd64,arm64,ppc64le,s390x,multi
```

- Operators
```bash
# List available operator catalog release versions
oc mirror list operators
  
# Output default operator catalogs for OpenShift release 4.17
oc mirror list operators --catalogs --version=4.17
  
# List all operator packages in a catalog
oc mirror list operators --catalog=catalog-name
  
# List all channels in an operator package
oc mirror list operators --catalog=catalog-name --package=package-name
  
# List all available versions for a specified operator in a channel
oc mirror list operators --catalog=catalog-name --package=operator-name --channel=channel-name
```

### OpenShift Versioning

- You can limit the min and max version of platform releases you want to pull

```yaml
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1

mirror:
  platform:
    channels:
    - type: ocp
      name: stable-4.17
      minVersion: 4.17.17
      maxVersion: 4.14.21
```

- You can also pin to a specific version

```yaml
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1

mirror:
  platform:
    channels:
    - type: ocp
      name: stable-4.17
      minVersion: 4.17.21
      maxVersion: 4.14.21
```

### OpenShift Update Service (OSUS)

- Specify your release and set `graph: true`. The graph data along with the `cincinnati-operator` allows you to use the same update mechanism that a connected cluster would use. 
    - To install and configure OSUS [instructions are here in this document](../postinstall/osus.md)

```yaml
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1

mirror:
  platform:
    channels:
    - type: ocp
      name: stable-4.17
    graph: true

  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.17
    packages:
    - name: cincinnati-operator
```

### OpenShift Data Foundation (ODF) Operators

[Red Hat Docs](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.17/html/planning_your_deployment/disconnected-environment_rhodf#disconnected-environment_rhodf){:target="_blank"}

```yaml
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1

mirror:
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.17
    packages:
    - name: ocs-operator
      channels:
      - name: stable
    - name: odf-operator
      channels:
      - name: stable
    - name: mcg-operator
      channels:
      - name: stable
    - name: odf-csi-addons-operator
      channels:
      - name: stable
    - name: odr-cluster-operator
      channels:
      - name: stable
    - name: odr-hub-operator
      channels:
      - name: stable
    
    - name: local-storage-operator # Optional: Only for local storage deployments
      channels:
      - name: stable
    - name: odf-multicluster-orchestrator # Optional: Only for Regional Disaster Recovery (Regional-DR) configuration
      channels:
      - name: stable
```

### OpenShift Virtulization (KubeVirt) Operators

```yaml
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1

mirror:
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.17
    packages:
    - name: kubevirt-hyperconverged
      channels:
      - name: stable
    - name: kubernetes-nmstate-operator
      channels:
      - name: stable
    
    - name: lvms-operator # Optional: If you would like to use local storage
      defaultChannel: stable-4.17
      channels:
      - name: stable-4.17
  additionalImages:
  - name: registry.redhat.io/rhel8/rhel-guest-image:latest # Optional: Virtual guest images
  - name: registry.redhat.io/rhel9/rhel-guest-image:latest # Optional: Virtual guest images
  - name: registry.redhat.io/openshift4/ose-must-gather:latest # Needed for lvms-operator if you're using
```

### DISA STIG Operators

```yaml
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1

mirror:
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.17
    packages:
    - name: cluster-logging
    - name: compliance-operator
      channels:
      - name: stable
    - name: file-integrity-operator
      channels:
      - name: stable
    - name: rhacs-operator
      channels:
      - name: stable
```