## Mirroring images to disk
[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/mirroring-in-disconnected-environments#mirror-to-disk-v2_about-installing-oc-mirror-v2){:target="_blank"}

Now that the images are defined, we can mirror them to disk. Repeat this process for updates or additions to your cluster.

- Pass in the image set configuration file that was created. This procedure assumes that it is named `imageset-config.yaml`. If you named your's differently, sub in your name of the file.
- Specify the target directory where you want to output the image set tar file. The target directory path must start with `file://`. This procedure assumes you want to store the image set in `/opt/4.17-mirrordata`. Store it anywhere that has available disk space. Can even be the mounted drive you're going to use to transfer the data to the high-side.
  - The target directory will also hold the `working-dir` environment. This directory contains the various necessary data to build, update, and maintain cluster resources. Keep this directory safe, and do not modify it. It will be used again for updates and additions to your cluster
- Be aware of the caching system, this will also take up considerable space on the disk depending on how many images you want to mirror
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
        - It goes through the images from your ISC but it won't pull them if they're already in the cache. You can compare the elapsed times by running a second time with the images already cached.
    - The cache takes up a lot of disk space can it be deleted?
        - Yes the cache can be removed, oc mirror will just re-download what's needed

1. You have set the umask parameter to `0022` on the operating system that uses oc-mirror.

    ```{ .bash }
    umask 0022
    ```

1. Perform a dry-run of the mirror to disk process to verify your imageset-config is valid and the tools can gather the data
    
    !!! info
        Ignore the warning for `images necessary for mirroring are not available in the cache.` This is just letting you know nothing has actually been downloaded to the cache yet as this is a dry-run, except the graph-data image...

        Currently the `--dry-run` process still downloads the graph-image to cache
    
    ```{ .bash }
    oc mirror -c imageset-config.yaml file:///opt/4.17-mirrordata --dry-run --v2
    ```
    ```{ . .no-copy title="Example Output" }
    [INFO]   : 👋 Hello, welcome to oc-mirror
    [INFO]   : ⚙️  setting up the environment for you...
    [INFO]   : 🔀 workflow mode: mirrorToDisk
    [INFO]   : 🕵  going to discover the necessary images...
    [INFO]   : 🔍 collecting release images...
    [INFO]   : 🔍 collecting operator images...
    ✓   (2m53s) Collecting catalog registry.redhat.io/redhat/redhat-operator-index:v4.17
    [INFO]   : 🔍 collecting additional images...
    [INFO]   : 🔍 collecting helm images...
    [WARN]   : ⚠️  193/194 images necessary for mirroring are not available in the cache.
    [WARN]   : List of missing images in : /opt/4.17-mirrordata/working-dir/dry-run/missing.txt.
    please re-run the mirror to disk process
    [INFO]   : 📄 list of all images for mirroring in : /opt/4.17-mirrordata/working-dir/dry-run/mapping.txt
    [INFO]   : mirror time     : 24.392878858s
    [INFO]   : 👋 Goodbye, thank you for using oc-mirror
    ```

1. Perform the mirror to disk process    
    ```{ .bash }
    oc mirror -c imageset-config.yaml file:///opt/4.17-mirrordata --v2
    ```
    ```{ . .no-copy title="Example Output" }
    ...
    [INFO]   : === Results ===
    [INFO]   :  ✓  185 / 185 release images mirrored successfully
    [INFO]   :  ✓  8 / 8 operator images mirrored successfully
    [INFO]   :  ✓  1 / 1 additional images mirrored successfully
    [INFO]   : 📦 Preparing the tarball archive...
    [INFO]   : mirror time     : 13m31.071692892s
    [INFO]   : 👋 Goodbye, thank you for using oc-mirror
    ```
    
1. List your output directory and verify the image set `mirror_000001.tar` file was created. The `working-dir` will contain logs and relavent info for the data mirrorred to disk.
    ```{ .bash }
    ls /opt/4.17-mirrordata/
    ```
    ```{ . .no-copy title="Example Output" }
    mirror_000001.tar  working-dir
    ```
  
### Extract the openshift-install binary from the release-images mirrored
This binary will be used to create the ISO that you will boot on your hardware to install the cluster. This binary has to match the exact version of OpenShift release images that you have mirrored. To extract the openshift-install that's built for your mirrored images version on the connected network:

!!! note
    If you used the `rhel-oc-tools.sh` script and chose to extract the binary you do not need to do this.

1. Construct the correct URL to download the payload for your release images. Follow one of these steps
    
    1. Using oc-mirror v2 directory structure, get the hash from the images we mirrored to disk
    ```{ .bash .no-copy }
    ls /opt/4.17-mirrordata/working-dir/signatures/4.17.70-x86_64-sha256-d9c985464c0315160971b3e79f5fbec628d403a572f7a6d893c04627c066c0bb | awk -F'sha256-' '{print $2}'
    {==40a0dce2a37e3278adc2fd64f63bca67df217b7dd8f68575241b66fdae1f04a3==}

    # Store this in a variable to use it to curate the URL to extract the installer from without copying and pasting 
    export HASH=$(ls /opt/4.17-mirrordata/working-dir/signatures/4.17.70-x86_64-sha256-40a0dce2a37e3278adc2fd64f63bca67df217b7dd8f68575241b66fdae1f04a3 | awk -F'sha256-' '{print $2}')
    ```
    2. Or, construct the entire URL based on the version specified in the imageset config file. Read the warning below to understand the potential issue you could run into with this method.
    ```{ .bash .no-copy }
    export VERSION=stable-4.17
    export RELEASE_ARCH=amd64
    export RELEASE_IMAGE=$(curl -s https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/$VERSION/release.txt | grep 'Pull From: quay.io' | awk -F ' ' '{print $3}')
    echo $RELEASE_IMAGE
    quay.io/openshift-release-dev/ocp-release@sha256:{==40a0dce2a37e3278adc2fd64f63bca67df217b7dd8f68575241b66fdae1f04a3==}
    ```
    !!! warning
        Be aware that this could end up downloading a different version of installer if you mirrored the images at a earlier time.

        Example: You mirrored the `stable-4.17` the images a week ago, at that time the stable channel was set to version `4.17.70`. Now you go to extract the binary a week later, but the stable-4.17 branch was updated from `4.17.70` to `4.17.71`. The binary would be downloaded for the newer stable branch `4.17.71` and be the incorrect version with the images you mirrored prior. This would cause the installer to fail, as it would be looking for the newer release payload on the mirror registry.

2. Use `oc adm` to extract the openshift-install binary that is purpose built for the version of images you mirrored. This command will extract the `openshift-install` or `openshift-install-fips` binary to your current directory. You can pass in the `--dir='<path>'` to extract the binary to a specific location on your filesystem. 
    ```{ .bash .no-copy }
    oc adm release extract --command=openshift-install quay.io/openshift-release-dev/ocp-release@sha256:$HASH

    # If you are installing OpenShift 4.16 or later and requiring FIPS
    oc adm release extract --command=openshift-install-fips quay.io/openshift-release-dev/ocp-release@sha256:$HASH
    ```
    
    If you constructed the entire URL
    ```{ .bash .no-copy }
    oc adm release extract --command=openshift-install $RELEASE_IMAGE
    
    # If you are installing OpenShift 4.16 or later and requiring FIPS
    oc adm release extract --command=openshift-install-fips $RELEASE_IMAGE
    ```

3. Now check the SHA256 hash against the release signatures we looked at before by running `openshift-install version` using the binary you just downloaded.
    ```{ .bash }
    ./openshift-install version
    ```
    ```{ . .no-copy title="Example Output" }
    ./openshift-install 4.12.70
    built from commit 798aeaaf61fbc22669b6bad2edc058ea6949d733
    release image quay.io/openshift-release-dev/ocp-release@sha256:{==40a0dce2a37e3278adc2fd64f63bca67df217b7dd8f68575241b66fdae1f04a3==}
    release architecture amd64
    ```

If the SHA256 values match each other (highlighted values), then you have extracted the correct `openshift-install` binary that can build your cluster ISO with the release images you mirrored. If the hashes do not match, you will need to either go find the correct `openshift-install` binary version for your images, or mirror the images again to the correct version of the install binary.

## Transfer data and tools to the disconnected environment.
Place these files on a disk and transfer them to your disconnected network

- **mirror_000001.tar** (image set .tar file)
- **imageset-config.yaml** (your image set config file)
- **oc**
- **oc-mirror**
- **butane**
- **mirror-registry** (if using)
- **openshift-install** or **openshift-install-fips**

---