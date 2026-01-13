#!/bin/bash
set -e

# Node list: List all hostnames of the nodes to ssh to
NODES=(
control1.cluster.example.com
...
)

# Path to Private SSH key that can connect to the hosts
KEY=/home/user/.ssh/id_rsa

# Yes this is using sudo inside of a bash script..  
APPROVE_CSR(){
  cat << 'EOF'
echo "Copy local.kubeconfig to /tmp"
sudo cp /etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost.kubeconfig /tmp
sudo chown core:core /tmp/localhost.kubeconfig
export KUBECONFIG=/tmp/localhost.kubeconfig

echo -e "\nPrint CSR's"
oc get csr

echo -e "\nApprove all CSR's"
oc get csr -o name | xargs oc adm certificate approve
rm -f /tmp/localhost.kubeconfig
EOF
}

for node in "${NODES[@]}"; do
  LOGFILE="./kubecsr-${node}.log"
  echo "----- $node -----"
  echo "----- $(date) -----" >> "$LOGFILE"
  ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 -i $KEY core@$node "$(APPROVE_CSR)" 2>&1 | tee -a "$LOGFILE"
  echo
done