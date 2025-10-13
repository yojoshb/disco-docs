## Prepare the tools

Identify a host on the disconnected network that will be used for installing the cluster. Optionally, identify a host that will become the mirror registry if you are using the Red Hat Mirror Registry and do not already have a registry set up in your environment.

- If you brought the tools over as `.tar` extract them to your `$PATH` like the connected process, or copy them there if you brought the binaries to your high-side host
```{ .bash .no-copy }
sudo cp /mnt/transfer-disk/{oc,oc-mirror,butane} /usr/local/bin/
sudo chmod +x /usr/local/bin/{oc,oc-mirror,butane}

# If selinux is enabled
sudo restorecon -v /usr/local/bin/{oc,oc-mirror,butane}
```

- Make sure you have set the umask parameter to `0022` on the operating system that uses oc-mirror
```{ .bash }
umask 0022
```
- Verify oc mirror works
```{ .bash }
oc mirror --v2 --help
```

- If you brought over the `openshift-install` binary copy it to your `$PATH`.  
```{ .bash .no-copy }
sudo cp /mnt/transfer-disk/openshift-install /usr/local/bin/
sudo chmod +x /usr/local/bin/openshift-install

# If selinux is enabled
sudo restorecon -v /usr/local/bin/openshift-install
```

- Optional: Copy the mirror-registry-amd64.tar.gz file to the host that you want to become your mirror registry. This can be the same host, just make sure you have enough storage space to hold the mirrored images that will be uploaded into the registry
```{ .bash }
cp /mnt/transfer-disk/mirror-registry-amd64.tar.gz /opt
```

!!! info
    If the system is STIG'd and using fapolicyd either disable it, or make changes as it automatically blocks any binary that is not an RPM.

    You can add the binaries to the policy like so:
    
    ```{ .bash .no-copy }
    systemctl stop fapolicyd.service
    
    sudo fapolicyd-cli --file add /usr/local/bin/oc
    sudo fapolicyd-cli --file add /usr/local/bin/oc-mirror
    sudo fapolicyd-cli --file add /usr/local/bin/butane
    sudo fapolicyd-cli --file add /usr/local/bin/openshift-install
    sudo fapolicyd-cli --update
    
    systemctl start fapolicyd.service; systemctl status fapolicyd.service
    ```


## Create a directory structure

!!! note
    You can just keep everything on the `transfer-disk` and mirror off of it if you want and skip this step. Be sure to stay organized

1. Do this how you see fit for your environment. Identify a space on your disconnected machine that can hold the imageset-config.yaml, mirror_000001.tar, and generated cluster configs
```{ .bash }
mkdir /opt/4.17-mirrordata
```

1.  Copy the imageset-config and mirror_000001.tar to that directory
```{ .bash }
cp /mnt/transfer-disk/{imageset-config.yaml,mirror_000001.tar} /opt/4.17-mirrordata/
```

## Create your pull/push secret for your mirror registry
If you already have a registry in your target environment, you can generate a secret from it and place it in a json file like earlier. 

If you do not have a registry in your target environment that can store the mirror images, [install the Red Hat Mirror Registry](../optional/registry.md).

1. Make a copy of your pull secret in JSON format:
    ```{ .bash  }
    cat ./pull-secret | jq . > registry-pull-secret.json
    ``` 

1. Specify the path to the folder to store the pull secret in and a name for the JSON file that you create. You can store this file in `/home/$USER/.docker/config.json` or `$XDG_RUNTIME_DIR/containers/auth.json`. If one of the directories aren't there, create them.
    - The contents of the file resemble the following example:
    ```{ .json .no-copy title="$XDG_RUNTIME_DIR/containers/auth.json" }
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
    ```{ .bash }
    podman login --tls-verify=false registry.example.com:8443
    ```
    ```{ . .no-copy title="Example Output" }
    Authenticating with existing credentials for registry.example.com:8443
    Existing credentials are valid. Already logged in to registry.example.com:8443
    ```

1. By the end, you should have a Registry account that can push/pull (so oc-mirror can push images to it) and a account that can only pull (so the cluster can access the images for installing/updating). This registry should ideally only be used to hold OpenShift release images.