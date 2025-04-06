## Prepare the tools
If you brought the tools over in `.tar` extract them to your `$PATH` like the low-side process, or copy them there if you brought the binaries to your high-side mirror host
```bash
$ sudo cp /mnt/transfer-disk/{oc,oc-mirror,butane} /usr/local/bin/

# Verify oc mirror works
$ oc mirror --v2 --help
```

If you brought over the `openshift-install` binary and `mirror-registry.tar.gz` copy those off as well. You can place the openshift-install binary in your $PATH if you want, but it'll only be used to build the cluster ISO and can be discarded after use. 

## Create a directory structure
1. Do this how you see fit for your environment. Identify a space on your disconnected machine that can hold the imageset-config.yaml, mirror_000001.tar, and generated cluster configs
```bash
$ mkdir /opt/4.17-mirrordata
```

1.  Copy the imageset-config and mirror_000001.tar to that directory
```bash 
$ cp /mnt/transfer-disk/{imageset-config.yaml,mirror_000001.tar} /opt/4.17-mirrordata
```

## Create your pull/push secret for your mirror registry
If you already have a registry in your target environment, you can generate a secret from it and place it in a json file like earlier. 

If you do not have a registry in your target environment that can store the mirror images, click [here for Red Hat Mirror Registry instructions](../optional/registry.md).

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