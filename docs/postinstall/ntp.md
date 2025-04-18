## Configuring a time source for the disconnected cluster

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html-single/machine_configuration/index#machine-config-index){:target="_blank"}

We need to apply a custom Network Time Protocol (NTP) configuration to the nodes, because by default, internet connectivity is assumed in OpenShift Container Platform and `chronyd` is configured to use the `*.rhel.pool.ntp.org` servers.

<div class="annotate" markdown>

1. Create a Butane config including the contents of the `chrony.conf` file. For example, to configure chrony on master nodes, create a `99-master-chrony.bu` file.

    !!! note
        The Butane version you specify in the config file should match the OpenShift Container Platform version and always ends in `0`. For example, `4.17.0`.

```yaml
variant: openshift
version: 4.17.0
metadata:
  name: 99-master-chrony # (1)! On control plane nodes, substitute master for worker in both of these locations
  labels:
    machineconfiguration.openshift.io/role: master # (2)! On control plane nodes, substitute master for worker in both of these locations
storage:
  files:
  - path: /etc/chrony.conf
    mode: 0644 # (3)! Specify an octal value mode for the mode field in the machine config file
    overwrite: true
    contents:
      inline: | # (4)! Specify any valid, reachable time source. `172.16.10.123` is an example time server
        pool 172.16.10.123 iburst
        driftfile /var/lib/chrony/drift
        makestep 1.0 3
        rtcsync
        logdir /var/log/chrony
```
<ol start=2>
2. Use Butane to generate a <code>MachineConfig</code> object file, <code>99-master-chrony.yaml</code>, containing the configuration to be delivered to the nodes

```bash
$ butane 99-master-chrony.bu -o 99-master-chrony.yaml
```
</ol>

<ol start=3>
3. Apply the configurations in one of two ways:

<ul><li>
If the cluster is not running yet, after you generate manifest files, add the <code>MachineConfig</code> object file to the <code>installation_directory/openshift</code> directory, and then continue to create the cluster.
</ul></li>

<ul><li>
If the cluster is already running, apply the file
</ul></li>

```bash
$ oc apply -f ./99-master-chrony.yaml
```

</ol>

</div>
1. On worker nodes, change `master` to `worker`
2. On worker nodes, change `master` to `worker`
3. Specify an octal value mode for the `mode` field in the machine config file. After creating the file and applying the changes, the `mode` is converted to a decimal value. You can check the YAML file with the command `oc get mc <mc-name> -o yaml`
4. Specify any valid, reachable time source. `172.16.10.123` is an example time server
