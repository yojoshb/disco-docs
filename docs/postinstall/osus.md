## Configuring the OpenShift Update Service

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/updating-a-cluster-in-a-disconnected-environment#updating-disconnected-cluster-osus){:target="_blank"}

[Red Hat Blog on updating clusters](https://www.redhat.com/en/blog/the-ultimate-guide-to-openshift-release-and-upgrade-process-for-cluster-administrators){:target="_blank"}

[Handy Update tool](https://access.redhat.com/labs/ocpupgradegraph/update_path/){:target="_blank"}

This is kind of a pain but should only need to be set up one time. We essentially have to tell the cluster to look at our registry for graph data and release images like it does when connected to the Internet. Perform these steps only if you mirrored graph data and the `cincinnati-operator` to your mirror registry.

The following steps outline the high-level workflow on how to update a cluster in a disconnected environment using OSUS:

1. Configure access to a secured registry.
1. Update the global cluster pull secret to access your mirror registry (if needed).
1. Install the OSUS Operator.
1. Create a service container for the OpenShift Update Service.
1. Install the OSUS application and configure your clusters to use the OpenShift Update Service in your environment.
1. Perform a supported update procedure from the documentation as you would with a connected cluster.

### Configure access to the secured registry
  [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/registry/configuring-registry-operator#images-configuration-cas_configuring-registry-operator){:target="_blank"}

  Create a configmap in the openshift-config namespace and use its name in AdditionalTrustedCA in the `image.config.openshift.io` custom resource to provide additional CAs that should be trusted when contacting external registries for images. 

  1. Grab the CA in pem format for the container registry that the graph-image is in and create a new `configmap` object in the `openshift-config` namespace that defines your registry to be used for the updateservice.
      
      - The OpenShift Update Service Operator needs the config map key name `updateservice-registry` in the registry CA cert.
      
      ```bash
      # Since the OSUS image is on the Quay Mirror Registry we need it's rootCA
      cp /opt/quay-data/quay-rootCA/rootCA.pem ca.crt

      oc create configmap image-ca-bundle --from-file=updateservice-registry=ca.crt -n openshift-config
      ```
      
    !!! info
        Here we copied the rootCA of our registry to our current directory and called it `ca.crt`. Then created a configmap called `image-ca-bundle` in the openshift-config namespace using that certificate.
      
  2. Edit the `Image` custom resource and add the configmap you just created to the additionalTrustedCA spec.
      ```bash
      oc edit image.config.openshift.io cluster
      ```
      ```yaml
      spec:
        additionalTrustedCA:
          name: image-ca-bundle
      ```
    - [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/updating-a-cluster-in-a-disconnected-environment#images-update-global-pull-secret_updating-disconnected-cluster-osus){:target="_blank"} 
    
        You can update the global pull secret for your cluster by either replacing the current pull secret or appending a new pull secret. The procedure is required when users use a separate registry to store images than the registry used during installation. If you are using the same registry that you installed from (recommended), you can skip this.

### Install the operator from the UI or CLI
  
#### UI Install
    
  [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/updating-a-cluster-in-a-disconnected-environment#update-service-install-web-console_updating-disconnected-cluster-osus){:target="_blank"}
  
  1. In the web console, click **Operators > OperatorHub**.
  2. Choose **OpenShift Update Service** from the list of available Operators, and click **Install**.
      1. Select an **Update channel**.
      2. Select a **Version**.
      3. Select **A specific namespace on the cluster** under **Installation Mode**.
      4. Select a namespace for **Installed Namespace** or accept the recommended namespace `openshift-update-service`.
      5. Select an **Update approval** strategy:
          - The **Automatic** strategy allows Operator Lifecycle Manager (OLM) to automatically update the Operator when a new version is available.
          - The **Manual** strategy requires a cluster administrator to approve the Operator update.
      6. Click **Install**.
  3. Go to **Operators > Installed Operators** and verify that the OpenShift Update Service Operator is installed.
  4. Ensure that **OpenShift Update Service** is listed in the correct namespace with a **Status** of **Succeeded**.
---
#### CLI install
  
  [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/updating-a-cluster-in-a-disconnected-environment#update-service-install-cli_updating-disconnected-cluster-osus){:target="_blank"}
  
  1. Create a namespace for the OpenShift Update Service Operator:
      - Create a `Namespace` object YAML file, for example, `update-service-namespace.yaml`, for the OpenShift Update Service Operator:
      ```yaml
      apiVersion: v1
      kind: Namespace
      metadata:
        name: openshift-update-service
        annotations:
          openshift.io/node-selector: ""
        labels:
          openshift.io/cluster-monitoring: "true"
      ```
      > Set the openshift.io/cluster-monitoring label to enable Operator-recommended cluster monitoring on this namespace.

      - Create the namespace:
      ```bash
      # Example
      oc create -f update-service-namespace.yaml
      ```

  2. Install the OpenShift Update Service Operator by creating the following objects:
      - Create an `OperatorGroup` object YAML file, for example, `update-service-operator-group.yaml`:
      ```yaml
      apiVersion: operators.coreos.com/v1
      kind: OperatorGroup
      metadata:
        name: update-service-operator-group
        namespace: openshift-update-service
      spec:
        targetNamespaces:
        - openshift-update-service
      ```

      - Create an `OperatorGroup` object:
      ```bash
      # Example
      oc -n openshift-update-service create -f update-service-operator-group.yaml
      ```
      - Create a `Subscription` object YAML file, for example, `update-service-subscription.yaml`:
        - **Example Subscription**
      ```yaml
      apiVersion: operators.coreos.com/v1alpha1
      kind: Subscription
      metadata:
        name: update-service-subscription
        namespace: openshift-update-service
      spec:
        channel: v1
        installPlanApproval: "Automatic"
        source: "redhat-operators" # Specify the correct source
        sourceNamespace: "openshift-marketplace"
        name: "cincinnati-operator"
      ```
      Specify the name of the catalog source that provides the Operator. For clusters that do not use a custom Operator Lifecycle Manager (OLM), specify `redhat-operators`. If your OpenShift Container Platform cluster is installed in a disconnected environment, specify the name of the `CatalogSource` object created when you configured Operator Lifecycle Manager (OLM).
      ```bash
      # Heres a way to see what catalog source the cluster is configured for
      $ oc get service -n openshift-marketplace
      ```
      ```{ . .no-copy title="Example Output" }
      NAME                             TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)             AGE
      redhat-operators                 ClusterIP   172.30.79.90   <none>        50051/TCP           12d
      marketplace-operator-metrics     ClusterIP   172.30.26.63   <none>        8383/TCP,8081/TCP   13d
      ```
      - Create the Subscription object:
      ```bash
      # Example
      oc -n openshift-update-service create -f update-service-subscription.yaml
      ```
      The OpenShift Update Service Operator is installed to the openshift-update-service namespace and targets the openshift-update-service namespace.

  3. Verify the Operator installation:
      ```bash
      oc -n openshift-update-service get clusterserviceversions
      ```
      ```{ . .no-copy title="Example Output" }
      NAME                             DISPLAY                    VERSION   REPLACES                         PHASE
      update-service-operator.v5.0.3   OpenShift Update Service   5.0.3     update-service-operator.v5.0.2   Succeeded
      ```

### Create an OpenShift Update Service application
  
!!! info
    oc-mirror will generate a `updateService.yaml` file for you when mirroring from disk to mirror. It will be located in the `working-dir/cluster-resources/` directory.

    The name of the service it will create is: `update-service-oc-mirror`

    Make sure to apply the service in the same namespace as the operator i.e. `openshift-update-service`
    
    ```bash
    oc -n openshift-update-service apply -f /opt/4.17-mirrordata/working-dir/cluster-resources/updateService.yaml
    ```

    You can use that service file, or create one by following the steps below.

  Here we'll deploy the service pods, pointing to graph-data to the one we mirrored to our registry, and pointing the release-images our registry mirror rather than Red Hat's CDN. 

  [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/updating-a-cluster-in-a-disconnected-environment#update-service-create-service-cli_updating-disconnected-cluster-osus){:target="_blank"}

  1. Configure the OpenShift Update Service target namespace, for example, `openshift-update-service`:
      ```bash
      NAMESPACE=openshift-update-service
      ```
      The namespace must match the `targetNamespaces` value from the operator group.
  2. Configure the name of the OpenShift Update Service application, for example, `update-service`:
      ```bash
      NAME=update-service
      ```
  3. Configure the registry and repository for the release images as configured for example, `registry.example.com:8443/ocp/openshift/release-images`:
      ```bash
      RELEASE_IMAGES=registry.example.com:8443/ocp/openshift/release-images
      ```  
  4. Set the local pullspec for the graph data image to the graph data container image for example, `registry.example.com:8443/ocp/openshift/graph-image:latest`:
      ```bash
      GRAPH_DATA_IMAGE=registry.example.com:8443/ocp/openshift/graph-image:latest
      ```
  5. Create an OpenShift Update Service application object:
      ```bash
      oc -n "${NAMESPACE}" create -f - <<EOF
      apiVersion: updateservice.operator.openshift.io/v1
      kind: UpdateService
      metadata:
        name: ${NAME}
      spec:
        replicas: 2
        releases: ${RELEASE_IMAGES}
        graphDataImage: ${GRAPH_DATA_IMAGE}
      EOF
      ```

### Configuring the Cluster Version Operator (CVO) 

  [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/updating-a-cluster-in-a-disconnected-environment#update-service-configure-cvo){:target="_blank"}
  
  After the OpenShift Update Service Operator has been installed and the OpenShift Update Service application has been created, the Cluster Version Operator (CVO) can be updated to pull graph data from the OpenShift Update Service installed in your environment.

  1. Set the OpenShift Update Service target namespace, for example, `openshift-update-service`:
      ```bash
      NAMESPACE=openshift-update-service
      ```
  2. Use the name of the OpenShift Update Service application created previously, for example, `update-service`:
      ```bash
      NAME=update-service

      # If you used the oc mirror generated updateService.yaml
      NAME=update-service-oc-mirror
      ```
  3. Obtain the policy engine route:
      ```bash
      POLICY_ENGINE_GRAPH_URI="$(oc -n "${NAMESPACE}" get -o jsonpath='{.status.policyEngineURI}/api/upgrades_info/v1/graph{"\n"}' updateservice "${NAME}")"
      ```
  4. Set the patch for the pull graph data:
      ```bash
      PATCH="{\"spec\":{\"upstream\":\"${POLICY_ENGINE_GRAPH_URI}\"}}"
      ```
  5. Patch the CVO to use the OpenShift Update Service in your environment:
      ```bash
      oc patch clusterversion version -p $PATCH --type merge
      ```

### Configure the cluster-wide proxy
  
  [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html-single/networking/#enable-cluster-wide-proxy){:target="_blank"}

  Finally, configure the cluster-wide proxy to configure the CA to trust the update server we created.

!!! warning "This may cause nodes to reboot so be prepared"

  1. Get the ingress-router CA and save it to a file
      ```bash
      oc get -n openshift-ingress-operator secret router-ca -o jsonpath="{.data.tls\.crt}" | base64 -d > ca-bundle.crt
      ```
  2. Create a configmap from that CA and store it in the openshift-config namespace
      ```bash
      oc create configmap router-bundle --from-file=ca-bundle.crt -n openshift-config
      ```
      
    !!! info
        Here we created a configmap called `router-bundle` in the openshift-config namespace using the CA cert from the ingress-router that we saved to the same directory.
  
  3. Edit the cluster proxy and add the config map you just created to the TrustedCA spec
      ```bash
      oc edit proxy cluster
      ```
      ```yaml
      spec:
        trustedCA:
          name: router-bundle
      ```
