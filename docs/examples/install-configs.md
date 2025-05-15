## Examples of install-config.yaml files

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/installing_an_on-premise_cluster_with_the_agent-based_installer/preparing-to-install-with-agent-based-installer#installation-bare-metal-agent-installer-config-yaml_preparing-to-install-with-agent-based-installer)

[Red Hat Docs: Install Configuration Parameters](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/installing_an_on-premise_cluster_with_the_agent-based_installer/installation-config-parameters-agent#installation-configuration-parameters_installation-config-parameters-agent){:target="_blank"}

Various examples of common install-configs. Sub in your data as appropriate.

### Single-Node OpenShift (SNO)

```yaml title="install-config.yaml: SNO cluster"
apiVersion: v1
baseDomain: example.com # (1)! The base domain name of the cluster. All DNS records must be sub-domains of this base and include the cluster name.
compute:
- architecture: amd64 # (2)! Specify the system architecture. Valid values are amd64, arm64, ppc64le, and s390x.
  hyperthreading: Enabled
  name: worker
  replicas: 0 # (3)! This parameter controls the number of compute machines that the Agent-based installation waits to discover before triggering the installation process. It is the number of compute machines that must be booted with the generated ISO.
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  replicas: 1 # (4)! The number of control plane machines that you add to the cluster. Because the cluster uses these values as the number of etcd endpoints in the cluster, the value must match the number of control plane machines that you deploy.
metadata:
  name: cluster # (5)! The cluster name that you specified in your DNS records.
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14 # (6)! The network that the cluster shares for assigning IPs to PODS. Each node will get a /23 (500~ usable IP addresses). Make sure this IP space does not conflict with anything on your LAN.
    hostPrefix: 23
  machineNetwork:
  - cidr: 172.16.1.0/24 # (7)! The network that connects the cluster to your LAN. This is the IP space that resides on your LAN.
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16 # (8)! Used for internal service objects. Make sure this IP space does not conflict with anything on your LAN.
platform:
  none: {} # (9)! You must set the platform to none for a single-node cluster. You can set the platform to vsphere, baremetal, or none for multi-node clusters.
fips: true # (10)! Boolean: Either true or false to enable or disable FIPS mode. By default, FIPS mode is not enabled. If FIPS mode is enabled, the Red Hat Enterprise Linux CoreOS (RHCOS) machines that OpenShift Container Platform runs on bypass the default Kubernetes cryptography suite and use the cryptography modules that are provided with RHCOS instead
pullSecret: '{"auths":{"registry.example.com:8443": {"auth": "am9zaDpLSW....","email": ""}}}' # (11)! A pull secret for your internal image registry
sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABg....' # (12)! Public ssh key that you define. This key will give ssh access to the nodes through the 'core' user. This is the only way to ssh into the nodes
additionalTrustBundle: | # (13)! The rootCA.pem certificate of your internal image registry
  -----BEGIN CERTIFICATE-----
  MIID1jCCAr6gAwIBAgIUZ11j30+eBRjNEl7IPufQdzMl6oAwDQYJKoZIhvcNAQEL
  BQAwajELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAlZBMREwDwYDVQQHDAhOZXcgWW9y
  azENMAsGA1UECgwEUXVheTERMA8GA1UECwwIRGl2aXNpb24xGTAXBgNVBAMMEHJl
  ...
  -----END CERTIFICATE----- 
imageDigestSources: # (14)! Your image mirrors, this in the idms-oc-mirror.yaml file generated from oc mirror. i.e. /opt/4.17-mirrordata/working-dir/cluster-resources/idms-oc-mirror.yaml 
- mirrors:
  - registry.example.com:8443/v4.17/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - registry.example.com:8443/v4.17/openshift/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

1. The base domain name of the cluster. All DNS records must be sub-domains of this base and include the cluster name.
2. Specify the system architecture. Valid values are `amd64`, `arm64`, `ppc64le`, and `s390x`.
3. This parameter controls the number of compute machines that the Agent-based installation waits to discover before triggering the installation process. It is the number of compute machines that must be booted with the generated ISO.
4. The number of control plane machines that you add to the cluster. Because the cluster uses these values as the number of etcd endpoints in the cluster, the value must match the number of control plane machines that you deploy.
5. The cluster name that you specified in your DNS records.
6. The network that the cluster shares for assigning IPs to PODS. Each node will get a /23 (500~ usable IP addresses). Make sure this IP space does not conflict with anything on your LAN.
7. The network that connects the cluster to your LAN. This is the IP space that resides on your LAN.
8. Used for internal service objects. Make sure this IP space does not conflict with anything on your LAN.
9.  You must set the platform to `none` for a single-node cluster. You can set the platform to `vsphere`, `baremetal`, or `none` for multi-node clusters.
10. Boolean: Either true or false to enable or disable FIPS mode. By default, FIPS mode is not enabled. If FIPS mode is enabled, the Red Hat Enterprise Linux CoreOS (RHCOS) machines that OpenShift Container Platform runs on bypass the default Kubernetes cryptography suite and use the cryptography modules that are provided with RHCOS instead
11. A pull secret for your internal image registry
12. Public ssh key that you define. This key will give ssh access to the nodes through the 'core' user. This is the only way to ssh into the nodes
13. The rootCA.pem certificate of your internal image registry
14. Your image mirrors, this in the idms-oc-mirror.yaml file generated from oc mirror. i.e. /opt/4.17-mirrordata/working-dir/cluster-resources/idms-oc-mirror.yaml 

### HA OpenShift - 3 master nodes and 2 worker nodes

```yaml title="install-config.yaml: HA cluster"
apiVersion: v1
baseDomain: example.com # (1)! The base domain name of the cluster. All DNS records must be sub-domains of this base and include the cluster name.
compute:
- architecture: amd64 # (2)! Specify the system architecture. Valid values are amd64, arm64, ppc64le, and s390x.
  hyperthreading: Enabled
  name: worker
  replicas: 2 # (3)! This parameter controls the number of compute machines that the Agent-based installation waits to discover before triggering the installation process. It is the number of compute machines that must be booted with the generated ISO.
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  replicas: 3 # (4)! The number of control plane machines that you add to the cluster. Because the cluster uses these values as the number of etcd endpoints in the cluster, the value must match the number of control plane machines that you deploy.
metadata:
  name: cluster # (5)! The cluster name that you specified in your DNS records.
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14 # (6)! The network that the cluster shares for assigning IPs to PODS. Each node will get a /23 (500~ usable IP addresses). Make sure this IP space does not conflict with anything on your LAN.
    hostPrefix: 23
  machineNetwork:
  - cidr: 172.16.1.0/24 # (7)! The network that connects the cluster to your LAN. This is the IP space that resides on your LAN.
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16 # (8)! Used for internal service objects. Make sure this IP space does not conflict with anything on your LAN.
platform:
  baremetal:
    apiVIPs:
      - 172.16.1.5 # (9)! API ip address
    ingressVIPs:
      - 172.16.1.4 # (10)! Ingress API ip address
fips: true # (11)! Boolean: Either true or false to enable or disable FIPS mode. By default, FIPS mode is not enabled. If FIPS mode is enabled, the Red Hat Enterprise Linux CoreOS (RHCOS) machines that OpenShift Container Platform runs on bypass the default Kubernetes cryptography suite and use the cryptography modules that are provided with RHCOS instead
pullSecret: '{"auths":{"registry.example.com:8443": {"auth": "am9zaDpLSW....","email": ""}}}' # (12)! A pull secret for your internal image registry
sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABg....' # (13)! Public ssh key that you define. This key will give ssh access to the nodes through the 'core' user. This is the only way to ssh into the nodes
additionalTrustBundle: | # (14)! The rootCA.pem certificate of your internal image registry
  -----BEGIN CERTIFICATE-----
  MIID1jCCAr6gAwIBAgIUZ11j30+eBRjNEl7IPufQdzMl6oAwDQYJKoZIhvcNAQEL
  BQAwajELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAlZBMREwDwYDVQQHDAhOZXcgWW9y
  azENMAsGA1UECgwEUXVheTERMA8GA1UECwwIRGl2aXNpb24xGTAXBgNVBAMMEHJl
  ...
  -----END CERTIFICATE----- 
imageDigestSources: # (15)! Your image mirrors, this in the idms-oc-mirror.yaml file generated from oc mirror. i.e. /opt/4.17-mirrordata/working-dir/cluster-resources/idms-oc-mirror.yaml 
- mirrors:
  - registry.example.com:8443/v4.17/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - registry.example.com:8443/v4.17/openshift/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

1. The base domain name of the cluster. All DNS records must be sub-domains of this base and include the cluster name.
2. Specify the system architecture. Valid values are `amd64`, `arm64`, `ppc64le`, and `s390x`.
3. This parameter controls the number of compute machines that the Agent-based installation waits to discover before triggering the installation process. It is the number of compute machines that must be booted with the generated ISO.
4. The number of control plane machines that you add to the cluster. Because the cluster uses these values as the number of etcd endpoints in the cluster, the value must match the number of control plane machines that you deploy.
5. The cluster name that you specified in your DNS records.
6. The network that the cluster shares for assigning IPs to PODS. Each node will get a /23 (500~ usable IP addresses). Make sure this IP space does not conflict with anything on your LAN.
7. The network that connects the cluster to your LAN. This is the IP space that resides on your LAN.
8. Used for internal service objects. Make sure this IP space does not conflict with anything on your LAN.
9. API ip address
10. Ingress API ip address
11. Boolean: Either true or false to enable or disable FIPS mode. By default, FIPS mode is not enabled. If FIPS mode is enabled, the Red Hat Enterprise Linux CoreOS (RHCOS) machines that OpenShift Container Platform runs on bypass the default Kubernetes cryptography suite and use the cryptography modules that are provided with RHCOS instead
12. A pull secret for your internal image registry
13. Public ssh key that you define. This key will give ssh access to the nodes through the 'core' user. This is the only way to ssh into the nodes
14. The rootCA.pem certificate of your internal image registry
15. Your image mirrors, this in the idms-oc-mirror.yaml file generated from oc mirror. i.e. /opt/4.17-mirrordata/working-dir/cluster-resources/idms-oc-mirror.yaml