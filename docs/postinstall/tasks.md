## Additional Post-Install Tasks

Many of these settings have already been applied if you deployed the cluster with the appropriate customizations but it's good to double check everything. Much of this is regurgitated information from [Source: Kens disconnected-openshift Repo](https://github.com/kenmoini/disconnected-openshift/blob/main/post-install-config/README.md#post-installation-cluster-configuration){:target="_blank"} which is a great resource for additional diconnected install information/configs/tools.

## Cluster-wide CA Certs

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/security_and_compliance/configuring-certificates#ca-bundle-understanding_updating-ca-bundle){:target="_blank"}

Typically you'll have custom internal Root Certificate Authorities that sign TLS certs for services. If you provided the certificates during installation (your mirror registry for example), you should find them in the `user-ca-bundle` ConfigMap in the `openshift-config` Namespace under the `ca-bundle.crt` key. 

1. Verify that the contents match what you have for your Root CAs
```{ .bash }
oc get cm/user-ca-bundle -n openshift-config -o yaml
```
```{ . .no-copy title="Example Output" }
apiVersion: v1
data:
  ca-bundle.crt: |
    -----BEGIN CERTIFICATE-----
    MIID1jCCAr6gAwIBAgIUZ11....
    -----END CERTIFICATE-----
    -----BEGIN CERTIFICATE-----
    MIID1jCCAr6gAwIBAgIUZ11....
    -----END CERTIFICATE-----
kind: ConfigMap
...
```

2. If you need to add additional CA's, modify this ConfigMap with the cert data
```{ .yaml title="user-ca-bundle.yaml" }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: user-ca-bundle
  namespace: openshift-config
data:
  ca-bundle.crt: |
    -----BEGIN CERTIFICATE-----
    MIID1jCCAr6gAwIBAgIUZ11....
    -----END CERTIFICATE-----
    -----BEGIN CERTIFICATE-----
    MIID1jCCAr6gAwIBAgIUZ11....
    -----END CERTIFICATE-----
    -----BEGIN CERTIFICATE-----
    ... other other cert text ...
    -----END CERTIFICATE-----
```

    !!! warning "This may cause nodes to reboot so be prepared"
```{ .bash }
# Edit from the cmdline and copy/paste contents
oc edit configmaps user-ca-bundle -n openshift-config

# Or

# Apply the yaml file if you created one
oc apply -f user-ca-bundle.yaml
```

3. With the Root CA Certificates in the cluster-wide ConfigMap, you can now create other ConfigMaps with a special label that will inject all the trusted Root CA certificates into it which makes it easy to be used by applications
```{ .yaml title="image-additional-trust-bundle.yaml" }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: image-additional-trust-bundle
  namespace: openshift-config
  labels:
    # This label will create the .data['ca-bundle.crt'] key with all the system trusted roots, custom and default
    config.openshift.io/inject-trusted-cabundle: 'true'
```
```{ .bash }
# Apply the yaml file
oc apply -f image-additional-trust-bundle.yaml
```

## Disabling the Insights Operator
This probably shows up in the WebUI as disabled, but is most likely set to `Managed` (enabled). Change the `managementState: Managed` to `managementState: Unmanaged`.

```{ .bash }
oc get insightsoperator.operator.openshift.io/cluster -o yaml
```
```{ .yaml .no-copy hl_lines="7" }
apiVersion: operator.openshift.io/v1
kind: InsightsOperator
metadata:
  ...
spec:
  logLevel: Normal
  managementState: Managed
  operatorLogLevel: Normal
```

Set it to Unmanaged
```{ .yaml .no-copy title="insights-disable.yaml" }
---
apiVersion: operator.openshift.io/v1
kind: InsightsOperator
metadata:
  name: cluster
spec:
  # Change from Managed to Unmanaged
  managementState: Unmanaged
```
```{ .bash }
# Edit from the cmdline and copy/paste contents
oc edit insightsoperator.operator.openshift.io/cluster

# Or

# Apply the yaml file if you created one
oc apply -f insights-disable.yaml
```

## Image CR and additional Container Registries

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html-single/images/index#image-configuration-classic){:target="_blank"}

The cluster has different mechanisms to control how images are pulled - you can block registries, specifically only registries, set insecure registries, etc. This is all configured in the Image CR.

You also need to set some configuration here for registries you're pulling from that are signed by custom Root CA certificates. These definitions are used for ImageStreams, the OpenShift Update Service, and a couple of other places. Not required for core cluster image pulling functionality but good to configure nonetheless.

To define Root CA certificates, you have to create a ConfigMap. This ConfigMap needs to have keys that are named for the hostname of the registry. If you're using a non-443 port for the registry, append it to the hostname with two dots to separate it, eg `registry.example.com:5000` would be `registry.example.com..5000`.

When configuring the Root CA for the registry that hosts the OpenShift Releases served by the OpenShift Update Service there is an `updateservice-registry` key that is used. This is outlined in the [OSUS Install: Configure access to the secured registry](./osus.md#configure-access-to-the-secured-registry)

```{ .yaml title="image-ca-bundle.yaml" }
# Root CA definitions for use by the config/Image CR
# Each image registry URL should have a corresponding entry in this ConfigMap
# with the registry URL as the key and the CA certificate as the value.
# If there is a port for the registry, use two dots to separate the registry hostname and the port.
# For example, if the registry URL is registry.example.com:5000, the key should be registry.example.com..5000
# The updateservice-registry entry is used for the OpenShift Update Service
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: image-ca-bundle
  namespace: openshift-config
data:
  # updateservice-registry is for the registry hosting OSUS Releases
  updateservice-registry: |
    -----BEGIN CERTIFICATE-----
    MIIH0DCCBbigAwIBAgIUV...
    -----END CERTIFICATE-----
  my-other-registry.example.com: |
    -----BEGIN CERTIFICATE-----
    ... cert text here ...
    -----END CERTIFICATE-----
  test-registry.example.com..8443: |
    -----BEGIN CERTIFICATE-----
    ... cert text here ...
    -----END CERTIFICATE-----
```
```{ .bash }
# Edit from the cmdline if the resource already exists and copy/paste contents
oc edit configmaps image-ca-bundle -n openshift-config

# Or

# Apply the yaml file if you created one
oc apply -f image-ca-bundle.yaml
```


With that ConfigMap created, you can now configure the Image CR with it and any other configuration you want

```{ .yaml title="image-config-cr.yaml" }
---
apiVersion: config.openshift.io/v1
kind: Image
metadata:
  name: cluster
spec:
  # additionalTrustedCA is a reference to a ConfigMap containing additional CAs that should be trusted during imagestream import, pod image pull, build image pull, and imageregistry pullthrough.
  # The namespace for this config map is openshift-config.
  additionalTrustedCA:
    name: image-ca-bundle
  
  # Optional configuration...

  # allowedRegistriesForImport limits the container image registries that normal users may import images from. Set this list to the registries that you trust to contain valid Docker images and that you want applications to be able to import from.
  # Users with permission to create Images or ImageStreamMappings via the API are not affected by this policy - typically only administrators or system integrations will have those permissions.
  allowedRegistriesForImport:
    - image-registry.openshift-image-registry.svc:5000
    - my-other-registry.example.com
    - test-registry.example.com:8443

  registrySources:
    # allowedRegistries are the only registries permitted for image pull and push actions. All other registries are denied. 
    # Only one of blockedRegistries or allowedRegistries may be set.
    allowedRegistries:
      - image-registry.openshift-image-registry.svc:5000
      - my-other-registry.example.com
      - test-registry.example.com:8443

    # blockedRegistries cannot be used for image pull and push actions. All other registries are permitted. 
    # Only one of BlockedRegistries or AllowedRegistries may be set.
    blockedRegistries:
      - docker.io

    # containerRuntimeSearchRegistries are registries that will be searched when pulling images that do not have fully qualified domains in their pull specs.
    # Registries will be searched in the order provided in the list.
    # Note: this search list only works with the container runtime, i.e CRI-O. Will NOT work with builds or imagestream imports.
    containerRuntimeSearchRegistries:
      - image-registry.openshift-image-registry.svc:5000
      - test-registry.example.com:8443

    # insecureRegistries are registries which do not have a valid TLS certificates or only support HTTP connections.
    insecureRegistries:
      - test-registry.example.com:8443
```

```{ .bash }
# Edit from the cmdline and copy/paste contents
oc edit image.config.openshift.io cluster

# Or

# Apply the yaml file if you created one
oc apply -f image-config-cr.yaml
```

## Creating Container Pull Secrets

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/images/managing-images#using-image-pull-secrets){:target="_blank"}

To authenticate with container registries in OpenShift Container Platform, you can create pull secrets from existing Docker or Podman authentication files. You can also create secrets by providing registry credentials directly by using the `oc create secret docker-registry` command.

1. Create a secret from an existing authentication file
    1. For Docker clients using `.docker/config.json`
    ```bash
    oc create secret generic <pull_secret_name> \
      --from-file=.dockerconfigjson=<path/to/.docker/config.json> \
      --type=kubernetes.io/dockerconfigjson
    ```
    
    1. For Podman clients using `.config/containers/auth.json`
    ```bash
    oc create secret generic <pull_secret_name> \
      --from-file=<path/to/.config/containers/auth.json> \
      --type=kubernetes.io/podmanconfigjson
    ```

1. If you do not already have a Docker credentials file for the secured registry, you can create a secret
```bash
oc create secret docker-registry <pull_secret_name> \
  --docker-server=<registry_server> \
  --docker-username=<user_name> \
  --docker-password=<password> \
  --docker-email=<email>
```

## Using a Pull Secret in a Workload

To allow workloads to pull images from private registries in OpenShift Container Platform, you can link the pull secret to a service account by entering the `oc secrets link` command or by defining it directly in your workload configuration YAML file.

1. Link the pull secret to a service account by entering the following command. Note that the name of the service account should match the name of the service account that pod uses. The default service account is `default`.
```bash
oc secrets link default <pull_secret_name> --for=pull
```

1. Verify the change by entering the following command
```bash
oc get serviceaccount default -o yaml
```
```{ . .no-copy title="Example Output" }
apiVersion: v1
imagePullSecrets:
- name: default-dockercfg-123456
- name: <pull_secret_name>
kind: ServiceAccount
metadata:
  annotations:
    openshift.io/internal-registry-pull-secret-ref: <internal_registry_pull_secret>
  creationTimestamp: "2025-03-03T20:07:52Z"
  name: default
  namespace: default
  resourceVersion: "13914"
  uid: 9f62dd88-110d-4879-9e27-1ffe269poe3
secrets:
- name: <pull_secret_name>
```

3. Optional: Instead of linking the secret to a service account, you can alternatively reference it directly in your pod or workload definition. This is useful for GitOps workflows such as ArgoCD.
```{ . .no-copy title="Example Pod Definition" }
apiVersion: v1
kind: Pod
metadata:
  name: <secure_pod_name>
spec:
  containers:
  - name: <container_name>
    image: quay.io/my-private-image
  imagePullSecrets:
  - name: <pull_secret_name>
```
```{ . .no-copy title="Example ArgoCD workflow" }
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: <example_workflow>
spec:
  entrypoint: <main_task>
  imagePullSecrets:
  - name: <pull_secret_name>
```