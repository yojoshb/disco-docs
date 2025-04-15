# Connected Setup

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/disconnected_environments/mirroring-in-disconnected-environments){:target="_blank"}

The connected Linux machine will need to be able to run provided tools and access specific registries.

  - The current CDN access needed for the mirror host:
  
  [Red Hat KCS](https://access.redhat.com/solutions/4919821){:target="_blank"}, [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/installation_configuration/configuring-firewall#configuring-firewall_configuring-firewall){:target="_blank"}
  
  |URL                    |Port|Function|
  |-                      |-   |-       |
  |`registry.redhat.io`   |443 |Provides core container images |
  |`*.quay.io`            |443 |Provides core container images |
  |`sso.redhat.com`       |443 |https://cloud.redhat.com/openshift site uses authentication from `sso.redhat.com`. |
  |`mirror.openshift.com` |443 |Required to access mirrored installation content and images. |

The general flow of a disconnected OpenShift install starts with: 

1. Download the required tools from Red Hat.
1. Create an image set configuration file.
1. Mirror an image set to disk 
1. Transfer the image set and associated tools to the target environment.
