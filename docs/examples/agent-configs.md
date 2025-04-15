## Examples of agent-config.yaml files

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/installing_an_on-premise_cluster_with_the_agent-based_installer/preparing-to-install-with-agent-based-installer#agent-host-config_preparing-to-install-with-agent-based-installer){:target="_blank"}

Various examples of common agent-configs. Sub in your data as appropriate.

### Bonds/Link Aggregation

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: cluster
rendezvousIP: 172.16.10.10
hosts:
  - hostname: master1.cluster.example.com
    role: master
    interfaces:
     - name: eno1
       macAddress: 00:ef:44:21:e6:a1
     - name: eno2
       macAddress: 00:ef:44:21:e6:a2
    networkConfig:
      interfaces:
        - name: bond0
          description: Access mode bond using ports eno1 and eno2
          type: bond
          state: up
          ipv4:
            enabled: true
            address:
              - ip: 172.16.10.10
                prefix-length: 24
            dhcp: false
          link-aggregation:
            mode: active-backup  # mode=1 active-backup, mode=2 balance-xor or mode=4 802.3ad
            options:
              miimon: '150'
            port:
            - eno1
            - eno2
      dns-resolver:
        config:
          server:
            - 172.16.10.1
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 172.16.10.254
            next-hop-interface: bond0
            table-id: 254
```

### Root Device Hints
The `rootDeviceHints` parameter enables the installer to provision the Red Hat Enterprise Linux CoreOS (RHCOS) image to a particular device. The installer examines the devices in the order it discovers them, and compares the discovered values with the hint values. The installer uses the first discovered device that matches the hint value. The configuration can combine multiple hints, but a device must match all hints for the installer to select it.

!!! info
    By default, `/dev/sda` path is used when no hints are specified. Furthermore, Linux does not guarantee the block device names to be consistent across reboots.

|Subfield|Description|
|-       |-          |
|`deviceName`|A string containing a Linux device name such as `/dev/vda` or `/dev/disk/by-path/`. It is recommended to use the `/dev/disk/by-path/<device_path>` link to the storage location. The hint must match the actual value exactly.|
|`hctl`|A string containing a SCSI bus address like `0:0:0:0`. The hint must match the actual value exactly.|
|`model`|A string containing a vendor-specific device identifier. The hint can be a substring of the actual value.|
|`vendor`|A string containing the name of the vendor or manufacturer of the device. The hint can be a sub-string of the actual value.|
|`serialNumber`|A string containing the device serial number. The hint must match the actual value exactly.|
|`minSizeGigabytes`|An integer representing the minimum size of the device in gigabytes.|
|`wwn`|A string containing the unique storage identifier. The hint must match the actual value exactly. If you use the `udevadm` command to retrieve the `wwn` value, and the command outputs a value for `ID_WWN_WITH_EXTENSION`, then you must use this value to specify the `wwn` subfield.|
|`rotational`|A boolean indicating whether the device must be a rotating disk (true) or not (false). Examples of non-rotational devices include SSD and NVMe storage.|


```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: cluster
rendezvousIP: 172.16.10.10
hosts:
  - hostname: master1.cluster.example.com
    role: master
    rootDeviceHints:
      deviceName: "/dev/sda"
    interfaces:
     - name: eno1
       macAddress: 00:ef:44:21:e6:a1
    networkConfig:
        interfaces:
          - name: enp6s18
            type: ethernet
            state: up
            mac-address: BC:24:11:EE:DD:C1
            ipv4:
              enabled: true
              address:
                - ip: 172.16.1.10
                  prefix-length: 24
              dhcp: false
        dns-resolver:
          config:
            server:
              - 172.16.1.254
        routes:
          config:
            - destination: 0.0.0.0/0
              next-hop-address: 172.16.1.254
              next-hop-interface: enp6s18
              table-id: 254
```

### DHCP
If you want to utilize DHCP, the config is very simple and you can leave out the `networkConfig` enitirely. Make sure to at least create a static reservation for the `rendezvousIP` and master nodes if you want them to be on specific machines.

```yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: cluster
rendezvousIP: 172.16.10.10
```