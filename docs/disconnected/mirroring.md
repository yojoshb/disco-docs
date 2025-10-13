## Mirroring images from disk to your mirror

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/mirroring-in-disconnected-environments#disk-mirror-v2_about-installing-oc-mirror-v2){:target="_blank"}

Now that the images are on the disk and you have a target registry with push/pull permissions to mirror to, we can mirror them to your registry

- Specify the image set configuration file that you brought over or created. This example assumes that it is in `/opt/4.17-mirrordata/imageset-config.yaml`. If you named your's differently, sub in your name and path of the file.
- Specify the target directory where the `mirror_000001.tar` file is. The target directory path must start with `file://`. This procedure assumes you want to upload the mirror_000001.tar **from** `/opt/4.17-mirrordata/`.
    - The target directory will also hold the `working-dir` environment. This directory contains the various necessary data to build, update, and maintain cluster resources. Keep this directory safe, and do not modify it. It will be used again for updates and additions to your cluster
- Specify the registry you will be mirroring the images to. In this example `registry.example.com:8443/` is our registry, and we will upload it to the `ocp` namespace in our registry.
- Be aware of the caching system, this will also take up considerable space on the disk depending on how many images are being uploaded to your mirror. Caching still occurs with the 'disk to mirror' workflow.
  
!!! question "Caching"
    - How does the cache work?
        - It's like a local registry, it can take up additional disk space almost as large as the .tar that gets generated
    - Where is it saved?
        - By default in `$HOME/.oc-mirror/.cache`
    - Can I control where I want the cache to be stored?
        - Yes, you can pass `--cache-dir <dir>` which will change the cache location to `<dir>/.oc-mirror/.cache`
    - During the mirroring process, is there a way to resume if something goes wrong?
        - Yes, by re-running oc mirror
    - I intentionally canceled the task and re-ran the mirroring process, but it seemed to start from the beginning.
        - It goes through the images from your ISC but it won't pull them from the tarball if they're already in the cache. You can compare the elapsed times by running a second time with the images already cached.
    - The cache takes up a lot of disk space can it be deleted?
        - Yes the cache can be removed, oc mirror will just re-pull what's needed from the tarball

---
1. You have set the umask parameter to `0022` on the operating system that uses oc-mirror.
    ```{ .bash }
    umask 0022
    ```

1. Upload your images to your mirror
  ```{ .bash }
  oc mirror -c /opt/4.17-mirrordata/imageset-config.yaml --from file:///opt/4.17-mirrordata docker://registry.example.com:8443/ocp --v2
  ```
  If your mirror registry is using a self-signed certificate and your machine doesn't trust it internally use `--dest-tls-verify=false`
  ```{ .bash }
  oc mirror --dest-tls-verify=false -c /opt/4.17-mirrordata/imageset-config.yaml --from file:///opt/4.17-mirrordata docker://registry.example.com:8443/ocp --v2
  ```
  ```{ . .no-copy title="Example Output" }
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

    - If you get an error like the one below, your registry most likely cannot write the data fast enough. You can try doing it again with less parallel operations using the `--parallel-images` flag
    ```{ . .no-copy title="Example Output" }
    [ERROR]  : [Worker] error mirroring image quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:dae0aadc59c79509779a9e904e0aeaa6d5c5e3f24eedc5c114c6bca1b15ea3b1 error: trying to reuse blob sha256:25c75c34b2e2b68ba9245d9cddeb6b8a0887371ed30744064f85241a75704d87 at destination: can't talk to a V1 container registry
    ```
    ```{ .bash }
    # Default is 8 parallel operations, so you can pull it down to a lower value
    oc mirror --dest-tls-verify=false --parallel-images 4 -c /opt/4.17-mirrordata/imageset-config.yaml --from file:///opt/4.17-mirrordata docker://registry.example.com:8443/ocp --v2
    ```

1. Verify the cluster resources were generated by oc mirror in the `working-dir/cluster-resources` directory, these resources will be applied to the cluster later once it's installed
    ```{ .bash }
    ls /opt/4.17-mirrordata/working-dir/cluster-resources/
    ```
    ```{ . .no-copy title="Example Output" }
    cc-redhat-operator-index-v4-17.yaml  cs-redhat-operator-index-v4-17.yaml  idms-oc-mirror.yaml  itms-oc-mirror.yaml  signature-configmap.json  signature-configmap.yaml  updateService.yaml
    ```