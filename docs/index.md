---
hide:
  #- navigation
  - toc
---
# OpenShift in a Disconnected Environment: Streamlined
This documentions purpose is for consolidating information to stand up a OpenShift v4.12 and later cluster, either HA or SNO, in a disconnected environment. This in not a one-size fits all, this is not specific to any team/org, this is rough and simple to at least put the important things to know in one centralized document. Relevant docs/articles will be linked in each section if applicable.

### Basic Prerequisites
- Online connected (low-side)
    - A Red Hat account and valid OpenShift subscription
    - RHEL 8/9 or compatible WSL machine that can access the internet (Red Hat's CDN)
    - Online mirror host disk space: 100GB+ (Dependant on what you want to install)
    - Data transfer capabilities (low-side to high-side)

- Offline disconnected (high-side) 
    - A machine that can access the network that the cluster will be installed to
    - Offline mirror host disk space: 100GB+ (Dependant on what you want to install)
    - A docker v2-2 capable registry with adequate storage space 100GB+ (If you do not have a registry in your environment, you can use the [mirror registry for Red Hat OpenShift](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html-single/disconnected_environments/index#installing-mirroring-creating-registry))
    
    !!! note
        If you want to use the Red Hat provided mirror registry, the machine must be able to run Podman. Changes to the machine may need to happen that may violate the DISA STIG.
    - DNS server
    - NTP server/source

### FIPS
Only pertains to the install being performed on the high-side.

- **OpenShift version 4.12 to 4.15**: To enable FIPS mode for your cluster, you must run the installation program from a RHEL 8 computer that is configured to operate in FIPS mode. Running RHEL 9 with FIPS mode enabled to install an OpenShift Container Platform cluster is not possible. 
    - [Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.12/html/installation_overview/installing-fips#installing-fips)

- **OpenShift version 4.16 and later**: To enable FIPS mode for your cluster, you must run the installation program from a RHEL 9 computer that is configured to operate in FIPS mode, and you must use a FIPS-capable version of the installation program. 
    - [Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/installation_overview/installing-fips#installing-fips)
