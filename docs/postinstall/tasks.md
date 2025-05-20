## Additional Post-Install Tasks

Many of these settings have already been applied if you deployed the cluster with the appropriate customizations but it's good to double check everything. Much of this is regurgitated information from [Kens disconnected-openshift Repo](https://github.com/kenmoini/disconnected-openshift/blob/main/post-install-config/README.md#post-installation-cluster-configuration){:target="_blank"} which is a great resource for additional diconnected install information/configs/tools.

## Cluster-wide CA Certs

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/security_and_compliance/configuring-certificates#ca-bundle-understanding_updating-ca-bundle){:target="_blank"}

Typically you'll have custom internal Root Certificate Authorities that sign TLS certs for services. If you provided the certificates during installation (your mirror registry for example), you should find them in the `user-ca-bundle` ConfigMap in the `openshift-config` Namespace under the `ca-bundle.crt` key. 

1. Verify that the contents match what you have for your Root CAs
```bash
$ oc get cm/user-ca-bundle -n openshift-config -o yaml
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
```yaml title="user-ca-bundle.yaml"
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
```bash
# Edit from the cmdline and copy/paste contents
$ oc edit configmaps user-ca-bundle -n openshift-config

# Or

# Apply the yaml file if you created one
$ oc apply -f user-ca-bundle.yaml
```

3. With the Root CA Certificates in the cluster-wide ConfigMap, you can now create other ConfigMaps with a special label that will inject all the trusted Root CA certificates into it which makes it easy to be used by applications
```yaml title="image-additional-trust-bundle.yaml"
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
```bash
# Apply the yaml file
$ oc apply -f image-additional-trust-bundle.yaml
```

## Disabling the Insights Operator
This is probably already set to be unmanaged (disabled) but check it if it's not. Look for `managementState: Unmanaged` under the `spec:` section.

```bash hl_lines="8"
$ oc get insightsoperator.operator.openshift.io/cluster -o yaml
apiVersion: operator.openshift.io/v1
kind: InsightsOperator
metadata:
  ...
spec:
  logLevel: Normal
  managementState: Unmanaged
  operatorLogLevel: Normal
```

If you need to set it to Unmanaged
```yaml title="insights-disable.yaml"
---
apiVersion: operator.openshift.io/v1
kind: InsightsOperator
metadata:
  name: cluster
spec:
  # Change from Managed to Unmanaged
  managementState: Unmanaged
```
```bash
# Edit from the cmdline and copy/paste contents
$ oc edit insightsoperator.operator.openshift.io/cluster

# Or

# Apply the yaml file if you created one
$ oc apply -f insights-disable.yaml
```

## Image CR and additional Container Registries

The cluster has different mechanisms to control how images are pulled - you can block registries, specifically only registries, set insecure registries, etc. This is all configured in the Image CR.

You also need to set some configuration here for registries you're pulling from that are signed by custom Root CA certificates. These definitions are used for ImageStreams, the OpenShift Update Service, and a couple of other places. Not required for core cluster image pulling functionality but good to configure nonetheless.

To define Root CA certificates, you have to create a ConfigMap. This ConfigMap needs to have keys that are named for the hostname of the registry. If you're using a non-443 port for the registry, append it to the hostname with two dots to separate it, eg `registry.example.com:5000` would be `registry.example.com..5000`.

When configuring the Root CA for the registry that hosts the OpenShift Releases served by the OpenShift Update Service there is an `updateservice-registry` key that is used. This is outlined in the [OSUS Install Doc: Configure access to the secured registry](./osus.md)

```yaml title="image-ca-bundle.yaml"
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
```bash
# Edit from the cmdline and copy/paste contents
$ oc edit configmaps image-ca-bundle -n openshift-config

# Or

# Apply the yaml file if you created one
$ oc apply -f image-ca-bundle.yaml
```


With that ConfigMap created, you can now configure the Image CR with it and any other configuration you want

```yaml title="image-config-cr.yaml"
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

```bash
# Edit from the cmdline and copy/paste contents
$ oc edit image.config.openshift.io cluster

# Or

# Apply the yaml file if you created one
$ oc apply -f image-config-cr.yaml
```