#!/bin/bash
set -euo pipefail

# Download OpenShift tools/binaries from a Linux system.
# Defaults can be overridden with command-line options or environment variables.

DL_DIR="${DL_DIR:-$(pwd)/bin}"
RHEL_VERSION="${RHEL_VERSION:-9}"
RELEASE_VERSION="${RELEASE_VERSION:-stable-4.20}"
RELEASE_ARCH="${RELEASE_ARCH:-amd64}"
MIRROR_REGISTRY="${MIRROR_REGISTRY:-false}"
INSTALLER="${INSTALLER:-false}"
FIPS="${FIPS:-false}"
HELM="${HELM:-false}"
REPO_SCRIPTS="${REPO_SCRIPTS:-false}"
ASSUME_YES=false

usage() {
  cat <<EOF
Download OpenShift client tools from Linux for a RHEL 8 or 9 target.

Usage: $(basename "$0") [OPTIONS]

Options:
  -d, --download-dir DIR    Destination directory (default: ./bin)
  -r, --rhel VERSION        Target RHEL major version: 8 or 9 (default: 9)
  -v, --release VERSION     OpenShift channel or version (default: stable-4.20)
                            Examples: latest, stable, stable-4.20, 4.20.2
  -a, --arch ARCH           Architecture: amd64, arm64, ppc64le, or s390x
                            (default: amd64)
      --registry            Download 'mini-Quay' mirror-registry (Requires Podman to run)
      --install             Download the openshift-install
      --fips                Download openshift-install-fips (implies --install)
      --helm                Download Helm
      --scripts             Download disco-docs helper scripts
  -y, --yes                 Skip the confirmation prompt
  -h, --help                Show this help

The defaults can also be set with environment variables named after the settings:
DL_DIR, RHEL_VERSION, RELEASE_VERSION, RELEASE_ARCH, MIRROR_REGISTRY, INSTALLER,
FIPS, HELM, and REPO_SCRIPTS. Command-line options take precedence.

Examples:
  $(basename "$0") --release stable-4.20 --helm --installer
  $(basename "$0") --rhel 8 --arch arm64 --download-dir /opt/oc-tools
  HELM=true REPO_SCRIPTS=true $(basename "$0") --yes
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_value() {
  [ "$#" -ge 2 ] && [ -n "$2" ] || die "Option $1 requires a value."
}

validate_bool() {
  case "$2" in
    true|false) ;;
    *) die "$1 must be 'true' or 'false' (received: $2)." ;;
  esac
}

download() {
  local url=$1
  local output=$2

  wget --quiet --show-progress \
    --tries=3 \
    --timeout=30 \
    --retry-connrefused \
    --output-document="$output" \
    "$url"
}

require_file_destination() {
  [ ! -d "$1" ] || die "Cannot replace '$1' because it is a directory."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -d|--download-dir)
      require_value "$@"
      DL_DIR=$2
      shift 2
      ;;
    -r|--rhel)
      require_value "$@"
      RHEL_VERSION=$2
      shift 2
      ;;
    -v|--release)
      require_value "$@"
      RELEASE_VERSION=$2
      shift 2
      ;;
    -a|--arch)
      require_value "$@"
      RELEASE_ARCH=$2
      shift 2
      ;;
    --registry)
      MIRROR_REGISTRY=true
      shift
      ;;
    --install)
      INSTALLER=true
      shift
      ;;
    --fips)
      FIPS=true
      INSTALLER=true
      shift
      ;;
    --helm)
      HELM=true
      shift
      ;;
    --scripts)
      REPO_SCRIPTS=true
      shift
      ;;
    -y|--yes)
      ASSUME_YES=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      die "Unknown option: $1. Run $(basename "$0") --help for usage."
      ;;
  esac
done

[ "$#" -eq 0 ] || die "Unexpected argument: $1"

case "$RHEL_VERSION" in
  8|9) ;;
  *) die "RHEL version must be 8 or 9 (received: $RHEL_VERSION)." ;;
esac

case "$RELEASE_ARCH" in
  amd64|arm64|ppc64le|s390x) ;;
  *) die "Unsupported architecture: $RELEASE_ARCH." ;;
esac

for setting in MIRROR_REGISTRY INSTALLER FIPS HELM REPO_SCRIPTS; do
  validate_bool "$setting" "${!setting}"
done

for command in curl wget tar awk; do
  command -v "$command" >/dev/null 2>&1 || die "Required command '$command' was not found."
done

if [ "$INSTALLER" = true ] && [ "$RELEASE_ARCH" != amd64 ]; then
  die "The curated installer archives require --arch amd64."
fi

if [ "$FIPS" = true ] && [ "$RHEL_VERSION" != 9 ]; then
  die "The FIPS installer requires --rhel 9 and --arch amd64."
fi

umask 0022 # STIG workaround just in case

REQUESTED_RELEASE=$RELEASE_VERSION
RELEASE_BASE_URL="https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/$REQUESTED_RELEASE"
RELEASE_METADATA=$(curl -fsSL \
  --retry 3 \
  --retry-delay 2 \
  --connect-timeout 15 \
  --max-time 60 \
  "$RELEASE_BASE_URL/release.txt") || die "Could not resolve OpenShift release '$REQUESTED_RELEASE' for '$RELEASE_ARCH'."
RELEASE_VERSION=$(awk '$1 == "Version:" { print $2; exit }' <<< "$RELEASE_METADATA")
[ -n "$RELEASE_VERSION" ] || die "The release metadata for '$REQUESTED_RELEASE' was incomplete."

# Download URLs curated from the supplied settings.
DL_BUTANE="https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/butane/latest/butane-$RELEASE_ARCH"
DL_OC="https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/$RELEASE_VERSION/openshift-client-linux-$RELEASE_ARCH-rhel$RHEL_VERSION.tar.gz"
DL_OCMIRROR_EL9="https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/latest/oc-mirror.rhel9.tar.gz"
DL_OCMIRROR_EL8="https://mirror.openshift.com/pub/openshift-v4/$RELEASE_ARCH/clients/ocp/latest/oc-mirror.tar.gz"
DL_OCP_INSTALL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$RELEASE_VERSION/openshift-install-linux.tar.gz"
DL_OCP_INSTALL_FIPS="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$RELEASE_VERSION/openshift-install-rhel9-amd64.tar.gz"
DL_MIRROR_REGISTRY="https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-$RELEASE_ARCH.tar.gz"
DL_HELM="https://mirror.openshift.com/pub/openshift-v4/clients/helm/latest/helm-linux-$RELEASE_ARCH.tar.gz"
DL_REPO_SCRIPTS=(
  "https://raw.githubusercontent.com/yojoshb/disco-docs/refs/heads/main/_scripts/start-cluster.sh"
  "https://raw.githubusercontent.com/yojoshb/disco-docs/refs/heads/main/_scripts/shutdown-cluster.sh"
  "https://raw.githubusercontent.com/yojoshb/disco-docs/refs/heads/main/_scripts/approve-kube-csr.sh"
  "https://raw.githubusercontent.com/yojoshb/disco-docs/refs/heads/main/_scripts/catalog-fetcher.sh"
)

cat <<EOF
OpenShift version:           $RELEASE_VERSION (requested: $REQUESTED_RELEASE)
Architecture:                $RELEASE_ARCH
Target OS:                   RHEL $RHEL_VERSION
Download directory:          $DL_DIR
Mirror Registry download:    $MIRROR_REGISTRY
OpenShift installer:         $INSTALLER
FIPS:                        $FIPS
Helm download:               $HELM
Repository scripts download: $REPO_SCRIPTS
EOF

if [ "$ASSUME_YES" != true ]; then
  echo
  read -r -p "Press [ENTER] to continue or [CTRL-C] to abort: "
fi

mkdir -p "$DL_DIR"
DL_DIR=$(cd "$DL_DIR" && pwd -P)
TMP_DIR=$(mktemp -d "$DL_DIR/.rhel-oc-tools.XXXXXX")
cleanup() {
  rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT
cd "$TMP_DIR"

# Download Butane, oc, and the RHEL-specific oc-mirror.
download "$DL_BUTANE" "butane-$RELEASE_ARCH"
download "$DL_OC" openshift-client.tar.gz
if [ "$RHEL_VERSION" = 9 ]; then
  download "$DL_OCMIRROR_EL9" oc-mirror.tar.gz
else
  download "$DL_OCMIRROR_EL8" oc-mirror.tar.gz
fi

if [ "$MIRROR_REGISTRY" = true ]; then
  MIRROR_REGISTRY_ARCHIVE="mirror-registry-$RELEASE_ARCH.tar.gz"
  download "$DL_MIRROR_REGISTRY" "$MIRROR_REGISTRY_ARCHIVE"
fi

if [ "$HELM" = true ]; then
  download "$DL_HELM" helm.tar.gz
  tar zxf helm.tar.gz
fi

if [ "$INSTALLER" = true ]; then
  if [ "$FIPS" = true ]; then
    download "$DL_OCP_INSTALL_FIPS" openshift-install.tar.gz
    tar zxf openshift-install.tar.gz
    chmod a+x openshift-install-fips
  else
    download "$DL_OCP_INSTALL" openshift-install.tar.gz
    tar zxf openshift-install.tar.gz
    chmod a+x openshift-install
  fi
fi

if [ "$REPO_SCRIPTS" = true ]; then
  mkdir repo-scripts
  for script in "${DL_REPO_SCRIPTS[@]}"; do
    download "$script" "repo-scripts/$(basename "$script")"
  done
  chmod a+x repo-scripts/*.sh
fi

tar zxf openshift-client.tar.gz
tar zxf oc-mirror.tar.gz
mv "butane-$RELEASE_ARCH" butane
chmod a+x oc kubectl butane oc-mirror

# Check every destination before replacing any existing files.
OUTPUT_FILES=(oc kubectl butane oc-mirror)
if [ "$HELM" = true ]; then OUTPUT_FILES+=(helm); fi
if [ "$INSTALLER" = true ]; then
  if [ "$FIPS" = true ]; then OUTPUT_FILES+=(openshift-install-fips); else OUTPUT_FILES+=(openshift-install); fi
fi
if [ "$MIRROR_REGISTRY" = true ]; then OUTPUT_FILES+=("$MIRROR_REGISTRY_ARCHIVE"); fi

for output in "${OUTPUT_FILES[@]}"; do
  require_file_destination "$DL_DIR/$output"
done
if [ "$REPO_SCRIPTS" = true ]; then
  [ ! -e "$DL_DIR/scripts" ] || [ -d "$DL_DIR/scripts" ] || die "Cannot create '$DL_DIR/scripts' because it is not a directory."
  for script in repo-scripts/*.sh; do
    require_file_destination "$DL_DIR/scripts/$(basename "$script")"
  done
fi

mv -f oc kubectl butane oc-mirror "$DL_DIR"
if [ "$HELM" = true ]; then mv -f "helm-linux-$RELEASE_ARCH" "$DL_DIR/helm"; fi
if [ "$INSTALLER" = true ]; then
  if [ "$FIPS" = true ]; then mv -f openshift-install-fips "$DL_DIR"; else mv -f openshift-install "$DL_DIR"; fi
fi
if [ "$MIRROR_REGISTRY" = true ]; then mv -f "$MIRROR_REGISTRY_ARCHIVE" "$DL_DIR"; fi
if [ "$REPO_SCRIPTS" = true ]; then
  mkdir -p "$DL_DIR/scripts"
  mv -f repo-scripts/*.sh "$DL_DIR/scripts"
fi
cd "$DL_DIR"

echo
echo "Tools downloaded to: $DL_DIR"
ls -1 --color=auto
