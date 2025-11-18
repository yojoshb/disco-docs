#!/bin/bash
set -e

# Script to gracefully shutdown the cluster. Requires cluster-admin permissions. Nodes will be unschedulable when powered back on

### Variables to modify ###
# oc tool path: Either specify the path or find it with another tool
OC="$(command -v oc)"

# Shutdown time: Indicates how long, in minutes, the process lasts before the control plane nodes are shut down. For large-scale clusters with 10 nodes or more, set to '10' or longer to make sure all the compute nodes have time to shut down first.
TIME=2

# Credentials: uncomment the line below and specify the path via kubeconfig; otherwise be sure to login to your cluster before running the script
#export KUBECONFIG=/home/user/mycluster/auth/kubeconfig

### Main ###

# Check for cluster login status and permissions
if [[ "$(${OC} whoami)" ]] ; then
  :
else
  exit
fi

if [[ "$(${OC} get clusterrolebinding -o json | jq '.items[] | select(.roleRef.name == "cluster-admin") | .subjects[] | select(.kind == "User" or .kind == "Group") | .name')" ]] ; then
  :
else
  exit
fi

RUNTIME=$(date)
OUTLOG="./$(${OC} cluster-info | awk 'NR<2 {for(i=1;i<=NF;i++) if ($i ~ /^https?:\/\//) url=$i} END {sub("https?://","",url); sub(":[0-9]+","",url); sub("^api\\.","",url); print url}')-SHUTDOWN_$(date "+%Y-%m-%d-%I:%M%p").log"
touch "$OUTLOG"
exec > >(tee -a "$OUTLOG") 2>&1

cleanup(){
  echo -e "Initiated Shutdown Script on: ${RUNTIME}\nCaught Ctrl+C — Shutdown Script was terminated" >> ${OUTLOG}
  exit 130
}
trap cleanup INT

# Print info before shutdown operations
echo -e "\n$(${OC} cluster-info | awk 'NR<2')"
echo -e "\nPreparing to shutdown the cluster, make sure you have created an etcd backup before continuing\nInitiated Shutdown Script on: ${RUNTIME}"
echo -e "The cluster certificates will expire on: $(${OC} -n openshift-kube-apiserver-operator get secret kube-apiserver-to-kubelet-signer -o jsonpath='{.metadata.annotations.auth\.openshift\.io/certificate-not-after}' | xargs -I{} date -d {}). Make sure to boot the cluster before this date\n"

read -p "Press [ENTER] to shutdown the cluster  |  Press [CTRL-C] to abort"

# Begin loops for a graceful-ish shutdown
echo -e "\nShutting down cluster!"

echo -e "\nMarking nodes as Unschedulable\n----------------------------------------"
for node in $(${OC} get nodes -o jsonpath='{.items[*].metadata.name}'); do
  echo ${node}
  ${OC} adm cordon ${node}
done

echo -e "\nEvacuating Worker nodes\n----------------------------------------"
for node in $(${OC} get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[*].metadata.name}'); do
  echo ${node}
  ${OC} adm drain ${node} --delete-emptydir-data --ignore-daemonsets=true --timeout=30s --force
done

echo -e "\nIssuing shutdown command with a time of ${TIME} minutes\n----------------------------------------"
for node in $(${OC} get nodes -o jsonpath='{.items[*].metadata.name}'); do
  ${OC} debug node/${node} -- chroot /host shutdown -h ${TIME}
done

echo -e "\nShutdown Script finished on: $(date)"