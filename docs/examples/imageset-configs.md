## Examples of imageset-config.yaml files

Various examples of common imageset-configs (ISC) including Operators. Sub in your data as appropriate.

!!! important
    Operators and catalogs are version specific. Be sure to prune through the catalogs so you mirror the correct version of the operators for your target platform

    Feel free to mix, match, and create different imagesets for different deployments

[Red Hat Blog about Operators in disconnected environments](https://www.redhat.com/en/blog/deploying-red-hat-openshift-operators-disconnected-environment){:target="_blank"}

To prune through the various catalogs, use the following commands

- OpenShift Releases
```bash
# Output OpenShift release versions
oc mirror list releases
  
# Output all OpenShift release channels list for a release
oc mirror list releases --version=4.17
  
# List all OpenShift versions in a specified channel
oc mirror list releases --channel=stable-4.17
  
# List all OpenShift channels for a specific version
oc mirror list releases --channels --version=4.17
  
# List OpenShift channels for a specific version and one or more release architecture. 
# Valid architectures: amd64 (default), arm64, ppc64le, s390x, multi.
oc mirror list releases --channels --version=4.17 --filter-by-archs amd64,arm64,ppc64le,s390x,multi
```

- Operators

    !!! tip
      
        This handy little one-liner will dump all available operators and their corresponding catalogs and store them in text files for a specific version. This will take some time to run initially, but saves a bunch of time in the long run

        [Source: Allens Repository with more helpful scripts and configs](https://github.com/afouladi7/openshift_shortcuts/blob/main/TEMPLATES/random_commands.md){:target="_blank"}
      
        ```bash
        for i in $(oc-mirror list operators --catalogs --version=4.17 | grep registry); do $(oc-mirror list operators --catalog=$i --version=4.17 > $(echo $i | cut -b 27- | rev | cut -b 7- | rev).txt); done
        ```

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

```{ .yaml .copy }
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1

mirror:
  platform:
    architectures:
    - amd64
    channels:
    - type: ocp
      name: stable-4.17
      minVersion: 4.17.17
      maxVersion: 4.17.21
```

- You can also pin to a specific version

```{ .yaml .copy }
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1

mirror:
  platform:
    architectures:
    - amd64
    channels:
    - type: ocp
      name: stable-4.17
      minVersion: 4.17.21
      maxVersion: 4.17.21
```

- For other architectures, you can select the filter for the target platform 

```{ .yaml .copy }
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1

mirror:
  platform:
    architectures:
    - arm64
    channels:
    - type: ocp
      name: stable-4.17
```

### OpenShift Update Service (OSUS)

- Specify your release and set `graph: true`. The graph data along with the `cincinnati-operator` allows you to use the same update mechanism that a connected cluster would use. 
    - To install and configure OSUS [instructions are here in this document](../postinstall/osus.md)

```{ .yaml .copy }
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

[Red Hat ODF 4.17 Docs](https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.17/html/planning_your_deployment/disconnected-environment_rhodf#disconnected-environment_rhodf){:target="_blank"}

Consult the docs for whatever version of ODF you are wanting to install. The operators required vary per version.

```{ .yaml .copy title="ODF 4.17" }
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1

mirror:
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.17
    packages:
    - name: ocs-operator
      channels:
      - name: stable-4.17
    - name: odf-operator
      channels:
      - name: stable-4.17
    - name: mcg-operator
      channels:
      - name: stable-4.17
    - name: odf-csi-addons-operator
      channels:
      - name: stable-4.17
    - name: ocs-client-operator
      channels:
      - name: stable-4.17
    - name: odf-prometheus-operator
      channels:
      - name: stable-4.17
    - name: recipe
      channels:
      - name: stable-4.17
    - name: rook-ceph-operator
      channels:
      - name: stable-4.17
    - name: cephcsi-operator
      channels:
      - name: stable-4.17
    - name: odr-cluster-operator
      channels:
      - name: stable-4.17
    - name: odr-hub-operator
      channels:
      - name: stable-4.17
    
    # For local storage deployments i.e. node disks 
    - name: local-storage-operator
      channels:
      - name: stable
    
    # Optional: Only for Regional Disaster Recovery (Regional-DR) configuration
    - name: odf-multicluster-orchestrator
      channels:
      - name: stable-4.17
  
  additionalImages:
  # Optional: ODF Must gather support tools
  - name: registry.redhat.io/odf4/odf-must-gather-rhel9:v4.17
```

### OpenShift Virtulization (KubeVirt) and Migration Kit for Virtualization (MTV) Operators

[KubeVirt](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/virtualization/index)

[MTV](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.9/html/installing_and_using_the_migration_toolkit_for_virtualization/index)

[VDDK](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.9/html/installing_and_using_the_migration_toolkit_for_virtualization/prerequisites_mtv#creating-vddk-image_mtv)

[VDDK Image](https://quay.io/repository/jcall/vddk?tab=info)

```{ .yaml .copy }
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1

mirror:
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.17
    packages:
    # Virtualization
    - name: kubevirt-hyperconverged
      channels:
      - name: stable
    - name: kubernetes-nmstate-operator
      channels:
      - name: stable
    
    # Optional: If you would like to use local dynamic storage on another disk attached to the host
    - name: lvms-operator
      defaultChannel: stable-4.17
      channels:
      - name: stable-4.17
    
    # Migration Toolkit for Virtulization
    - name: mtv-operator
      channels:
      - name: release-v2.6
      
  additionalImages:
  # Optional: Virtual guest images
  - name: registry.redhat.io/rhel8/rhel-guest-image:latest
  - name: registry.redhat.io/rhel9/rhel-guest-image:latest
  
  # Needed for lvms-operator if you're using
  - name: registry.redhat.io/openshift4/ose-must-gather:latest
  
  # Heavily recommended to have a VDDK image when transferring from vSphere
  - name: quay.io/jcall/vddk:latest # Heavily recommended to have a VDDK image when transferring from vSphere

  # Optional: KubeVirt Must gather support tools
  - name: registry.redhat.io/container-native-virtualization/cnv-must-gather-rhel9:v4.17
```

### Other Handy Operators

[NFD](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/specialized_hardware_and_driver_enablement/psap-node-feature-discovery-operator)

[OADP](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/backup_and_restore/oadp-application-backup-and-restore)

[MTC](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/migration_toolkit_for_containers/index)

```{ .yaml .copy }
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v1alpha2
mirror:
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.17
    packages:
    # Advanced Cluster Management for Kuberenetes
    - name: advanced-cluster-management
      channels:
        - name: release-2.13
    - name: multicluster-engine
      channels:
        - name: stable-2.8
        
    # Advanced Cluster Security for Kuberenetes
    - name: rhacs-operator
      channels:
      - name: stable
    
    # OpenShift API for Data Protection (OADP) features provide options for backing up and restoring applications
    - name: redhat-oadp-operator 
      channels:
      - name: stable-1.4
    
    # Migration Toolkit for containers to migrate workloads from one cluster to another
    - name: mtc-operator
      channels:
      - name: release-v1.8
    
    # Node feature discovery
    - name: nfd
      channels:
      - name: stable
    
    # Terminal that you can access from the WebUI
    - name: web-terminal
      channels:
      - name: fast
    - name: devworkspace-operator
      channels:
      - name: fast

   # Ansible Automation Platform Operator
    - name: ansible-automation-platform-operator
      channels:
      - name: stable-2.5
   
   # MetalLB Operator
    - name: metallb-operator
      channels:
      - name: stable
      
   # PTP Operator
    - name: ptp-operator
      channels:
      - name: stable

   # OpenShift Logging
    - name: cluster-logging
      channels:
      - name: stable-6.2
    - name: loki-operator
      channels:
      - name: stable-6.2

   # OpenShift Service Mesh
    - name: servicemeshoperator3
      channels:
      - name: stable
    - name: kiali-ossm
      channels:
      - name: stable
    - name: jaeger-product
      channels:
      - name: stable

   # Cluster Observability Operator
    - name: cluster-observability-operator
      channels:
      - name: stable

   # Network Observability Operator
    - name: netobserv-operator
      channels:
      - name: stable

   # Keycloak Operator 
    - name: rhbk-operator
      channels:
      - name: stable-v26.0

   # Cert Manager
    - name: openshift-cert-manager-operator
      channels:
      - name: stable-v1
  
  additionalImages:
  - name: registry.redhat.io/rhel8/support-tools
  - name: registry.redhat.io/rhel9/support-tools

  # Universal Base Images
  - name: registry.redhat.io/ubi9/ubi:latest
  - name: registry.redhat.io/ubi8/ubi:latest

  helm:
    repositories:
      
      # NFS CSI that can do dynamic provisioning off of NFS attached storage, or provide NFS storage from the cluster (community supported)
      - name: csi-driver-nfs
        url: https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
        charts:
          - name: csi-driver-nfs
            version: 4.9.0
```

### DISA STIG Operators
These aren't actually tied to the STIG, just makes it easier to actually apply it to your cluster

```{ .yaml .copy }
---
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1

mirror:
  operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.17
    packages:
    - name: compliance-operator
      channels:
      - name: stable
    - name: file-integrity-operator
      channels:
      - name: stable
```