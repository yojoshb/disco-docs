## Mirror Registry for Red Hat OpenShift

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html-single/disconnected_environments/index#installing-mirroring-creating-registry)

- This is a quick install config for the Red Hat provided mirror registry if you want to use it. Make sure you have transferred the `mirror-registry-amd64.tar.gz` from the connected side.
    - There are a few ways to install this, refer to the Red Hat docs above for additional installation examples and configurations.
    - This example will go over installing the mirror registry to a local host called `registry.example.com`, and storing the persistent data in a directory on disk as a non-root user in `/opt`

---

1. Prerequisites
    - Red Hat Enterprise Linux (RHEL) 8 and 9 with Podman 3.4.2 or later and OpenSSL installed.
    - Fully qualified domain name for the Red Hat Quay service, which must resolve through a DNS server. (i.e. `registry.example.com`)
    - Key-based SSH connectivity on the target host. SSH keys are automatically generated for local installs. For remote hosts, you must generate your own SSH keys.
    - 2 or more vCPUs.
    - 8 GB or more of RAM.
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
    
  - Installing the mirror registry. This will kick off an ansible playbook and install and run the pods
    ```bash
    $ ./mirror-registry install --quayHostname registry.example.com --quayRoot /opt/quay-root --quayStorage /opt/quay-storage
    ...
    PLAY RECAP ********************************************************************************************************************************************************************admin@registry.example.com : ok=50   changed=28   unreachable=0    failed=0    skipped=14   rescued=0    ignored=0

    INFO[2025-03-17 14:39:08] Quay installed successfully, config data is stored in /opt/quay-root
    INFO[2025-03-17 14:39:08] Quay is available at https://registry.example.com:8443 with credentials (init, 4AywhWu5xsjiN2et09C3mg1rV7K6IS8f)
    ```

## Create your pull/push secret for your mirror registry
Generate a secret from the mirror registry and save it to your machine. 

1. Make a copy of your pull secret in JSON format:
    ```bash
    $ cat ./pull-secret | jq . > registry-pull-secret.json
    ``` 

1. Specify the path to the folder to store the pull secret in and a name for the JSON file that you create. You can store this file in `/home/$USER/.docker/config.json` or `$XDG_RUNTIME_DIR/containers/auth.json`. If one of the directories aren't there, create them.
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

1. Verify that you can login to your registry. Your account should have push and pull permissions to your registry
    ```bash
    $ podman login --tls-verify=false registry.example.com:8443
    Authenticating with existing credentials for registry.example.com:8443
    Existing credentials are valid. Already logged in to registry.example.com:8443
    ```

1. Continue to [mirroring images to registry](../disconnected/mirroring.md)