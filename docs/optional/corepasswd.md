## Setting a password for the `core` user

By default, Red Hat Enterprise Linux CoreOS (RHCOS) creates a user named `core` on the nodes in your cluster. You can use the `core` user to access the node through a cloud provider serial console or a bare metal baseboard controller manager (BMC). 

This can be helpful, for example, if a node is down and you cannot access that node by using SSH or the `oc debug node` command. However, by default, there is no password for this user, so you cannot log in without creating one. You can create a password for the `core` user by using a machine config.

## OpenShift 4.7 to 4.12 Procedure
[Red Hat KCS Article](https://access.redhat.com/solutions/7010657){:target="_blank"}

1. Create a base64-encoded string in the format `username:password`, with the username as `core` and the password being hashed with SHA512 (`openssl passwd -6`) in order to avoid storing cleartext passwords. Replace `MYPASSWORD` in the command below with the password of your choice:

    ```{ .bash }
    MYBASE64STRING=$(echo core:$(printf "MYPASSWORD" | openssl passwd -6 --stdin) | base64 -w0)
    ```

2. Using the template below as an example, create a `MachineConfig` object that accomplishes two tasks:

    1. Writes the base64-encoded string generated above on the desired nodes' filesystem as the file `/etc/core.passwd`

    1. Sets up a new systemd unit on the desired nodes to run the `chpasswd` command during the boot process using the file written above as input (The `-e` flag is used to tell `chpasswd` to expect an encrypted/hashed password).

    ```{ .bash }
    cat << EOF > 99-set-core-passwd.yaml
    apiVersion: machineconfiguration.openshift.io/v1
    kind: MachineConfig
    metadata:
      labels:
        machineconfiguration.openshift.io/role: worker
      name: 99-worker-set-core-passwd
    spec:
      config:
        ignition:
          version: 3.2.0
        storage:
          files:
          - contents:
              source: data:text/plain;charset=utf-8;base64,$MYBASE64STRING
            mode: 420
            overwrite: true
            path: /etc/core.passwd
        systemd:
          units:
          - name: set-core-passwd.service
            enabled: true
            contents: |
              [Unit]
              Description=Set 'core' user password for out-of-band login
              [Service]
              Type=oneshot
              ExecStart=/bin/sh -c 'chpasswd -e < /etc/core.passwd'
              [Install]
              WantedBy=multi-user.target
    EOF
    ```
    ```{ .bash }
    oc create -f 99-set-core-passwd.yaml
    ```

3. As the `MachineConfig` is applied, the file containing the hashed password will be created and a new systemd unit will be configured to run the `chpasswd` command on the nodes' next boot process, setting a password for the `core` user and thus allowing terminal login via virtual console.
    
    !!! note
        Be aware that SSH password-based login would not be possible still as it is **disabled** by default on RHCOS `sshd` configuration, allowing only key-based authentication. Also, these steps could be taken before the issue arises, as a safeguard.

## OpenShift 4.13 and up Procedure
[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/machine_configuration/machine-configs-configure#core-user-password_machine-configs-configure){:target="_blank"}

You can create a password for the `core` user by using a machine config. The Machine Config Operator (MCO) assigns the password and injects the password into the `/etc/shadow` file, allowing you to log in with the `core` user. The MCO does not examine the password hash. As such, the MCO cannot report if there is a problem with the password.

!!! note
    The password works only through a cloud provider serial console or a BMC. It does not work with SSH.

    If you have a machine config that includes an `/etc/shadow` file or a systemd unit that sets a password, it takes precedence over the password hash.

!!! info "You can change the password, if needed, by editing the machine config you used to create the password. Also, you can remove the password by deleting the machine config. Deleting the machine config does not remove the user account."

1. Using a tool that is supported by your operating system, create a hashed password. For example, create a hashed password using `mkpasswd` by running the following command:

    ```{ .bash }
    mkpasswd -m SHA-512 testpass
    ```
    ```{ . .no-copy title="Example Output" }
    $6$CBZwA6s6AVFOtiZe$aUKDWpthhJEyR3nnhM02NM1sKCpHn9XN.NPrJNQ3HYewioaorpwL3mKGLxvW0AOb4pJxqoqP4nFX77y0p00.8.
    ```
2. Create a machine config file that contains the core username and the hashed password:

    ```{ .yaml }
    apiVersion: machineconfiguration.openshift.io/v1
    kind: MachineConfig
    metadata:
      labels:
        machineconfiguration.openshift.io/role: worker
      name: set-core-user-password
    spec:
      config:
        ignition:
          version: 3.2.0
        passwd:
          users:
          - name: core
            passwordHash: <password>
    ```
    > - The user name must be `core`.
    > - `<password>` is the hashed password to use with the core account.

3. Create the machine config by running the following command
    ```{ .bash }
    oc create -f <file-name>.yaml
    ```

    The nodes do not reboot and should become available in a few moments. You can use the `oc get mcp` to watch for the machine config pools to be updated
    ```{ . .no-copy title="Example Output" }
    NAME     CONFIG                                             UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
    master   rendered-master-d686a3ffc8fdec47280afec446fce8dd   True      False      False      3              3                   3                     0                      64m
    worker   rendered-worker-4605605a5b1f9de1d061e9d350f251e5   False     True       False      3              0                   0                     0                      64m
    ```