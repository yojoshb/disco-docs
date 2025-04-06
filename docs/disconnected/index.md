# Disconnected Setup

[Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/mirroring-in-disconnected-environments)

The disconnected Linux machine will need to be able to run the tools and have adequate disk space on the mirror host as well as the target registry you will be uploading to.

The general flow of goes like this: 

1. Copy the image set and associated tools off of the transfer medium to the disconnected environment.
1. Configure push/pull credentials for your target mirror registry.
1. Upload the image set to the target mirror registry.
