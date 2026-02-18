#!/bin/bash

# Default values
VERSION="4.20"
CATALOG="all"

check_deps() {
  if ! command -v oc &> /dev/null; then echo "Error: 'oc' command not found. Please install it or ensure it is in your system PATH." && exit 1; fi
  if ! command -v oc-mirror &> /dev/null; then echo "Error: 'oc-mirror' command not found. Please install it or ensure it is in your system PATH." && exit 1; fi
  # hacky way to make sure 4.21 or newer oc-mirror version is in use so --v1 flags are used
  ocmirror_version=$(oc mirror version 2>&1 /dev/null | grep -o 'GitVersion:"[^"]*"' | cut -d'"' -f2)
  ocmirror_req_version="4.21"
  ocmirror_lowest_version=$(printf '%s\n' "$ocmirror_version" "$ocmirror_req_version" | sort -V | head -n1)
  if [ "$ocmirror_lowest_version" = "$ocmirror_req_version" ]; then : ; else echo "Error: oc-mirror version is lower than $ocmirror_req_version. Please install the latest version for your architecture." && exit 1; fi
}

check_deps

helper() {
  cat <<EOF
Fetch OpenShift Operator Catalog contents and write them to a file in the current directory. All operators will be listed by their default channel.

Usage: $0 [OPTIONS]

Options:
  -v, --version <ver>   Specify OpenShift version (default: 4.20)
  -c, --catalog <name>  Specify catalog name (default: all)
                        Options: all, redhat-operator-index, certified-operator-index, community-operator-index, redhat-marketplace-index

  -h, --help            Show this help message

Examples:
  $0 --version 4.18 --catalog certified-operator-index
  $0 --version 4.19
EOF
  exit 0
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -v|--version) VERSION="$2"; shift ;;
    -c|--catalog) CATALOG="$2"; shift ;;
    -h|--help) helper ;;
    *) echo "Unknown parameter: $1"; helper ;;
  esac
  shift
done

echo "Fetching catalogs for Version: $VERSION"; echo "Target Catalog: $CATALOG"; echo "----------------------------------------"

if [ "$CATALOG" = "all" ]; then
  for catalog in $(oc mirror list operators --catalogs --version=$VERSION --v1 2> /dev/null | grep registry); do
    file=$(echo "$catalog" | sed 's/.*redhat\///;s/:.*//')_v$VERSION.txt
    echo -e "Processing $catalog -> $file\n"
    oc mirror list operators --catalog=$catalog --version=$VERSION --v1 2> /dev/null > $file
	echo -e "\nProcessed Catalog: $catalog on $(date)" >> $file
	echo -e "- If you need to list all channels for a specific operator use:\n    oc mirror list operators --catalog=$catalog --version=$VERSION --package=<operator-name> --v1\n"
    echo -e "- If you need to list all available versions for a specified operator in a channel use:\n    oc mirror list operators --catalog=$catalog --version=$VERSION --package=<operator-name> --channel=<channel-name> --v1"
	echo "----------------------------------------"
  done
else
  url="registry.redhat.io/redhat/"
  version=":v${VERSION}"
  catalog="${url}${CATALOG}${version}"
  file="${CATALOG}_v${VERSION}.txt"
  echo -e "Processing $catalog -> $file\n"
  oc mirror list operators --catalog=$catalog --version=$VERSION --v1 2> /dev/null > $file
  echo -e "\nProcessed Catalog: $catalog on $(date)" >> $file
  echo -e "- If you need to list all channels for a specific operator use:\n    oc mirror list operators --catalog=$catalog --version=$VERSION --package=<operator-name> --v1\n"
  echo -e "- If you need to list all available versions for a specified operator in a channel use:\n    oc mirror list operators --catalog=$catalog --version=$VERSION --package=<operator-name> --channel=<channel-name> --v1"
  echo "----------------------------------------"
fi

rm -f .oc-mirror.log