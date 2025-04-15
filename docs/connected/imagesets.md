## Creating ImageSets for mirroring

1. Let's browse the catalog to determine what we want to download using `oc mirror`
    
    !!! tip 
        Some of these commands take time, and by default they print to stdout. You can send the outputs to a file e.g. '`oc mirror list operators > $(date +%F)-openshift-operators.txt`' or view the stdout in `.oc-mirror.log`. 
        
        The `.oc-mirror.log` file gets generated in the current directory you are at when you run oc mirror commands.

    - Using `oc mirror list releases` to list platform releases and versions
      
      ```bash
      # Output OpenShift release versions
      $ oc mirror list releases
  
      # Output all OpenShift release channels list for a release
      $ oc mirror list releases --version=4.17
  
      # List all OpenShift versions in a specified channel
      $ oc mirror list releases --channel=stable-4.17
  
      # List all OpenShift channels for a specific version
      $ oc mirror list releases --channels --version=4.17
  
      # List OpenShift channels for a specific version and one or more release architecture. 
      # Valid architectures: amd64 (default), arm64, ppc64le, s390x, multi.
       $ oc mirror list releases --channels --version=4.17 --filter-by-archs amd64,arm64,ppc64le,s390x,multi
      ```
    
    - Using `oc mirror list operators` to list available operator catalog content and versions
  
      ```bash
      # List available operator catalog release versions
      oc mirror list operators
  
      # Output default operator catalogs for OpenShift release 4.17
      oc mirror list operators --catalogs --version=4.17
  
      # List all operator packages in a catalog
      oc mirror list operators --catalog=catalog-name
  
      # List all channels in an operator package
      oc mirror list operators --catalog=catalog-name --package=package-name
  
      # List all available versions for a specified operator in a channel
      oc mirror list operators --catalog=catalog-name --package=operator-name --channel=channel-name
      ```

2. Initialize a image set template, it will take a minute or so. The template will default to latest OpenShift version content so we will modify it further to get what we want. Comments have been added to describe what these values mean. 
  
    [Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html-single/disconnected_environments/index#oc-mirror-creating-image-set-config_installing-mirroring-disconnected){:target="_blank"}
 
    - You can initialize a imageset-config using `oc mirror init > imageset-config.yaml`
      
    !!! info 
        As of this date `oc mirror init` generates a oc-mirror *v1* formatted ics file (ImageSetConfiguration). We will be using oc-mirror *v2* formatted ics moving forward for future proof sake.


3. Edit this file to define what you want to mirror. You can add comments to this file if you would like as the file can become quite busy. You can name the file anything you want as long as the yaml formatting is correct e.g. `4.17-imageset-config.yaml`. 

    Be aware of yaml formatting, **line indentation matters**
    
      - [Red Hat Doc examples](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html-single/disconnected_environments/index#oc-mirror-image-set-examples_installing-mirroring-disconnected){:target="_blank"}
      - The example below is for OpenShift 4.17 stable, with the `lvms-operator` to use node attached disks for persistent storage and the `cincinnati-operator` to make cluster updating easier using OSUS consuming graph data pulled from Red Hat.
      
    !!! note "oc-mirror v2 changes"
        
        `apiVersion`: changes from *v1alpha2* to *v2alpha1*
        
        `storageConfig`: no longer needed as it's using a caching system rather than a metadata storage directory  

    ```yaml title="Example: imageset-config.yaml"
    kind: ImageSetConfiguration
    apiVersion: mirror.openshift.io/v2alpha1
    
    mirror:
      platform:
        channels:
        - name: stable-4.17 # (1)!
          type: ocp
        graph: true # (2)! 

      operators:
      - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.17 # (3)!
        packages:
        - name: lvms-operator # (4)!
          defaultChannel: stable-4.17 # (5)!
          channels:
          - name: stable-4.17 # (6)!
        - name: cincinnati-operator # (7)!
  
      additionalImages: # (8)!
      - name: registry.redhat.io/ubi8/ubi:latest
      - name: registry.redhat.io/openshift4/ose-must-gather:latest
      
      helm: {} # (9)!
    ```

    1. Defines that we want to download: OCP version 4.17 stable branch
    1. Graph data needed for the cincinnati operator
    1. Operator catalog we want to download from
    1. Operator that we want to download
    1. Some operators will need a defaultChannel specified. oc-mirror will tell you if it's required when attempting to mirror the data
    1. Version/Channel for said operators
    1. Only has one channel so just take the latest version
    1. Any additional images to bring with us, RHEL UBI's are always nice to have for testing, ose-must-gather is for gathering extra logs in the event a must gather is used for support or general debugging
    1. Any additional helm charts, these are non-cataloged application bundles more or less. This example we aren't specifying anything so it's blank