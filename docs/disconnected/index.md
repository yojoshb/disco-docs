# Disconnected Setup

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/mirroring-in-disconnected-environments){:target="_blank"}

The disconnected Linux machine will need to be able to run the tools and have adequate disk space on the mirror host as well as the target registry you will be uploading to.

!!! note
    This document goes over the installation using the builtin HAProxy load-balancer that OpenShift comes with out of the box.
    
    This is not a true load balancer as traffic will always go to the pod where Ingress VIP is attached.
    
    If you want to use an external load-balancer (encouraged for Production), refer to the [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html-single/installing_an_on-premise_cluster_with_the_agent-based_installer/index#agent-install-load-balancing-none_preparing-to-install-with-agent-based-installer){:target="_blank"}

The general flow of goes like this: 

1. Copy the image set and associated tools off of the transfer medium to the disconnected environment.
1. Configure push/pull credentials for your target mirror registry.
1. Upload the image set to the target mirror registry.
