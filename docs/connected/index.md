# Connected Setup

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/mirroring-in-disconnected-environments)

The connected Linux machine will need to be able to run tools and access Quay.io and redhat.io registries.

  - The current CDN access needed is

The general flow of a disconnected OpenShift install starts with: 

1. Download the required tools from Red Hat.
1. Create an image set configuration file.
1. Mirror an image set to disk 
1. Transfer the image set and associated tools to the target environment.
