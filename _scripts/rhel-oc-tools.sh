#!/bin/bash
set -e

# Script to download OpenShift tools/binaries on a Red Hat 8/9 system

### Variables to modify
DL_DIR="$(pwd)/bin"           # Download directory: /some/path
RHEL_VERSION="9"              # Major version of RHEL: 8 or 9
RELEASE_VERSION="stable-4.17" # OpenShift Channel and version: latest, stable, stable-4.20, etc
RELEASE_ARCH="amd64"          # OpenShift and Tools architecture: amd64, arm64, ppc64le, s390x, multi
MIRROR_REGISTRY=0             # 1=true or 0=false, to download the mirror-registry or not
INSTALLER=0                   # 1=true or 0=false, to extract the openshift-install binary or not. $RHEL_VERSION must match your current machine so the correct 'oc' binary is used for extraction
FIPS=0                        # 1=true or 0=false, only for OpenShift version 4.16 and later to determine if the openshift-install binary needs to be a FIPS version or not. Only used if INSTALLER=1

### Shouldn't need to modify, only used if INSTALLER=1
RELEASE_IMAGE=$(curl -s https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/$RELEASE_VERSION/release.txt | grep 'Pull From: quay.io' | awk -F ' ' '{print $3}')
RUNTIME_RHEL_VERSION=$(cat /etc/redhat-release | cut -f1 -d. | tr -d -c 0-9)

### Main ###
if [ "$RHEL_VERSION" = "9" ] || [ "$RHEL_VERSION" = "8" ]; then
  :
else
  echo "Aborting. Invalid RHEL Version specified: $RHEL_VERSION"; exit
fi

# Download URL's curated from supplied vars
DL_BUTANE="https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/butane/latest/butane-$RELEASE_ARCH"                                             # Latest butane
DL_OC="https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/$RELEASE_VERSION/openshift-client-linux-$RELEASE_ARCH-rhel$RHEL_VERSION.tar.gz" # Version & RHEL specific oc 
DL_OCMIRROR_EL9="https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/latest/oc-mirror.rhel9.tar.gz"                                        # Latest oc-mirror for rhel9
DL_OCMIRROR_EL8="https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/latest/oc-mirror.tar.gz"                                              # Latest oc-mirror for rhel8
DL_MIRROR_REGISTRY="https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-$RELEASE_ARCH.tar.gz"                                          # Latest mirror-registry

# Print info based on supplied vars
echo "Architecture: $RELEASE_ARCH"
echo "OS: RHEL$RHEL_VERSION"
echo "Download directory: $DL_DIR"

if [ "$MIRROR_REGISTRY" = "1" ]; then
  echo "Mirror Registry download: True"
else
  echo "Mirror Registry download: False"
fi

if [ "$INSTALLER" = "1" ] && [ "$RHEL_VERSION" = "$RUNTIME_RHEL_VERSION" ]; then
  if [ "$FIPS" = "1" ]; then
    echo "OpenShift Install binary: True, extracting FIPS binary from $RELEASE_IMAGE"
  else
    echo "OpenShift Install binary: True, extracting binary from $RELEASE_IMAGE"
  fi
else
  echo "OpenShift Install binary: False, either INSTALLER=0 or your runtime version of RHEL does not match the RHEL_VERSION you defined."
  INSTALLER=0
fi
echo ""
read -p "Press [ENTER] to continue  |  Press [CTRL-C] to abort"
echo ""

# Create dir structure and clean tmp if there's leftover junk in there from possible download failure
mkdir -p $DL_DIR/tmp
cd $DL_DIR/tmp
rm -f *

# Download butane and oc
wget -q --show-progress $DL_BUTANE
wget -q --show-progress $DL_OC

# Download rhel specific oc-mirror
if [ "$RHEL_VERSION" = "9" ]; then wget -q --show-progress $DL_OCMIRROR_EL9; else wget -q --show-progress $DL_OCMIRROR_EL8; fi

# If true, download mirror-registry
if [ "$MIRROR_REGISTRY" = "1" ]; then wget -q --show-progress -P ../ $DL_MIRROR_REGISTRY; fi

# Extract tools
for tar in *.tar.gz; do
  tar zxf $tar
  rm -f $tar
  rm -f README.md
done
chmod a+x oc kubectl

# If true, extract the openshift-install binary for fips or non fips
if [ "$INSTALLER" = "1" ] && [ "$RHEL_VERSION" = "$RUNTIME_RHEL_VERSION" ]; then
  if [ "$FIPS" = "1" ]; then
    echo "Extracting openshift-install-fips binary"
    ./oc adm release extract --command=openshift-install-fips $RELEASE_IMAGE && echo "openshift-install-fips binary extracted"
    chmod a+x openshift-install-fips
    mv openshift-install-fips ..
  else
    echo "Extracting openshift-install binary"
    ./oc adm release extract --command=openshift-install $RELEASE_IMAGE && echo "openshift-install binary extracted"
    chmod a+x openshift-install
    mv openshift-install ..
  fi
fi

mv butane-$RELEASE_ARCH butane
chmod a+x butane oc-mirror
mv oc kubectl butane oc-mirror ..

# Remove tmp directory
cd ..
rm -rf tmp
echo -e "\nTools downloaded to: $DL_DIR"