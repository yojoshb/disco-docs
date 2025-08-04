#!/bin/bash
set -e

# Script to download OpenShift tools/binaries on a Red Hat 8/9 system

### Variables to modify ###
# Download directory: /some/path
DL_DIR="$(pwd)/bin"

# Major version of RHEL: 8 or 9           
RHEL_VERSION="9"

# OpenShift Channel and version: latest, stable, stable-4.20, etc
RELEASE_VERSION="stable-4.18"

# OpenShift and Tools architecture: amd64, arm64, ppc64le, s390x, multi
RELEASE_ARCH="amd64"

# boolean true or false, to download the mirror-registry or not
MIRROR_REGISTRY=false

# boolean true or false, to extract the openshift-install binary or not. $RHEL_VERSION must match your current machine so the correct 'oc' binary is used for extraction
INSTALLER=false

# boolean true or false, only for OpenShift version 4.16 and later to determine if the openshift-install binary needs to be a FIPS version or not. Only used if INSTALLER=true
FIPS=false

### Shouldn't need to modify ###
RELEASE_IMAGE=$(curl -s https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/$RELEASE_VERSION/release.txt | grep 'Pull From: quay.io' | awk -F ' ' '{print $3}')
RELEASE_VERSION=$(curl -s https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/$RELEASE_VERSION/release.txt | grep 'Version:' | awk -F ' ' '{print $2}')
RUNTIME_RHEL_VERSION=$(cat /etc/redhat-release | cut -f1 -d. | tr -d -c 0-9)

### Main ###
if [ "$RHEL_VERSION" = "9" ] || [ "$RHEL_VERSION" = "8" ] && [ "$RUNTIME_RHEL_VERSION" = "8" ] || [ "$RUNTIME_RHEL_VERSION" = "9" ] ; then
  :
else
  echo "Aborting. Invalid RHEL Version or RHEL runtime"; exit
fi

# Download URL's curated from supplied vars
DL_BUTANE="https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/butane/latest/butane-$RELEASE_ARCH"                                             # Latest butane
DL_OC="https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/$RELEASE_VERSION/openshift-client-linux-$RELEASE_ARCH-rhel$RHEL_VERSION.tar.gz" # Version & RHEL specific oc 
DL_OCMIRROR_EL9="https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/latest/oc-mirror.rhel9.tar.gz"                                        # Latest oc-mirror for rhel9
DL_OCMIRROR_EL8="https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/latest/oc-mirror.tar.gz"                                              # Latest oc-mirror for rhel8
DL_MIRROR_REGISTRY="https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-$RELEASE_ARCH.tar.gz"                                          # Latest mirror-registry

# Print info based on supplied vars
echo "OpenShift Version: $RELEASE_VERSION"
echo "Architecture: $RELEASE_ARCH"
echo "OS: RHEL$RHEL_VERSION"
echo "Download directory: $DL_DIR"
echo "Mirror Registry download: $MIRROR_REGISTRY"

if [ "$INSTALLER" = true ] && [ "$RHEL_VERSION" = "$RUNTIME_RHEL_VERSION" ]; then
  if [ "$FIPS" = true ]; then
    echo "OpenShift Install binary: $INSTALLER, extracting FIPS binary from $RELEASE_IMAGE"
  else
    echo "OpenShift Install binary: $INSTALLER, extracting binary from $RELEASE_IMAGE"
  fi
  echo "> Make sure you have either $HOME/.docker/config.json or $XDG_RUNTIME_DIR/containers/auth.json populated with your Red Hat Pull Secret"
else
  echo "OpenShift Install binary: false, either INSTALLER=false or your runtime version of RHEL does not match the RHEL_VERSION you defined."
  INSTALLER=false
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
if [ "$MIRROR_REGISTRY" = true ]; then wget -q --show-progress -P ../ $DL_MIRROR_REGISTRY; fi

# Extract tools
for tar in *.tar.gz; do
  tar zxf $tar
  rm -f $tar
  rm -f README.md
done
chmod a+x oc kubectl

# If true, extract the openshift-install binary for fips or non fips
if [ "$INSTALLER" = true ] && [ "$RHEL_VERSION" = "$RUNTIME_RHEL_VERSION" ]; then
  if [ "$FIPS" = true ]; then
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

echo -e "\nTools saved to: $DL_DIR\n"
