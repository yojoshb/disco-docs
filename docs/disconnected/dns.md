## Create DNS records

[Red Hat Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/installing_on_bare_metal/installing-restricted-networks-bare-metal#installation-dns-user-infra_installing-restricted-networks-bare-metal){:target="_blank"}

These records are mandatory for the cluster to function. Technically the cluster can function without an external DNS source, but it will be much harder to use and access the cluster and recourses it provides/hosts and each node will need a curated `/etc/hosts` file provisioned.

- The following DNS records are required for a user-provisioned OpenShift Container Platform cluster and they must be in place before installation. In each record, `<cluster_name>` is the cluster name and `<base_domain>` is the base domain that you specify in the install-config.yaml file. A complete DNS record takes the form: `<component>.<cluster_name>.<base_domain>.`

  |Component      |Record                            |Type                                   |Description        |
  |-              |-                                 |-                                      |-                  |
  |Kubernetes API |api.<cluster_name\>.<base_domain\>. |DNS A/AAAA or CNAME and DNS PTR record |To identify the API load balancer. These records must be resolvable by both clients external to the cluster and from all the nodes within the cluster.|
  |Kubernetes API |api-int.<cluster_name\>.<base_domain\>. |DNS A/AAAA or CNAME and DNS PTR record |To internally identify the API load balancer. These records must be resolvable from all the nodes within the cluster.|
  |Routes |*.apps.<cluster_name\>.<base_domain\>. |wildcard DNS A/AAAA or CNAME record |Refers to the application ingress load balancer. The application ingress load balancer targets the machines that run the Ingress Controller pods. The Ingress Controller pods run on the compute machines by default. These records must be resolvable by both clients external to the cluster and from all the nodes within the cluster.|
  |Control plane machines |<control_plane\><n\>.<cluster_name\>.<base_domain\>. |DNS A/AAAA or CNAME and DNS PTR record |To identify each machine for the control plane nodes. These records must be resolvable by the nodes within the cluster.|
  |Compute machines |<compute\><n\>.<cluster_name\>.<base_domain\>. |DNS A/AAAA or CNAME and DNS PTR record |To identify each machine for the worker nodes. These records must be resolvable by the nodes within the cluster.|

- Here's and example for a 3 node high-avalablity compact cluster. The cluster name is `cluster` and the base domain is `example.com`. The `registry.example.com` record is displayed here as well, showing that it's necessary to be DNS resolvable by your OpenShift nodes on your network. The registry does not have to belong to the cluster sub-domain. 
  
    !!! note
        This example is using the builtin HAProxy load balancer for the Kubernetes API that OpenShift comes with out of the box.
        This is not a true load balancer as traffic will always go to the pod where Ingress VIP is attached but you can make it a different IP as you would with a external load-balancer.

  |Component        |Record                       |IP Address   |Type               |
  |-                |-                            |-            |-                  |
  |Kubernetes API   |api.cluster.example.com      |172.16.1.5   |DNS A/PTR record   |
  |Kubernetes API   |api-int.cluster.example.com  |172.16.1.4   |DNS A/PTR record   |
  |Routes           |*.apps.cluster.example.com   |172.16.1.5   |DNS wildcard record|
  |Master node 1    |m1.cluster.example.com       |172.16.1.10  |DNS A/PTR record   |
  |Master node 2    |m2.cluster.example.com       |172.16.1.11  |DNS A/PTR record   |
  |Master node 3    |m3.cluster.example.com       |172.16.1.12  |DNS A/PTR record   |
  |Registry         |registry.example.com         |172.16.1.1   |DNS A/PTR record   |

- For Single Node OpenShift (SNO) the Kubernetes API and Routes all must point to the SNO if you aren't using a external load-balancer. The cluster name is `sno` and the base domain is `example.com`.

  |Component        |Record                  |IP Address   |Type               |
  |-                |-                       |-            |-                  |
  |Kubernetes API   |api.sno.example.com     |172.16.1.10  |DNS A/PTR record   |
  |Kubernetes API   |api-int.sno.example.com |172.16.1.10  |DNS A/PTR record   |
  |Routes           |*.apps.sno.example.com  |172.16.1.10  |DNS wildcard record|
  |Single node 1    |n1.sno.example.com      |172.16.1.10  |DNS A/PTR record   |
  |Registry         |registry.example.com    |172.16.1.1   |DNS A/PTR record   |

- Check forward, reverse, and wildcard DNS resolution
    - Forward lookup for the record `api.cluster.example.com` answered by the DNS server at `172.16.1.254`
    ```bash hl_lines="15 18"
    $ dig api.cluster.example.com
  
    ; <<>> DiG 9.16.23-RH <<>> api.cluster.example.com
    ;; global options: +cmd
    ;; Got answer:
    ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 13520
    ;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
    
    ;; OPT PSEUDOSECTION:
    ; EDNS: version: 0, flags:; udp: 1232
    ;; QUESTION SECTION:
    ;api.cluster.example.com.           IN      A
    
    ;; ANSWER SECTION:
    api.cluster.example.com.    3600    IN      A       172.16.1.5
    
    ;; Query time: 0 msec
    ;; SERVER: 172.16.1.254#53(172.16.1.254)
    ;; WHEN: Mon Mar 24 16:11:11 CDT 2025
    ;; MSG SIZE  rcvd: 64
    ```
    - Reverse lookup for the record `172.16.1.5` answered by the DNS server at `172.16.1.254`
    ```bash hl_lines="15 18"
    $ dig -x 172.16.1.5
  
    ; <<>> DiG 9.16.23-RH <<>> -x 172.16.1.5
    ;; global options: +cmd
    ;; Got answer:
    ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 62615
    ;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
    
    ;; OPT PSEUDOSECTION:
    ; EDNS: version: 0, flags:; udp: 1232
    ;; QUESTION SECTION:
    ;5.1.16.172.in-addr.arpa.     IN      PTR
    
    ;; ANSWER SECTION:
    5.1.16.172.in-addr.arpa. 3600 IN      PTR     api.cluster.example.com.
    
    ;; Query time: 0 msec
    ;; SERVER: 172.16.1.254#53(172.16.1.254)
    ;; WHEN: Mon Mar 24 16:11:52 CDT 2025
    ;; MSG SIZE  rcvd: 91 
    ```
    - Wildcard lookup for the record `someapp.apps.cluster.example.com` answered by the DNS server at `172.16.1.254`
    ```bash hl_lines="15 18"
    $ dig someapp.apps.cluster.example.com
  
    ; <<>> DiG 9.16.23-RH <<>> someapp.apps.cluster.example.com
    ;; global options: +cmd
    ;; Got answer:
    ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 46996
    ;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
    
    ;; OPT PSEUDOSECTION:
    ; EDNS: version: 0, flags:; udp: 1232
    ;; QUESTION SECTION:
    ;someapp.apps.cluster.example.com.  IN      A
    
    ;; ANSWER SECTION:
    someapp.apps.cluster.example.com. 3600 IN   A       172.16.1.5
    
    ;; Query time: 0 msec
    ;; SERVER: 172.16.1.254#53(172.16.1.254)
    ;; WHEN: Mon Mar 24 16:13:18 CDT 2025
    ;; MSG SIZE  rcvd: 73 
    ```