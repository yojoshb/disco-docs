## Creating cluster configs and building the agent ISO

[Red Hat Docs: Install Configuration Parameters](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/installing_an_on-premise_cluster_with_the_agent-based_installer/installing-with-agent-basic#installing-ocp-agent_installing-with-agent-basic){:target="_blank"}

Here is where the cluster is defined. We'll use two files, `install-config.yaml` and `agent-config.yaml` along with the `openshift-install` binary we extracted earlier to create the install `agent.iso`. Examples are given below. Create a directory somewhere to house the config files. This directory will also hold the credentials for API and console access to the cluster when it is built.


1. Install the `nmstate` package
```{ .bash }
sudo dnf install /usr/bin/nmstatectl -y
```
1. Create a directory to store the cluster configuration, we'll call this directory `my_cluster` for this example and it's in the users $HOME directory
```{ .bash }
mkdir ~/my_cluster
```

1. Get the rootCA of your Registry. This is required for the `install-config.yaml` file.
    
    1. Grab the cert using openssl or by some other means
    ```{ .bash .no-copy }
    openssl s_client -connect registry.example.com:8443 -showcerts | awk '/BEGIN/,/END/{print $0}' | tee ./rootCA.pem
    cat rootCA.pem
    
    # If you want your system to trust the registry CA
    sudo cp ./rootCA.pem /etc/pki/ca-trust/source/anchors/
    sudo update-ca-trust
    ```

    1. If you installed Red Hat Quay following this documentation, it is also located on disk where you specified the `quayRoot`.
    ```{ .bash .no-copy }
    cat /opt/quay-root/quay-rootCA/rootCA.pem
    
    # If you want your system to trust the registry CA
    sudo cp /opt/quay-root/quay-rootCA/rootCA.pem /etc/pki/ca-trust/source/anchors/
    sudo update-ca-trust
    ```
    
    !!! info 
        For the `additionalTrustBundle`, the data must be indented as displayed in the example `install-config.yaml` below. You can add indentation with a quick `sed` command to then paste it into your install-config.yaml.
        ```{ .bash }
        sed "s/^/  /" rootCA.pem
        ```

1. Get the pull secret for your mirror registry. This is required for the `install-config.yaml` file. Using `jq` you can print it to stdout in a single line like so:
```{ .bash }
jq -c . $XDG_RUNTIME_DIR/containers/auth.json
```

1. Create the files `install-config.yaml` and `agent-config.yaml` in the directory you defined.

The example below builds a bare metal compact cluster (3 master/control-plane/worker nodes) with static IP's and no external load-balancer. The cluster is called `cluster.example.com`. Each node is called m(1-3).cluster.example.com. You can use these procedures as a basis and modify according to your requirements.

- **install-config.yaml**: This defines your cluster configuration, click on the `+` signs to get a general description of some the values
  
  You can look at several [install-config.yaml examples here in this document](../examples/install-configs.md)
  
  ```{ .yaml .copy title="install-config.yaml: Compact cluster" }
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
      provisioningNetwork: Disabled
  fips: true # (11)! Boolean: Either true or false to enable or disable FIPS mode. By default, FIPS mode is not enabled. If FIPS mode is enabled, the Red Hat Enterprise Linux CoreOS (RHCOS) machines that OpenShift Container Platform runs on bypass the default Kubernetes cryptography suite and use the cryptography modules that are provided with RHCOS instead
  pullSecret: '{"auths":{"registry.example.com:8443": {"auth": "am9zaDpLSW....","email": ""}}}' # (12)! A pull secret for your internal image registry. Best practive is for this secret to only have pull permissions
  sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABg....' # (13)! Public ssh key that you define. This key will give ssh access to the nodes through the 'core' user. This is the only way to ssh into the nodes by default
  additionalTrustBundle: | # (14)! The rootCA.pem certificate of your internal image registry. Note the indentation
    -----BEGIN CERTIFICATE-----
    MIID1jCCAr6gAwIBAgIUZ11j30+eBRjNEl7IPufQdzMl6oAwDQYJKoZIhvcNAQEL
    BQAwajELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAlZBMREwDwYDVQQHDAhOZXcgWW9y
    azENMAsGA1UECgwEUXVheTERMA8GA1UECwwIRGl2aXNpb24xGTAXBgNVBAMMEHJl
    ...
    -----END CERTIFICATE----- 
  additionalTrustBundlePolicy: Always
  imageDigestSources: # (15)! Your image mirrors, this in the idms-oc-mirror.yaml file generated from oc mirror. i.e. /opt/4.17-mirrordata/working-dir/cluster-resources/idms-oc-mirror.yaml 
  - mirrors:
    - registry.example.com:8443/ocp/openshift/release-images # (16)! # You must have a direct reference to both the openshift-release-dev/ocp-release and openshift-release-dev/ocp-v4.0-art-dev paths. These two are the only ones required to complete an installation of OpenShift
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - registry.example.com:8443/ocp/openshift/release
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
  12. A pull secret for your internal image registry. Best practive is for this secret to only have pull permissions
  13. Public ssh key that you define. This key will give ssh access to the nodes through the 'core' user. This is the only way to ssh into the nodes by default
  14. The rootCA.pem certificate of your internal image registry. Note the indentation
  15. Your image mirrors, this in the idms-oc-mirror.yaml file generated from oc mirror. i.e. /opt/4.17-mirrordata/working-dir/cluster-resources/idms-oc-mirror.yaml 
  16. You must have a direct reference to both the openshift-release-dev/ocp-release and openshift-release-dev/ocp-v4.0-art-dev paths. These two are the only ones required to complete an installation of OpenShift

---
- **agent-config.yaml**: This defines your node(s) configuration, click on the `+` signs to get a general description of some of the values
  
  You can look at several [agent-config.yaml examples here in this document](../examples/agent-configs.md)

  ```{ .yaml .copy title="agent-config.yaml: Static IP assignment" }
  apiVersion: v1alpha1
  kind: AgentConfig
  metadata:
    name: cluster # (1)! The cluster name that you specified in your DNS records.
  rendezvousIP: 172.16.1.10 # (2)! Can be the IP of any one of the master nodes. This node will become bootstrap machine during install. A worker cannot be the rendezvous machine.
  additionalNTPSources: # (3)! Optional but recommended for disconnected installs. The install can work without NTP but it'll rely on the system clocks to be correct which may not always be true. IP address or hostname is accepatable 
    - ntp.example.com 
  hosts:
    - hostname: m1.cluster.example.com # (4)! Hostname of the node, must be resolvable by dns.
      role: master # (5)! Recommended to explicitly define roles for your hosts, especially if you're defining masters and workers as they would otherwise be applied at random.
      interfaces:
        - name: enp6s18 # (6)! Name of the interface. If you do not know it, the installer scripts will detect the actual name by mac-address.
          macAddress: BC:24:11:EE:DD:C1 # (7)! Required! The MAC address of an interface on the host, used to determine which host to apply the configuration to.
      networkConfig:
        interfaces:
          - name: enp6s18
            type: ethernet
            state: up
            mac-address: BC:24:11:EE:DD:C1
            ipv4:
              enabled: true
              address:
                - ip: 172.16.1.10 # (8)! The static IP address of the target bare metal host.
                  prefix-length: 24 # (9)! The static IP address’s subnet prefix for the target bare metal host.
              dhcp: false
        dns-resolver:
          config:
            server:
              - 172.16.1.254 # (10)! The DNS server for the target bare metal host.
        routes:
          config:
            - destination: 0.0.0.0/0
              next-hop-address: 172.16.1.254 # (11)! The default gateway, or default route of your node. This must be in the same subnet as the IP address set for the specified interface.
              next-hop-interface: enp6s18
              table-id: 254
    - hostname: m2.cluster.example.com
      role: master
      interfaces:
        - name: enp6s18
          macAddress: BC:24:11:EE:DD:C2
      networkConfig:
        interfaces:
          - name: enp6s18
            type: ethernet
            state: up
            mac-address: BC:24:11:EE:DD:C2
            ipv4:
              enabled: true
              address:
                - ip: 172.16.1.11
                  prefix-length: 24
              dhcp: false
        dns-resolver:
          config:
            server:
              - 172.16.1.254
        routes:
          config:
            - destination: 0.0.0.0/0
              next-hop-address: 172.16.1.254
              next-hop-interface: enp6s18
              table-id: 254
    - hostname: m3.cluster.example.com
      role: master
      interfaces:
        - name: enp6s18
          macAddress: BC:24:11:EE:DD:C3
      networkConfig:
        interfaces:
          - name: enp6s18
            type: ethernet
            state: up
            mac-address: BC:24:11:EE:DD:C3
            ipv4:
              enabled: true
              address:
                - ip: 172.16.1.12
                  prefix-length: 24
              dhcp: false
        dns-resolver:
          config:
            server:
              - 172.16.1.254
        routes:
          config:
            - destination: 0.0.0.0/0
              next-hop-address: 172.16.1.254
              next-hop-interface: enp6s18
              table-id: 254
  ```

  1. The cluster name that you specified in your DNS records.
  2. Can be the IP of any one of the master nodes. This node will become bootstrap machine during install. A worker cannot be the rendezvous machine.
  3. Optional but recommended for disconnected installs. The install can work without NTP but it'll rely on the system clocks to be correct which may not always be true. IP address or hostname is accepatable 
  4. Hostname of the node, must be resolvable by DNS.
  5. Recommended to explicitly define roles for your hosts, especially if you're defining masters and workers as they would otherwise be applied at random.
  6. Name of the interface. If you do not know it, the installer scripts will detect the actual name by mac-address.
  7. Required! The MAC address of an interface on the host, used to determine which host to apply the configuration to.
  8. The static IP address of the target bare metal host.
  9. The static IP address’s subnet prefix for the target bare metal host.
  10. The DNS server for the target bare metal host.
  11. The default gateway, or default route of your node. This must be in the same subnet as the IP address set for the specified interface.

### Validation checks 
The Agent-based Installer performs validation checks on user defined YAML files before the ISO is created. Once the validations are successful, the agent ISO is created.

**`install-config.yaml`**

  - `baremetal`, `vsphere` and `none` platforms are supported.
  - If `none` is used as a platform, the number of control plane replicas must be `1` and the total number of worker replicas must be `0`.
  - The `networkType` parameter must be `OVNKubernetes` in the case of none platform. Generally stick with `OVNKubernetes` for all installs.
  - `apiVIPs` and `ingressVIPs` parameters must be set for bare metal and vSphere platforms.
  - Some host-specific fields in the bare metal platform configuration that have equivalents in `agent-config.yaml` file are ignored. A warning message is logged if these fields are set.

**`agent-config.yaml`**

  - Each interface must have a defined MAC address. Additionally, all interfaces must have a different MAC address.
  - At least one interface must be defined for each host.
  - World Wide Name (WWN) vendor extensions are not supported in root device hints.
  - The `role` parameter in the `host` object must have a value of either `master` or `worker`.

## Creating the agent image

1. Your cluster build directory should look like this
```{ .bash }
tree my_cluster
```
```{ . .no-copy title="Example Output" }
my_cluster
├── agent-config.yaml
└── install-config.yaml

0 directories, 2 files
```

1. Make a copy of this directory and it's contents. When you run `openshift-install` against it, all the files are consumed to build the image.
```{ .bash }
cp -r my_cluster/ my_cluster_backup/
```

1. Create the agent image. It will be saved in the target directory that had the configs.
```{ .bash }
openshift-install --dir my_cluster/ agent create image
```
```{ . .no-copy title="Example Output" }
INFO Configuration has 3 master replicas and 0 worker replicas
WARNING The imageDigestSources configuration in install-config.yaml should have at least one source field matching the releaseImage value registry.example.com:8443/ocp/openshift/release-images@sha256:fd8f5562f0403504b35cc62e064b04c34e6baeb48384bddebffc98c3c69a2af3
INFO The rendezvous host IP (node0 IP) is 172.16.1.10
INFO Extracting base ISO from release payload
INFO Base ISO obtained from release and cached at [/home/admin/.cache/agent/image_cache/coreos-x86_64.iso]
INFO Consuming Install Config from target directory
INFO Consuming Agent Config from target directory
{==INFO Generated ISO at my_cluster/agent.x86_64.iso.==}
```

    - For FIPS, do the same thing but use the FIPS binary
    ```{ .bash }
    openshift-install-fips --dir my_cluster/ agent create image
    ```

    !!! info
        If you have built an ISO before, there may be issues with the caching system that will cause a new build to fail.

        Remove the existing cache, it will exist in the `$HOME` of the installation user

        ```{ .bash }
        rm -rf ~/.cache/agent
        ```