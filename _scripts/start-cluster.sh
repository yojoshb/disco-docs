#!/bin/bash
set -e

# Script to set nodes to be scheduable (uncordon). This is to be done after powering back up from a graceful shutdown.

### Variables to modify ###
# oc tool path: Either specify the path or find it with another tool
OC="$(command -v oc)"

# Credentials: uncomment the line below and specify the path via kubeconfig; otherwise be sure to login to your cluster before running the script
#export KUBECONFIG=/home/user/mycluster/auth/kubeconfig

### Main ###

# Check for cluster login status, and cluster permissions
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
OUTLOG="./$(${OC} cluster-info | awk 'NR<2 {for(i=1;i<=NF;i++) if ($i ~ /^https?:\/\//) url=$i} END {sub("https?://","",url); sub(":[0-9]+","",url); sub("^api\\.","",url); print url}')-START_$(date "+%Y-%m-%d-%I:%M%p").log"
touch "$OUTLOG"
exec > >(tee -a "$OUTLOG") 2>&1

cleanup(){
  echo -e "Initiated Startup Script on: ${RUNTIME}\nCaught Ctrl+C — Start Script was terminated" >> ${OUTLOG}
  exit 130
}
trap cleanup INT

# Print info before startup operations
echo -e "\n$(${OC} cluster-info | awk 'NR<2')"
echo -e "\nPreparing to start the cluster, make sure nodes/hardware is ready and all cluster sub-components are available\nInitiated Start Script on: ${RUNTIME}\n"

read -p "Press [ENTER] to continue  |  Press [CTRL-C] to abort"

### Main Operations ###
echo -e "\nStarting the cluster!"

echo -e "\nMarking nodes as Schedulable\n----------------------------------------"
for node in $(${OC} get nodes -o jsonpath='{.items[*].metadata.name}'); do
  echo ${node}
  ${OC} adm uncordon ${node}
done

echo -e "\nListing all current Certificate Signing Requests\n----------------------------------------"
${OC} get csr

echo

read -p "Would you like to forcibly approve all certificates? (Y/n): " yn
yn=${yn:-Y}

if [[ "$yn" =~ ^[Yy]$ ]]; then
  echo -e "\nApproving all CSR's\n----------------------------------------"
  ${OC} get csr -o name | xargs ${OC} adm certificate approve
else
    echo -e "Skipping certificate approvals"
fi

echo -e "\nStartup Script finished on: $(date)"