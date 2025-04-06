Here is where the cluster is defined. We'll use two files, `install-config.yaml` and `agent-config.yaml` along with the `openshift-install` binary we extracted earlier to create the install `agent.iso`. Examples are given below. Create a directory somewhere to house the config files. This directory will also hold the credentials for API access to the cluster when it is built.

The examples below build a compact cluster (HA: 3 control-plane/master/worker) with static IP's. The cluster is called `cluster.example.com`. Each node is called m(1-3).cluster.example.com. 

- **install-config.yaml**: This defines your cluster configuration, click on the `+` signs to get a general description of some the values
  
  [Docs examples]()
  
  ```yaml title="install-config.yaml"
  apiVersion: v1
  baseDomain: example.com # (1)! Your base domain name of the cluster
  compute:
  - architecture: amd64
    hyperthreading: Enabled
    name: worker
    replicas: 0 # (2)! Zero workers for this build as it's a compact cluster
  controlPlane:
    architecture: amd64
    hyperthreading: Enabled
    name: master
    replicas: 3 # (3)! HA compact cluster needs 3 master nodes
  metadata:
    name: cluster # (4)! The cluster name
  networking:
    clusterNetwork:
    - cidr: 10.128.0.0/14 # (5)! The network that the cluster shares for assigning IPs to PODS. Each node will get a /23 (500~ usable IP addresses). Make sure this IP space does not conflict with anything on your LAN.
      hostPrefix: 23
    machineNetwork:
    - cidr: 172.16.1.0/24 # (6)! The network that connects the cluster to your lan. This is the IP space that resides on your LAN.
    networkType: OVNKubernetes
    serviceNetwork:
    - 172.30.0.0/16 # (7)! Used for internal service objects. Make sure this IP space does not conflict with anything on your LAN.
  platform:
    baremetal:
      apiVIPs:
        - 172.16.1.5 # (8)! API ip address
      ingressVIPs:
        - 172.16.1.4 # (9)! Ingress API ip address
  fips: true # (10)! Boolean: either true or false
  pullSecret: '{"auths":{"registry.example.com:8443": {"auth": "am9zaDpLSW....","email": ""}}}' # (11)! A pull secret for your internal image registry
  sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABg....' # (12)! Public ssh key that you define. This key will give ssh access to the nodes through the 'core' user. This is the only way to ssh into the baremetal nodes
  additionalTrustBundle: | # (13)! The rootCA.pem certificate of your internal image registry
    -----BEGIN CERTIFICATE-----
    MIID1jCCAr6gAwIBAgIUZ11j30+eBRjNEl7IPufQdzMl6oAwDQYJKoZIhvcNAQEL
    BQAwajELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAlZBMREwDwYDVQQHDAhOZXcgWW9y
    azENMAsGA1UECgwEUXVheTERMA8GA1UECwwIRGl2aXNpb24xGTAXBgNVBAMMEHJl
    ...
    -----END CERTIFICATE----- 
  imageContentSources: # (14)! Your image mirrors, this in the idms-oc-mirror.yaml file from oc mirror; /opt/4.17-mirrordata/working-dir/cluster-resources/idms-oc-mirror.yaml 
  - mirrors:
    - registry.example.com:8443/v4.17/openshift/release-images
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - registry.example.com:8443/v4.17/openshift/release
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
  ```

  1. Your base domain name of the cluster
  1. Zero workers for this build as it's a compact cluster
  1. HA compact cluster needs 3 master nodes
  1. The cluster name
  1. The network that the cluster shares for assigning IPs to PODS. Each node will get a /23 (500~ usable IP addresses). Make sure this IP space does not conflict with anything on your LAN.
  1. The network that connects the cluster to your lan. This is the IP space that resides on your LAN.
  1. Used for internal service objects. Make sure this IP space does not conflict with anything on your LAN.
  1. API ip address
  1. Ingress API ip address
  1. Either true or false
  1. A pull secret for your internal image registry
  1. Public ssh key that you define. This key will give ssh access to the nodes through the 'core' user. This is the only way to ssh into the baremetal nodes
  1. The rootCA.pem certificate of your internal image registry
  1. Your image mirrors, this in the idms-oc-mirror.yaml file from oc mirror; /opt/4.17-mirrordata/working-dir/cluster-resources/idms-oc-mirror.yaml 

---
- **agent-config.yaml**: This defines your node configuration(s), click on the `+` signs to get a general description of some of the values
  
  [Docs examples]()

  ```yaml title="agent-config.yaml"
  apiVersion: v1alpha1
  kind: AgentConfig
  metadata:
    name: cluster # (1)! The cluster name
  rendezvousIP: 172.16.1.10 # (2)! Can be the IP of any one of the master nodes. This node will become bootstrap machine during install. A worker cannot be the rendezvous machine
  hosts:
    - hostname: m1.cluster.example.com # (3)! Hostname of the node, must be resolvable by dns
      interfaces:
        - name: enp6s18 # (4)! Name of the interface, may need to boot the node into linux to find this
          macAddress: BC:24:11:EE:DD:C1
      networkConfig:
        interfaces:
          - name: enp6s18
            type: ethernet
            state: up
            mac-address: BC:24:11:EE:DD:C1
            ipv4:
              enabled: true
              address:
                - ip: 172.16.1.10 # (5)! IP address that this node will get
                  prefix-length: 24
              dhcp: false
        dns-resolver:
          config:
            server:
              - 172.16.1.254 # (6)! DNS server address, you can list more than one
        routes:
          config:
            - destination: 0.0.0.0/0
              next-hop-address: 172.16.1.254 # (7)! The default gateway, or default route of your node
              next-hop-interface: enp6s18
              table-id: 254
    - hostname: m2.cluster.example.com
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
                - ip: 172.99.99.11
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