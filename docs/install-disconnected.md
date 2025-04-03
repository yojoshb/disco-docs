### Prepare the tools
If you brought the tools over in `.tar` extract them to your `$PATH` like the low-side process, or copy them there if you brought the binaries to your high-side mirror host
```bash
$ sudo cp /mnt/transfer-disk/{oc,oc-mirror,butane} /usr/local/bin/

# Verify oc mirror works
$ oc mirror --v2 --help
```

### Create a directory structure
Do this how you see fit for your environment. Identify a space on your high-side mirror host that can hold the imageset-config.yaml, mirror_000001.tar, and generated cluster configs
```bash
$ mkdir /opt/4.17-mirrordata
```
- Copy the imageset-config and mirror_000001.tar to that directory
```bash 
$ cp /mnt/transfer-disk/{imageset-config.yaml,mirror_000001.tar} /opt/4.17-mirrordata
```

#### Mirror Registry for Red Hat OpenShift
If you do not have a registry in your environment, you can use the [mirror registry for Red Hat OpenShift.](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html-single/disconnected_environments/index#installing-mirroring-creating-registry)

If you already have a registry in your target environment, skip this section and continue to creating your push/pull secret for your mirror registry.

- This is a quick install config for the Red Hat provided mirror registry if you want to use it. Make sure you have brought over the `mirror-registry-amd64.tar.gz` from the low-side.
    - There are a few ways to install this, refer to the docs above for additional installation examples and configurations.
    - This example will go over installing the mirror registry to a local host called `registry.example.com`, and storing the persistent data in a directory on disk as a non-root user in `/opt`

---

1. Prerequisites
    - Red Hat Enterprise Linux (RHEL) 8 and 9 with Podman 3.4.2 or later and OpenSSL installed.
    - Fully qualified domain name for the Red Hat Quay service, which must resolve through a DNS server. (i.e. `registry.example.com`)
    - Key-based SSH connectivity on the target host. SSH keys are automatically generated for local installs. For remote hosts, you must generate your own SSH keys.
    - 2 or more vCPUs.
    - 8 GB of RAM.
    - About 12 GB for OpenShift Container Platform 4.17 release images, or about 358 GB for OpenShift Container Platform 4.17 release images and OpenShift Container Platform 4.17 Red Hat Operator images. Up to 1 TB per stream or more is suggested. Shoot for 100GB+

1. Create a directory structure for the mirror registry contents. This example expects the `/opt` directory to have have sufficient space to hold the data for the images mirrored earlier as well as sufficient permissions for a **non-root** account to read/write to this area. Change this path/structure as you see fit for your environment.
    ```bash
    $ umask 0022
    $ mkdir /opt/{mirror-registry,quay-storage,quay-root}
    ```
1. Bring the mirror registry over to the machine that will be the registry host and untar it
    ```bash
    $ cp /mnt/transfer-disk/mirror-registry-amd64.tar.gz /opt/mirror-registry/
    $ cd /opt/mirror-registry
    $ tar -xzvf mirror-registry-amd64.tar.gz
    ```
1. Firewall tcp port 8443 must be opened
    ```bash
    $ sudo firewall-cmd --add-port=8443/tcp --permanent
    $ sudo firewall-cmd --reload
    ```
1. Verify the fully qualified hostname is set and can be resolved in dns
    ```bash
    $ hostname -f
    registry.example.com
    ```
2. Install the mirror registry

!!! warning "If this system is DISA STIG'd, or otherwise not a vanilla RHEL install the following changes may need to be made/adjusted"
    
    - `sysctl user.max_user_namespaces` must **not** be set to `0`. Namespaces are needed for rootless podman
    
    - `noexec` must **not** be enabled on `/home`, **or** podman must be configured to use a different `rootless_storage_path` directory on a filesystem that allows exec. `rootless_storage_path` is defined in `/etc/containers/storage.conf`. 
        - This can be overridden on a per-user basis as well if needed by creating `~/.config/containers/storage.conf` and making edits there
    
    - `fapolicyd` may need to be adjusted or disabled
    
    - If the users `$HOME` is on NFS network storage, adjustments will need to be made
        - Refer to this article: https://www.redhat.com/en/blog/rootless-podman-nfs
    
    - The user running podman must be a local Linux account, or have SUBUID/SUBGID explicitly defined in `/etc/subuid` and `/etc/subgid`. Network accounts such as Active Directory don't exist in `/etc/passwd` so the podman tools have no idea how to create these maps for you at the moment
    
    - Installing as root is not recommended but can be done, ssh access as root will need to be enabled for the install though which is highly frowned upon
    
  - Installing the mirror registry
    ```bash
    $ ./mirror-registry install --quayHostname registry.example.com --quayRoot /opt/quay-root --quayStorage /opt/quay-storage
    ...
    PLAY RECAP ********************************************************************************************************************************************************************admin@registry.example.com : ok=50   changed=28   unreachable=0    failed=0    skipped=14   rescued=0    ignored=0

    INFO[2025-03-17 14:39:08] Quay installed successfully, config data is stored in /opt/quay-root
    INFO[2025-03-17 14:39:08] Quay is available at https://registry.example.com:8443 with credentials (init, 4AywhWu5xsjiN2et09C3mg1rV7K6IS8f)
    ```

### Create your pull/push secret for your mirror registry
If you already have a registry in your target environment, you can generate a secret from it and place it in a json file like earlier. 

1. Make a copy of your pull secret in JSON format:
    ```bash
    $ cat ./pull-secret | jq . > registry-pull-secret.json
    ``` 

2. Specify the path to the folder to store the pull secret in and a name for the JSON file that you create. You can store this file in `/home/$USER/.docker/config.json` or `$XDG_RUNTIME_DIR/containers/auth.json`. If one of the directories aren't there, create them.
    - The contents of the file resemble the following example:
    ```json title="$XDG_RUNTIME_DIR/containers/auth.json"
    {
      "auths": {
        "registry.example.com:8443": {
          "auth": "b3BlbnNo...",
          "email": "you@example.com"
        }
      }
    }
    ```

3. Verify that you can login to your registry. Your account should have push and pull permissions to your registry
    ```bash
    $ podman login --tls-verify=false registry.example.com:8443
    Authenticating with existing credentials for registry.example.com:8443
    Existing credentials are valid. Already logged in to registry.example.com:8443
    ```

### Mirroring images from disk to your mirror
[Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/mirroring-in-disconnected-environments#disk-mirror-v2_about-installing-oc-mirror-v2)

Now that the images are on the disk and you have a target registry with push/pull permissions to mirror to, we can mirror them to your registry

- Pass in the image set configuration file that you brought over or created. This procedure assumes that it is named `imageset-config.yaml`. If you named your's differently, sub in your name of the file.
- Specify the target directory where the `mirror_000001.tar` file is. The target directory path must start with `file://`. This procedure assumes you want to upload the mirror_000001.tar **from** `/opt/4.17-mirrordata/`.
  - The target directory will also hold the `working-dir` environment. This directory contains the various necessary data to build, update, and maintain cluster resources. Keep this directory safe, and do not modify it. It will be used again for updates and additions to your cluster
- Be aware of the caching system, this will also take up considerable space on the disk depending on how many images are being uploaded to your mirror
  > - Where is it saved?
  >     - By default in `$HOME/.oc-mirror/.cache`
  > - Can I control where I want the cache to be stored?
  >     - Yes, you can pass `--cache-dir <dir>` which will change the cache location to `<dir>/.oc-mirror/.cache`
  > - During the mirroring process, is there a way to resume if something goes wrong?
  >     - Yes, by re-running oc mirror
---
1. Upload your images to your mirror
  ```bash
  $ oc mirror -c /opt/4.17-mirrordata/imageset-config.yaml --from file:///opt/4.17-mirrordata docker://registry.example.com:8443/v4.17 --v2
  ...
  [INFO]   : === Results ===
  [INFO]   :  ✓  185 / 185 release images mirrored successfully
  [INFO]   :  ✓  8 / 8 operator images mirrored successfully
  [INFO]   :  ✓  1 / 1 additional images mirrored successfully
  [INFO]   : 📄 Generating IDMS file...
  [INFO]   : /opt/4.17-mirrordata/working-dir/cluster-resources/idms-oc-mirror.yaml file created
  [INFO]   : 📄 Generating ITMS file...
  [INFO]   : /opt/4.17-mirrordata/working-dir/cluster-resources/itms-oc-mirror.yaml file created
  [INFO]   : 📄 Generating CatalogSource file...
  [INFO]   : /opt/4.17-mirrordata/working-dir/cluster-resources/cs-redhat-operator-index-v4-17.yaml file created
  [INFO]   : 📄 Generating ClusterCatalog file...
  [INFO]   : /opt/4.17-mirrordata/working-dir/cluster-resources/cc-redhat-operator-index-v4-17.yaml file created
  [INFO]   : 📄 Generating Signature Configmap...
  [INFO]   : /opt/4.17-mirrordata/working-dir/cluster-resources/signature-configmap.json file created
  [INFO]   : /opt/4.17-mirrordata/working-dir/cluster-resources/signature-configmap.yaml file created
  [INFO]   : 📄 Generating UpdateService file...
  [INFO]   : /opt/4.17-mirrordata/working-dir/cluster-resources/updateService.yaml file created
  [INFO]   : mirror time     : 14m20.563306852s
  [INFO]   : 👋 Goodbye, thank you for using oc-mirror
  ```

    - If your mirror registry is using a self-signed certificate and your machine doesn't trust it internally use the `--dest-tls-verify=false` flag
    ```bash
    $ oc mirror --dest-tls-verify=false -c /opt/4.17-mirrordata/imageset-config.yaml --from file:///opt/4.17-mirrordata docker://registry.example.com:8443/v4.17 --v2
    ```
    - If you get an error like the one below, your registry most likely cannot write the data fast enough. You can try doing it again with less parallel operations using the `--parallel-images` flag
    ```
    [ERROR]  : [Worker] error mirroring image quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:dae0aadc59c79509779a9e904e0aeaa6d5c5e3f24eedc5c114c6bca1b15ea3b1 error: trying to reuse blob sha256:25c75c34b2e2b68ba9245d9cddeb6b8a0887371ed30744064f85241a75704d87 at destination: can't talk to a V1 container registry
    ```
    ```bash
    # Default is 8 parallel
    oc mirror --dest-tls-verify=false --parallel-images 4 -c /opt/4.17-mirrordata/imageset-config.yaml --from file:///opt/4.17-mirrordata docker://registry.example.com:8443/v4.17 --v2
    ```

1. Verify the cluster resources were generated and their are no errors in the logs
   ```bash
   $ cd /opt/4.17-mirrordata
   ```

## Building the cluster
Now we can define records in DNS, create a couple of boilerplate yaml files that will define our cluster, and then build create the ISO image that will bootstrap and install the cluster.

### DNS
[Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/installing_on_bare_metal/installing-restricted-networks-bare-metal#installation-dns-user-infra_installing-restricted-networks-bare-metal)

These records are mandatory for the cluster to function. Technically the cluster can function without an external DNS source, but it will be much harder to use and access the cluster and recourses it provides/hosts and each node will need a curated `/etc/hosts` file provisioned.

- The following DNS records are required for a user-provisioned OpenShift Container Platform cluster and they must be in place before installation. In each record, `<cluster_name>` is the cluster name and `<base_domain>` is the base domain that you specify in the install-config.yaml file. A complete DNS record takes the form: `<component>.<cluster_name>.<base_domain>.`

  |Component      |Record                            |Type                                   |Description        |
  |-              |-                                 |-                                      |-                  |
  |Kubernetes API |api.<cluster_name\>.<base_domain\>. |DNS A/AAAA or CNAME and DNS PTR record |To identify the API load balancer. These records must be resolvable by both clients external to the cluster and from all the nodes within the cluster.|
  |Kubernetes API |api-int.<cluster_name\>.<base_domain\>. |DNS A/AAAA or CNAME and DNS PTR record |To internally identify the API load balancer. These records must be resolvable from all the nodes within the cluster.|
  |Routes |*.apps.<cluster_name\>.<base_domain\>. |wildcard DNS A/AAAA or CNAME record |Refers to the application ingress load balancer. The application ingress load balancer targets the machines that run the Ingress Controller pods. The Ingress Controller pods run on the compute machines by default. These records must be resolvable by both clients external to the cluster and from all the nodes within the cluster.|
  |Control plane machines |<control_plane\><n\>.<cluster_name\>.<base_domain\>. |DNS A/AAAA or CNAME and DNS PTR record |To identify each machine for the control plane nodes. These records must be resolvable by the nodes within the cluster.|
  |Compute machines |<compute\><n\>.<cluster_name\>.<base_domain\>. |DNS A/AAAA or CNAME and DNS PTR record |To identify each machine for the worker nodes. These records must be resolvable by the nodes within the cluster.|

- Here's and example for a 3 node high-avalablity compact cluster using the builtin HAProxy load balancer that OpenShift comes with out of the box. The cluster name is `cluster` and the base domain is `example.com`
  
    !!! note
        This is not a true load balancer as traffic will always go to the pod where Ingress VIP is attached.

  |Component        |Record                       |IP Address   |Type               |
  |-                |-                            |-            |-                  |
  |Kubernetes API   |api.cluster.example.com      |172.16.1.5   |DNS A/PTR record   |
  |Kubernetes API   |api-int.cluster.example.com  |172.16.1.4   |DNS A/PTR record   |
  |Routes           |*.apps.cluster.example.com   |172.16.1.5   |DNS wildcard record|
  |Master node 1    |m1.cluster.example.com       |172.16.1.10  |DNS A/PTR record   |
  |Master node 2    |m2.cluster.example.com       |172.16.1.11  |DNS A/PTR record   |
  |Master node 3    |m3.cluster.example.com       |172.16.1.12  |DNS A/PTR record   |

- Check forward, reverse, and wildcard DNS resolution
    - Forward lookup for the record `api.cluster.example.com` answered by the DNS server at `172.16.1.254`
    ```bash hl_lines="15 18"
    $ dig api.cluster.example.com
  
    ; <<>> DiG 9.16.23-RH <<>> api.cluster.example.com
    ;; global options: +cmd
    ;; Got answer:
    ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 13520
    ;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
    
    ;; OPT PSEUDOSECTION:
    ; EDNS: version: 0, flags:; udp: 1232
    ;; QUESTION SECTION:
    ;api.cluster.example.com.           IN      A
    
    ;; ANSWER SECTION:
    api.cluster.example.com.    3600    IN      A       172.16.1.5
    
    ;; Query time: 0 msec
    ;; SERVER: 172.16.1.254#53(172.16.1.254)
    ;; WHEN: Mon Mar 24 16:11:11 CDT 2025
    ;; MSG SIZE  rcvd: 64
    ```
    - Reverse lookup for the record `172.16.1.5` answered by the DNS server at `172.16.1.254`
    ```bash hl_lines="15 18"
    $ dig -x 172.16.1.5
  
    ; <<>> DiG 9.16.23-RH <<>> -x 172.16.1.5
    ;; global options: +cmd
    ;; Got answer:
    ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 62615
    ;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
    
    ;; OPT PSEUDOSECTION:
    ; EDNS: version: 0, flags:; udp: 1232
    ;; QUESTION SECTION:
    ;5.1.16.172.in-addr.arpa.     IN      PTR
    
    ;; ANSWER SECTION:
    5.1.16.172.in-addr.arpa. 3600 IN      PTR     api.cluster.example.com.
    
    ;; Query time: 0 msec
    ;; SERVER: 172.16.1.254#53(172.16.1.254)
    ;; WHEN: Mon Mar 24 16:11:52 CDT 2025
    ;; MSG SIZE  rcvd: 91 
    ```
    - Wildcard lookup for the record `someapp.apps.cluster.example.com` answered by the DNS server at `172.16.1.254`
    ```bash hl_lines="15 18"
    $ dig someapp.apps.cluster.example.com
  
    ; <<>> DiG 9.16.23-RH <<>> someapp.apps.cluster.example.com
    ;; global options: +cmd
    ;; Got answer:
    ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 46996
    ;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
    
    ;; OPT PSEUDOSECTION:
    ; EDNS: version: 0, flags:; udp: 1232
    ;; QUESTION SECTION:
    ;someapp.apps.cluster.example.com.  IN      A
    
    ;; ANSWER SECTION:
    someapp.apps.cluster.example.com. 3600 IN   A       172.16.1.5
    
    ;; Query time: 0 msec
    ;; SERVER: 172.16.1.254#53(172.16.1.254)
    ;; WHEN: Mon Mar 24 16:13:18 CDT 2025
    ;; MSG SIZE  rcvd: 73 
    ```

### Installation Config Files
Here is where the cluster is defined. We'll use two files, `install-config.yaml` and `agent-config.yaml` along with the `openshift-install` binary we extracted earlier to create the install agent.iso. Examples with commented sections are given below. Create a directory somewhere to house the config files. This directory will also hold the credentials for API access to the cluster when it is built.

- **install-config.yaml**: This defines your cluster resources, click on the `+` signs to get a description of the values
  
  [Docs examples]()
  
  ```yaml title="install-config.yaml"
  apiVersion: v1
  baseDomain: example.com # (1)!
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
  fips: true # (10)! Either true or false
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
- **agent-config.yaml**
  [Docs examples]()
  ```yaml
  apiVersion: v1alpha1
  kind: AgentConfig
  metadata:
    name: cluster # Name of the cluster
  rendezvousIP: 172.16.1.10 # Can be the IP of any one of the master nodes. This node will be the main bootstrap machine during install
  hosts:
    - hostname: m1.cluster.example.com # Hostname of the node 
      interfaces:
        - name: enp6s18 # Name of the interface, may need to boot the node into linux to find this
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
                - ip: 172.16.1.10 # IP address that this node will get
                  prefix-length: 24
              dhcp: false
        dns-resolver:
          config:
            server:
              - 172.16.1.254 # DNS server address
        routes:
          config:
            - destination: 0.0.0.0/0
              next-hop-address: 172.16.1.254 # The default-gateway 
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

### Installing the ISO
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