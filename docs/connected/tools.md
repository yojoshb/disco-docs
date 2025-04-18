## Download necessary tools
Be aware of the tool(s) version and architecture. Certain tools require matching to the version of OpenShift you're installing and the correct binary for the RHEL version that you are using. 

- [https://console.redhat.com/openshift/downloads](https://console.redhat.com/openshift/downloads){:target="_blank"} has the latest version of all the tools. 
    - Look through the [public mirror site](https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/){:target="_blank"} if you need to get a specific version.
    - Or access specific versions through the [OpenShift Container Platform downloads page on the Red Hat Customer Portal](https://access.redhat.com/downloads/content/290){:target="_blank"}
    !!! info "This document will go over the ways to check and verify that you have the correct packages before proceeding."
  ---

- **oc**: The OpenShift command line tool to interact with the cluster, also needed to use CLI plugins.
    - [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html-single/cli_tools/index#cli-installing-cli_cli-developer-commands){:target="_blank"}
    - You can use the latest version available for your architecture. `oc` newer than your cluster version may have additional capabilities that your cluster cannot use.
  ---

- **oc-mirror**: Awesome oc plugin tool to streamline getting the required images to a `.tar` file to then transfer to the high-side.
    - [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/disconnected_environments/mirroring-in-disconnected-environments#about-installing-oc-mirror-v2){:target="_blank"}
    - Always use the latest version available for your architecture.
    - **oc-mirror v2** is new, and GA'd for OpenShift 4.18, but is backwards compatible with older releases
    - RHEL 9: `$ wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/oc-mirror.rhel9.tar.gz`
    - RHEL 8: `$ wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/oc-mirror.tar.gz`
  ---

- **openshift-install**: Program that will create the OpenShift install disk that will bootstrap and install the cluster on your hardware. 
    
    !!! warning "Important"
        This binary is specific to the release version of OpenShit you are installing. The binary must match the release images that you mirror. 
    - We can acquire this binary on the low-side, or high-side. Steps will be included for both methods
  ---

- **mirror-registry** (optional): Small registry that can host the required container images to install, update, and maintain the cluster.
    - [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/mirroring-in-disconnected-environments#installing-mirroring-creating-registry){:target="_blank"}
    - Always use the latest version available for your architecture.
    - `$ wget https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-amd64.tar.gz`
  ---

- **butane**: CLI tool to create machine config files to customize OpenShift nodes in your environment. 
    - [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.12/html/installation_configuration/installing-customizing#installation-special-config-butane-install_installing-customizing){:target="_blank"}
    - Always use the latest version available for your architecture.
    - `$ wget https://mirror.openshift.com/pub/openshift-v4/clients/butane/latest/butane-amd64`


## Install/configure tools

1. Put `oc` and `oc-mirror` tools we need on the low-side in your `$PATH`. Either `/usr/local/bin` or somewhere like `/home/$USER/bin` or `/home/$USER/.local/bin`
```bash
$ sudo tar -xzvf openshift-client-linux.tar.gz -C /usr/local/bin/
$ sudo tar -xzvf oc-mirror.tar.gz -C /usr/local/bin/ # RHEL 8
$ sudo tar -xzvf oc-mirror.rhel9.tar.gz -C /usr/local/bin/ # RHEL 9
$ sudo chmod +x /usr/local/bin/oc-mirror
```
1. Make sure you have set the umask parameter to `0022` on the operating system that uses oc-mirror
1. Verify that the oc-mirror v2 plugin is successfully installed by running the following command
```bash
$ oc mirror --v2 --help
```

## Grab your pull-secret from your Red Hat Account 
[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/mirroring-in-disconnected-environments#installation-adding-registry-pull-secret_installing-mirroring-disconnected){:target="_blank"}

1. Download or copy your `registry.redhat.io` [pull secret from the Red Hat OpenShift Cluster Manager](https://console.redhat.com/openshift/install/pull-secret){:target="_blank"}. These are your credentials for accessing Red Hat container registries.

1. Make a copy of your pull secret in JSON format:
```bash
$ cat ./pull-secret | jq . > rh-pull-secret.json
``` 

1. Specify the path to the folder to store the pull secret in and a name for the JSON file that you create. You can store this file in `/home/$USER/.docker/config.json` or `$XDG_RUNTIME_DIR/containers/auth.json`. If one of the directories aren't there, create them.
    - The contents of the file resemble the following example:
```json
{
  "auths": {
    "cloud.openshift.com": {
      "auth": "b3BlbnNo...",
      "email": "you@example.com"
    },
    "quay.io": {
      "auth": "b3BlbnNo...",
      "email": "you@example.com"
    },
    "registry.connect.redhat.com": {
      "auth": "NTE3Njg5Nj...",
      "email": "you@example.com"
    },
    "registry.redhat.io": {
      "auth": "NTE3Njg5Nj...",
      "email": "you@example.com"
    }
  }
}
```

1. Verify you can authenticate to `registry.redhat.io`
```bash
$ podman login registry.redhat.io
Authenticating with existing credentials for registry.redhat.io
Existing credentials are valid. Already logged in to registry.redhat.io
```