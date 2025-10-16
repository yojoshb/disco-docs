## Examples of agent-config.yaml files

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/installing_an_on-premise_cluster_with_the_agent-based_installer/preparing-to-install-with-agent-based-installer#agent-host-config_preparing-to-install-with-agent-based-installer){:target="_blank"}

[Red Hat Docs: Agent Configuration Parameters](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/installing_an_on-premise_cluster_with_the_agent-based_installer/installation-config-parameters-agent#agent-configuration-parameters_installation-config-parameters-agent){:target="_blank"}

[Bill's awesome collection of agent installation examples](https://github.com/bstrauss84/openshift-install-configs/tree/main/installation-configs/baremetal/agent)

Various examples of common agent-configs. Sub in your data as appropriate.

!!! important
    For each host you configure, you must provide the MAC address of an interface on the host, the name of the interface can be whatever you want as long as you know the MAC. 
    
    You can configure additional interfaces on your hosts after the cluster is installed by utilizing the `NMState Operator`.

### Bonds/Link Aggregation

```{ .yaml .copy }
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: cluster
rendezvousIP: 172.16.10.10
additionalNTPSources:
- ntp.example.com
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
        mode: 802.3ad  # mode=1 active-backup, mode=2 balance-xor or mode=4 802.3ad
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

### VLANs & Bonds/Link Aggregation

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/installing_an_on-premise_cluster_with_the_agent-based_installer/preparing-to-install-with-agent-based-installer#agent-install-sample-config-bonds-vlans_preparing-to-install-with-agent-based-installer)

```{ .yaml .copy }
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: cluster
rendezvousIP: 172.16.10.10
additionalNTPSources:
- ntp.example.com
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
    - name: eno1
      type: ethernet
      state: up
    - name: eno2
      type: ethernet
      state: up
    
    - name: bond0
      description: Trunk mode bond using ports eno1 and eno2
      type: bond
      state: up
      ipv4:
        enabled: false
      ipv6:
        enabled: false
      link-aggregation:
        mode: 802.3ad  # mode=1 active-backup, mode=2 balance-xor or mode=4 802.3ad
        options:
          miimon: '150'
        port:
        - eno1
        - eno2
    
    - name: bond0.100  # Example VLAN 100 on the 'main' network subnet
      type: vlan
      state: up
      vlan:
        base-iface: bond0
        id: 100
      ipv4:
        enabled: true
        address:
        - ip: 172.16.10.10
          prefix-length: 24
        dhcp: false
      ipv6:
        enabled: false
    
    - name: bond0.500  # Example VLAN 500 on different subnet
      type: vlan
      state: up
      vlan:
        base-iface: bond0
        id: 500
      ipv4:
        enabled: true
        address:
        - ip: 172.16.50.10
          prefix-length: 24
        dhcp: false
      ipv6:
        enabled: false
    
    dns-resolver:
      config:
        server:
        - 172.16.10.1
    routes:
      config:
      - destination: 0.0.0.0/0
        next-hop-address: 172.16.10.254
        next-hop-interface: bond0.100
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


```{ .yaml .copy }
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: cluster
rendezvousIP: 172.16.10.10
additionalNTPSources:
- ntp.example.com
hosts:
- hostname: master1.cluster.example.com
  role: master
  rootDeviceHints:
    deviceName: "/dev/disk/by-path/pci-0000:01:00.0-nvme-1"
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
If you want to utilize DHCP, the config is very simple and you can leave out the `networkConfig` enitirely. It's a good idea to at least create a static reservation for the `rendezvousIP` and master nodes if you want them to be on specific machines. The `rendezvousIP` must be a master node. You can source NTP directly from DHCP if your DHCP server has this option

```{ .yaml .copy }
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: cluster
rendezvousIP: 172.16.10.10

# You can omit this section below entirely if you wanna let DHCP just assign addressing at random
hosts:
- hostname: master1.cluster.example.com
  role: master
  interfaces:
  - name: enp6s18
    macAddress: BC:24:11:EE:DD:C1

- hostname: master2.cluster.example.com
  role: master
  interfaces:
  - name: enp6s18
    macAddress: BC:24:11:EE:DD:C2

- hostname: master3.cluster.example.com
  role: master
  interfaces:
  - name: enp6s18
    macAddress: BC:24:11:EE:DD:C3
```

(Opinionated): It may be better represented to still explicitly define the interfaces like so

```{ .yaml .copy }
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: cluster
rendezvousIP: 172.16.10.10

hosts:
- hostname: master1.cluster.example.com
  role: master
  interfaces:
  - name: enp6s18
    macAddress: BC:24:11:EE:DD:C1
  networkConfig:
    interfaces:
    - name: enp6s18
      type: ethernet
      state: up
      ipv4:
        enabled: true
        dhcp: true
      ipv6:
        enabled: false

- hostname: master2.cluster.example.com
  role: master
  interfaces:
    - name: enp6s18
      macAddress: BC:24:11:EE:DD:C2
    networkConfig:
      interfaces:
      - name: enp6s18
        type: ethernet
        state: up
        ipv4:
          enabled: true
          dhcp: true
        ipv6:
          enabled: false

- hostname: master3.cluster.example.com
  role: master
  interfaces:
  - name: enp6s18
    macAddress: BC:24:11:EE:DD:C3
  networkConfig:
    interfaces:
    - name: enp6s18
      type: ethernet
      state: up
      ipv4:
        enabled: true
        dhcp: true
      ipv6:
        enabled: false
```