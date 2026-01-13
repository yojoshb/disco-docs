## Mirroring images to disk
[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/disconnected_environments/about-installing-oc-mirror-v2){:target="_blank"}

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
    
1. List your output directory and verify the image set `mirror_000001.tar` file was created. The `working-dir` will contain logs and relavent info for the data mirrored to disk.
    ```{ .bash }
    ls /opt/4.17-mirrordata/
    ```
    ```{ . .no-copy title="Example Output" }
    mirror_000001.tar  working-dir
    ```

1. The working-dir will also show you the exact version of OpenShift you mirrored, if you specified the platform mirror via `stable-4.xx` in your imageset config file.
  ```{ . .no-copy title="Example" }
  ls /opt/4.17-mirrordata/working-dir/signatures/4.17.17-x86_64-sha256-2c8a2124df0a8c865a3771c49d01bfcb96cadc7f411e23870eb9f8adbe032ec1
  ```

## Transfer mirrored data to the disconnected environment.
Place these files on a disk and transfer them to your disconnected network

- **mirror_000001.tar** (image set .tar file)
- **imageset-config.yaml** (your image set config file)
