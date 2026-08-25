#!/bin/bash
set -euo pipefail

VERSION="${VERSION:-4.20}"
CATALOG="${CATALOG:-all}"
MODE=list
OUTPUT_FILE=""
PACKAGE_SPECS=()
TUI_TITLE="OpenShift ImageSet Builder"
TUI_ACTION_EDIT_CONFIG="Edit an existing configuration"
TUI_ACTION_UPGRADE_OPERATORS="Upgrade Operator packages from loaded configuration"
TUI_ACTION_EDIT_PLATFORM="Add or edit a Platform version"
TUI_ACTION_EDIT_CATALOG="Add or edit an Operator catalog"
TUI_ACTION_ADD_OPERATOR_GROUP="Add an Operator group"
TUI_ACTION_BROWSE_CATALOGS="Browse Operator catalogs and packages"
TUI_ACTION_VIEW_SELECTIONS="View current selections"
TUI_ACTION_FINISH="Finish selections and build YAML"
TUI_ACTION_EXIT="Cancel"
TUI_WIDTH=78
TUI_HEIGHT=22
TUI_LIST_HEIGHT=14
TUI_INPUT_HEIGHT=14
TUI_TERMINAL_LINES=24
TUI_TERMINAL_COLUMNS=80
TUI_TERMINFO_DIR=""
TUI_SCREEN_INITIALIZED=false
TUI_ALT_SCREEN_ACTIVE=false
TUI_TERMINAL_RESTORED=false
declare -A CACHED_DEFAULT_CHANNELS=()
declare -A CACHED_PACKAGE_METADATA=()
declare -A CACHED_CHANNEL_VERSIONS=()
declare -A CACHED_CATALOG_PACKAGE_DEFAULTS=()
declare -A CACHED_RELEASE_CHANNEL_RANGES=()
declare -A CACHED_CURRENT_RELEASES=()
TUI_CATALOG_IMAGES=()
TUI_INITIAL_CATALOG_HANDLED=false
TUI_PLATFORM_CONFIGURED=false
TUI_PLATFORM_ARCHITECTURES=()
TUI_PLATFORM_GRAPH=true
TUI_PLATFORM_CHANNELS=()
TUI_CATALOG_PACKAGES=()
TUI_OPERATOR_VERSIONS=()
TUI_LOADED_FILE=""
TUI_PRESERVED_CONFIG_SUFFIX=""
declare -A TUI_PLATFORM_VERSIONS=()
declare -A TUI_PLATFORM_MIN_VERSIONS=()
declare -A TUI_PLATFORM_MAX_VERSIONS=()
declare -A TUI_PLATFORM_FULL_CHANNELS=()
declare -A TUI_PLATFORM_CURRENT_VERSIONS=()
declare -A TUI_PLATFORM_CURRENT_VERSION_ARCHES=()
declare -A TUI_CATALOG_PACKAGE_SPECS=()
declare -A TUI_CATALOG_VERSIONS=()
declare -A TUI_WHOLE_CATALOG=()
declare -A TUI_IMPORTED_PACKAGES=()
declare -A TUI_IMPORTED_PACKAGE_DEFAULTS=()
declare -A TUI_OPERATOR_CHANNEL_MIN_VERSIONS=()
declare -A TUI_OPERATOR_CHANNEL_MAX_VERSIONS=()
declare -A SEEN_PACKAGES=()

KNOWN_CATALOGS=(
  redhat-operator-index
  certified-operator-index
  community-operator-index
  redhat-marketplace-index
)

# -----------------------------------------------------------------------------
# Curated content bundles
#
# To add a normal Operator group:
#   1. Define a NAME_OPERATOR_BUNDLE array in this section.
#   2. Add its display name to the groups array in add_tui_operator_group().
#   3. Map that exact display name to the bundle in
#      load_operator_group_definition().
#
# Every package in OPERATOR_GROUP_PACKAGES is shown in the review checklist.
# Packages copied to OPERATOR_GROUP_DEFAULT_PACKAGES start selected; use a
# smaller DEFAULT bundle when some packages should be optional.
#
# Operator groups currently target redhat-operator-index. Entries that do not
# exist in the selected catalog version are omitted and reported to the user.
# COMMON_ADDITIONALIMAGES_BUNDLE is separate and is not an Operator group.
# -----------------------------------------------------------------------------

if [ -z "${ODF_OPERATOR_BUNDLE:-}" ]; then
  # {version} is replaced when the user selects the Operator catalog version.
  ODF_OPERATOR_BUNDLE='https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/{version}/html/planning_your_deployment/disconnected-environment_rhodf'
fi

# The documentation is authoritative, but this fallback keeps group selection
# useful when curl is unavailable, the host is offline, or the page changes.
# Pinned to 4.22 currently
ODF_OPERATOR_BUNDLE_FALLBACK=(
  ocs-operator
  odf-operator
  mcg-operator
  odf-csi-addons-operator
  ocs-client-operator
  odf-prometheus-operator
  recipe
  rook-ceph-operator
  cephcsi-operator
  odf-dependencies
  odf-external-snapshotter-operator
  ocs-tls-profiles
)

ODF_LOCALSTORAGE_OPERATOR_BUNDLE=(
  local-storage-operator
)

ODF_DR_OPERATOR_BUNDLE=(
  odf-multicluster-orchestrator
  odr-cluster-operator
  odr-hub-operator
  odr-volsync-plugin-operator
)

VIRT_OPERATOR_BUNDLE=(
  kubevirt-hyperconverged
  kubernetes-nmstate-operator
  node-healthcheck-operator
  node-maintenance-operator
  fence-agents-remediation
  self-node-remediation
  cluster-kube-descheduler-operator
  mtv-operator
)

ACM_OPERATOR_BUNDLE=(
  advanced-cluster-management
  multicluster-engine
  submariner
)

OPERATIONS_OPERATOR_BUNDLE=(
  redhat-oadp-operator
  web-terminal
  devworkspace-operator
  cli-manager
)

SECURITY_OPERATOR_BUNDLE=(
  rhacs-operator
  openshift-cert-manager-operator
  compliance-operator
)

# https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.6/html/installing_logging/overview-of-openshift-logging-installation#logging-installation-workflow_overview-of-openshift-logging-installation
LOGGING_OPERATOR_BUNDLE=(
  elasticsearch-operator
  loki-operator
  openshift-logging
)

LOCALSTORAGE_OPERATOR_BUNDLE=(
  lvms-operator
  local-storage-operator
)

COMMON_ADDITIONALIMAGES_BUNDLE=(
  registry.redhat.io/rhel8/support-tools:latest
  registry.redhat.io/rhel9/support-tools:latest
  registry.redhat.io/ubi9/ubi:latest
  registry.redhat.io/ubi8/ubi:latest
  registry.redhat.io/rhel8/rhel-guest-image:latest
  registry.redhat.io/rhel9/rhel-guest-image:latest
)

export NEWT_COLORS="${NEWT_COLORS:-
root=lightgray,black
border=brightcyan,black
window=lightgray,black
shadow=black,black
title=brightcyan,black
button=lightgray,black
actbutton=black,cyan
checkbox=lightgray,black
actcheckbox=black,cyan
entry=white,black
label=lightgray,black
listbox=lightgray,black
actlistbox=black,cyan
sellistbox=white,black
actsellistbox=black,cyan
textbox=lightgray,black
acttextbox=black,cyan
helpline=brightcyan,black
roottext=lightgray,black
emptyscale=lightgray,black
fullscale=cyan,black
compactbutton=lightgray,black
}"

# -----------------------------------------------------------------------------
# Command-line and catalog identity helpers
# -----------------------------------------------------------------------------

usage() {
  cat <<EOF
List OpenShift Operator catalog contents or build a complete oc-mirror v2
ImageSetConfiguration YAML file with platform and Operator content.

Usage: $(basename "$0") [OPTIONS]

Options:
  -v, --version VERSION     Default OpenShift version (default: 4.20)
  -c, --catalog CATALOG     Catalog short name or full image reference
                            (default for list mode: all)
  -t, --tui                 Open the Whiptail interactive builder
  -y, --yaml                Generate an ImageSetConfiguration YAML file
      --self-test           Run built-in regression checks without network access
  -p, --package SPEC...     One or more package selections for YAML mode
                            Formats: NAME, NAME:CHANNEL, NAME:CHANNEL1,CHANNEL2
  -o, --output FILE         YAML output path
                            (default: imageset-config-v<VERSION>.yaml)
  -h, --help                Show this help

Catalog names:
  redhat-operator-index
  certified-operator-index
  community-operator-index
  redhat-marketplace-index

In YAML mode, omitting --package includes the entire catalog using its default
channel heads. Omitting a channel from --package queries and selects that
package's default channel. TUI mode asks for a version when adding platform or
Operator content, and can combine multiple OpenShift versions in one image set.
Packages use their default channels without additional queries; channel
cherry-picking is opt-in. A chosen channel can use its current head or an exact
Operator version. The TUI can browse available platform channels and their
release ranges, or load an existing
ImageSetConfiguration from the directory where it was launched. Loaded
Operator selections can be refreshed from their current catalog defaults or
compared with a newer catalog version. Upgrades can retain exact current and
target bundles for selected packages in the upgraded catalog. Curated Operator
groups can be merged into a matching catalog without replacing existing
selections. It requires
Whiptail (provided by the RHEL 'newt' package).
Use arrow keys to navigate, Space to toggle checklist items, Enter to select
or apply, and Esc to go back.

Examples:
  $(basename "$0") --version 4.17
  $(basename "$0") --tui --version 4.18
  $(basename "$0") --version 4.19 --catalog certified-operator-index
  $(basename "$0") --yaml --version 4.19 --catalog redhat-operator-index --package ansible-automation-platform-operator:stable-2.6
  $(basename "$0") --yaml --catalog redhat-operator-index --package lvms-operator cincinnati-operator:stable
EOF
}

die() {
  if [ "${MODE:-}" = tui ] && [ "${TUI_SCREEN_INITIALIZED:-false}" = true ] && \
    declare -F tui_restore_terminal >/dev/null 2>&1; then
    tui_restore_terminal
  fi
  echo "Error: $*" >&2
  exit 1
}

require_value() {
  [ "$#" -ge 2 ] && [ -n "$2" ] || die "Option $1 requires a value."
}

validate_name() {
  [[ "$2" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die "Invalid $1: $2"
}

catalog_image() {
  local catalog=$1
  local version=${2:-$VERSION}

  if [[ "$catalog" == */* ]]; then
    [[ "$catalog" == *:* ]] || die "A full catalog image reference must include a tag."
    [[ "$catalog" != *[[:space:]]* ]] || die "Catalog image references cannot contain whitespace."
    printf '%s\n' "$catalog"
  else
    validate_name "catalog name" "$catalog"
    printf 'registry.redhat.io/redhat/%s:v%s\n' "$catalog" "$version"
  fi
}

catalog_version() {
  local image=$1
  local tag=${image##*:}

  if [[ -v TUI_CATALOG_VERSIONS["$image"] ]]; then
    printf '%s\n' "${TUI_CATALOG_VERSIONS[$image]}"
  elif [[ "$tag" =~ ^v([0-9]+\.[0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "$VERSION"
  fi
}

catalog_image_for_version() {
  local image=$1
  local version=$2

  if [[ "$image" =~ ^(.+):v[0-9]+\.[0-9]+$ ]]; then
    printf '%s:v%s\n' "${BASH_REMATCH[1]}" "$version"
    return 0
  fi
  return 1
}

catalog_filename() {
  local image=${1##*/}
  printf '%s_v%s.txt\n' "${image%%:*}" "$VERSION"
}

check_dependencies() {
  local command
  local -a commands=(oc oc-mirror awk sort mktemp)
  [ "$MODE" != tui ] || commands+=(whiptail find grep)
  for command in "${commands[@]}"; do
    command -v "$command" >/dev/null 2>&1 || die "Required command '$command' was not found."
  done

  local version_output oc_mirror_version minimum_version lowest_version
  version_output=$(oc mirror version 2>&1 || true)
  oc_mirror_version=$(awk 'match($0, /GitVersion:"[^"]+"/) { value=substr($0, RSTART, RLENGTH); gsub(/GitVersion:|"|v/, "", value); print value; exit }' <<< "$version_output")
  minimum_version=4.21
  [ -n "$oc_mirror_version" ] || die "Could not determine the oc-mirror version."
  lowest_version=$(printf '%s\n' "$oc_mirror_version" "$minimum_version" | sort -V | head -n1)
  [ "$lowest_version" = "$minimum_version" ] || die "oc-mirror $minimum_version or newer is required (found: $oc_mirror_version)."
}

# -----------------------------------------------------------------------------
# Terminal lifecycle and command progress
# -----------------------------------------------------------------------------

tui_update_geometry() {
  local terminal_lines terminal_columns terminal_size

  terminal_size=$(stty size 2>/dev/null < /dev/tty || true)
  read -r terminal_lines terminal_columns <<< "$terminal_size"
  if [[ ! "$terminal_lines" =~ ^[0-9]+$ ]] || [[ ! "$terminal_columns" =~ ^[0-9]+$ ]] || \
    [ "$terminal_lines" -le 0 ] || [ "$terminal_columns" -le 0 ]; then
    terminal_lines=$(tput lines 2>/dev/null || true)
    terminal_columns=$(tput cols 2>/dev/null || true)
  fi
  [[ "$terminal_lines" =~ ^[0-9]+$ ]] && [ "$terminal_lines" -gt 0 ] || terminal_lines=24
  [[ "$terminal_columns" =~ ^[0-9]+$ ]] && [ "$terminal_columns" -gt 0 ] || terminal_columns=80
  TUI_TERMINAL_LINES=$terminal_lines
  TUI_TERMINAL_COLUMNS=$terminal_columns

  TUI_WIDTH=$((terminal_columns - 4))
  [ "$TUI_WIDTH" -le 120 ] || TUI_WIDTH=120
  [ "$TUI_WIDTH" -ge 30 ] || TUI_WIDTH=$((terminal_columns - 2))
  [ "$TUI_WIDTH" -ge 20 ] || TUI_WIDTH=20

  TUI_HEIGHT=$((terminal_lines - 4))
  [ "$TUI_HEIGHT" -le 34 ] || TUI_HEIGHT=34
  [ "$TUI_HEIGHT" -ge 14 ] || TUI_HEIGHT=$((terminal_lines - 2))
  [ "$TUI_HEIGHT" -ge 10 ] || TUI_HEIGHT=10

  TUI_LIST_HEIGHT=$((TUI_HEIGHT - 8))
  [ "$TUI_LIST_HEIGHT" -ge 4 ] || TUI_LIST_HEIGHT=4
  TUI_INPUT_HEIGHT=14
  [ "$TUI_INPUT_HEIGHT" -le "$TUI_HEIGHT" ] || TUI_INPUT_HEIGHT=$TUI_HEIGHT
}

tui_package_label() {
  local package=$1
  local default_channel=$2
  local suffix="  (default: $default_channel)"
  local available_width=$((TUI_WIDTH - 14))
  local package_width=$((available_width - ${#suffix}))

  [ "$available_width" -ge 12 ] || available_width=12
  if [ $((${#package} + ${#suffix})) -le "$available_width" ]; then
    TUI_PACKAGE_LABEL="$package$suffix"
  elif [ "$package_width" -ge 8 ]; then
    TUI_PACKAGE_LABEL="${package:0:$((package_width - 1))}…$suffix"
  else
    TUI_PACKAGE_LABEL="${package:0:$((available_width - 1))}…"
  fi
}

tui_initialize_screen() {
  local enter_alternate_screen

  tui_update_geometry
  if [ -w /dev/tty ]; then
    enter_alternate_screen=$(tput smcup 2>/dev/null || true)
    if [ -n "$enter_alternate_screen" ]; then
      (printf '%s' "$enter_alternate_screen" > /dev/tty) 2>/dev/null || true
      TUI_ALT_SCREEN_ACTIVE=true
    fi
    (printf '\033[0;37;40m\033[2J\033[H' > /dev/tty) 2>/dev/null || true
  fi
  TUI_SCREEN_INITIALIZED=true
  TUI_TERMINAL_RESTORED=false
}

tui_restore_terminal() {
  local leave_alternate_screen=""

  if [ -w /dev/tty ]; then
    if [ "$TUI_ALT_SCREEN_ACTIVE" = true ]; then
      leave_alternate_screen=$(tput rmcup 2>/dev/null || true)
    fi
    (
      printf '\033[0m\033(B\033[?1000l\033[?1006l\033[?25h'
      printf '%s' "$leave_alternate_screen"
      printf '\033[0m\033(B\033[?1000l\033[?1006l\033[?25h\033[2J\033[H'
    ) > /dev/tty 2>/dev/null || true
  fi
  TUI_ALT_SCREEN_ACTIVE=false
  TUI_TERMINAL_RESTORED=true
}

tui_prepare_terminal_profile() {
  local terminal_source

  command -v infocmp >/dev/null 2>&1 || return 0
  command -v tic >/dev/null 2>&1 || return 0
  [ -n "${TERM:-}" ] || return 0

  terminal_source="$WORK_DIR/whiptail-terminal.info"
  mkdir -p "$WORK_DIR/terminfo"
  if ! infocmp -1 "$TERM" 2>/dev/null | \
    awk '!/^[[:space:]]*(smcup|rmcup)=/' > "$terminal_source"; then
    return 0
  fi
  if ! tic -x -o "$WORK_DIR/terminfo" "$terminal_source" 2>/dev/null; then
    return 0
  fi
  TUI_TERMINFO_DIR="$WORK_DIR/terminfo"
}

tui_whiptail() {
  local whiptail_pid redraw_pid status
  local -a terminal_environment=(
    "LINES=$TUI_TERMINAL_LINES"
    "COLUMNS=$TUI_TERMINAL_COLUMNS"
  )
  [ -z "$TUI_TERMINFO_DIR" ] || terminal_environment+=("TERMINFO=$TUI_TERMINFO_DIR")
  env "${terminal_environment[@]}" whiptail --backtitle "$TUI_TITLE" "$@" <&0 &
  whiptail_pid=$!
  (
    sleep 0.05
    kill -WINCH "$whiptail_pid" 2>/dev/null || true
    sleep 0.10
    kill -WINCH "$whiptail_pid" 2>/dev/null || true
  ) &
  redraw_pid=$!

  if wait "$whiptail_pid"; then
    status=0
  else
    status=$?
  fi
  wait "$redraw_pid" 2>/dev/null || true
  return "$status"
}

run_with_progress() {
  local label=$1
  shift
  local output_file error_file query_pid status elapsed frame_index=0 percent error_text
  local -a frames=('|' '/' '-' $'\\')

  output_file=$(mktemp "$WORK_DIR/query-output.XXXXXX")
  error_file=$(mktemp "$WORK_DIR/query-error.XXXXXX")
  local started_at=$SECONDS

  "$@" >"$output_file" 2>"$error_file" &
  query_pid=$!
  trap 'kill "$query_pid" 2>/dev/null || true; wait "$query_pid" 2>/dev/null || true; exit 130' INT TERM

  if [ "$MODE" = tui ]; then
    tui_update_geometry
    (
      while kill -0 "$query_pid" 2>/dev/null; do
        percent=$((5 + frame_index))
        [ "$percent" -le 90 ] || percent=90
        printf 'XXX\n%d\n%s %s\nXXX\n' "$percent" \
          "$label" "${frames[$((frame_index % ${#frames[@]}))]}"
        frame_index=$((frame_index + 1))
        sleep 0.15
      done
      printf '100\n'
    ) 2>/dev/null | tui_whiptail --title "Loading" \
      --gauge "$label" "$TUI_INPUT_HEIGHT" "$TUI_WIDTH" 0 || true
  elif [ -t 2 ]; then
    while kill -0 "$query_pid" 2>/dev/null; do
      printf '\r[%s] %s' "${frames[$((frame_index % ${#frames[@]}))]}" "$label" >&2
      frame_index=$((frame_index + 1))
      sleep 0.15
    done
  else
    printf '%s...\n' "$label" >&2
  fi

  if wait "$query_pid"; then
    status=0
  else
    status=$?
  fi
  trap - INT TERM
  elapsed=$((SECONDS - started_at))

  if [ "$status" -eq 0 ]; then
    if [ "$MODE" = tui ]; then
      :
    elif [ -t 2 ]; then
      printf '\r\033[K[done] %s (%ss)\n' "$label" "$elapsed" >&2
    else
      printf '[done] %s (%ss)\n' "$label" "$elapsed" >&2
    fi
    QUERY_OUTPUT=$(<"$output_file")
  else
    if [ "$MODE" = tui ]; then
      error_text=$(sed 's/^/oc-mirror: /' "$error_file")
      [ -z "$error_text" ] || error_text=$'\n\n'"$error_text"
      tui_error "$label failed.$error_text"
    elif [ -t 2 ]; then
      printf '\r\033[K[failed] %s (%ss)\n' "$label" "$elapsed" >&2
    else
      printf '[failed] %s (%ss)\n' "$label" "$elapsed" >&2
    fi
    [ "$MODE" = tui ] || sed 's/^/oc-mirror: /' "$error_file" >&2
  fi

  rm -f -- "$output_file" "$error_file"
  return "$status"
}

# -----------------------------------------------------------------------------
# Catalog and OpenShift release queries
# -----------------------------------------------------------------------------

fetch_catalog() {
  local image=$1
  local output_file temporary_output
  output_file="$ORIGINAL_DIR/$(catalog_filename "$image")"
  temporary_output="$WORK_DIR/$(catalog_filename "$image")"

  echo "Processing $image -> $output_file"
  if ! run_with_progress "Loading catalog ${image##*/}" oc mirror list operators \
    --catalog="$image" \
    --version="$VERSION" \
    --v1; then
    die "Could not fetch catalog '$image'."
  fi
  printf '%s\n' "$QUERY_OUTPUT" > "$temporary_output"
  printf '\nProcessed catalog: %s on %s\n' "$image" "$(date)" >> "$temporary_output"
  [ ! -d "$output_file" ] || die "Output path '$output_file' is a directory."
  mv -f "$temporary_output" "$output_file"
}

package_metadata() {
  local image=$1
  local package=$2
  local version
  version=$(catalog_version "$image")

  if ! run_with_progress "Loading channels for $package" oc mirror list operators \
    --catalog="$image" \
    --version="$version" \
    --package="$package" \
    --v1; then
    return 1
  fi
  PACKAGE_METADATA_OUTPUT=$QUERY_OUTPUT
}

load_operator_channel_versions() {
  local image=$1
  local package=$2
  local channel=$3
  local version
  local cache_key="$image|$package|$channel"
  version=$(catalog_version "$image")

  if [[ -v CACHED_CHANNEL_VERSIONS["$cache_key"] ]]; then
    CHANNEL_VERSIONS_OUTPUT=${CACHED_CHANNEL_VERSIONS[$cache_key]}
    return 0
  fi
  if ! run_with_progress "Loading versions in $package / $channel" oc mirror list operators \
    --catalog="$image" \
    --version="$version" \
    --package="$package" \
    --channel="$channel" \
    --v1; then
    return 1
  fi
  CHANNEL_VERSIONS_OUTPUT=$(awk '
    $1 == "VERSIONS" { versions = 1; next }
    versions && NF { print $1 }
  ' <<< "$QUERY_OUTPUT")
  [ -n "$CHANNEL_VERSIONS_OUTPUT" ] || return 1
  CACHED_CHANNEL_VERSIONS["$cache_key"]=$CHANNEL_VERSIONS_OUTPUT
}

load_tui_operator_versions() {
  local catalog_image=$1
  local package=$2
  local channel=$3

  if ! load_operator_channel_versions "$catalog_image" "$package" "$channel"; then
    return 1
  fi
  mapfile -t TUI_OPERATOR_VERSIONS < <(
    printf '%s\n' "$CHANNEL_VERSIONS_OUTPUT" | awk 'NF && !seen[$0]++'
  )
  [ "${#TUI_OPERATOR_VERSIONS[@]}" -gt 0 ]
}

default_channel_from_metadata() {
  awk '
    $1 == "NAME" && $2 == "DISPLAY" { summary = 1; next }
    summary && NF { print $NF; exit }
  '
}

channel_exists_in_metadata() {
  local channel=$1
  awk -v wanted="$channel" '
    $1 == "PACKAGE" && $2 == "CHANNEL" { channels = 1; next }
    channels && $2 == wanted { found = 1 }
    END { exit(found ? 0 : 1) }
  '
}

available_catalogs() {
  local version=${1:-$VERSION}
  local catalog
  for catalog in "${KNOWN_CATALOGS[@]}"; do
    catalog_image "$catalog" "$version"
  done
}

load_catalog_package_defaults() {
  local image=$1
  local version
  version=$(catalog_version "$image")

  if [[ -v CACHED_CATALOG_PACKAGE_DEFAULTS["$image"] ]]; then
    CATALOG_PACKAGE_DEFAULTS_OUTPUT=${CACHED_CATALOG_PACKAGE_DEFAULTS[$image]}
    [ "$MODE" = tui ] || echo "Using cached packages for ${image##*/}." >&2
    return
  fi

  if ! run_with_progress "Loading packages from ${image##*/}" oc mirror list operators \
    --catalog="$image" \
    --version="$version" \
    --v1; then
    return 1
  fi

  CATALOG_PACKAGE_DEFAULTS_OUTPUT=$(awk '
      $1 == "NAME" && $2 == "DISPLAY" { packages = 1; next }
      packages && NF { printf "%s\t%s\n", $1, $NF }
    ' <<< "$QUERY_OUTPUT")
  CACHED_CATALOG_PACKAGE_DEFAULTS["$image"]=$CATALOG_PACKAGE_DEFAULTS_OUTPUT
}

available_channels_from_metadata() {
  awk '
    $1 == "PACKAGE" && $2 == "CHANNEL" { channels = 1; next }
    channels && NF { print $2 }
  '
}

channel_head_from_metadata() {
  local channel=$1
  awk -v wanted="$channel" '
    $1 == "PACKAGE" && $2 == "CHANNEL" { channels = 1; next }
    channels && $2 == wanted {
      prefix = $1 ".v"
      if (index($3, prefix) == 1) {
        print substr($3, length(prefix) + 1)
      } else {
        print $3
      }
      exit
    }
  '
}

operator_channel_key() {
  OPERATOR_CHANNEL_KEY="$1|$2|$3"
}

set_operator_channel_version_bounds() {
  local catalog=$1
  local package=$2
  local channel=$3
  local minimum=${4:-}
  local maximum=${5:-}

  operator_channel_key "$catalog" "$package" "$channel"
  if [ -n "$minimum" ]; then
    TUI_OPERATOR_CHANNEL_MIN_VERSIONS["$OPERATOR_CHANNEL_KEY"]=$minimum
  else
    unset 'TUI_OPERATOR_CHANNEL_MIN_VERSIONS[$OPERATOR_CHANNEL_KEY]'
  fi
  if [ -n "$maximum" ]; then
    TUI_OPERATOR_CHANNEL_MAX_VERSIONS["$OPERATOR_CHANNEL_KEY"]=$maximum
  else
    unset 'TUI_OPERATOR_CHANNEL_MAX_VERSIONS[$OPERATOR_CHANNEL_KEY]'
  fi
}

set_operator_channel_exact_version() {
  set_operator_channel_version_bounds "$1" "$2" "$3" "$4" "$4"
}

clear_operator_channel_versions() {
  local catalog=$1
  local package=${2:-}
  local prefix="$catalog|"
  local constraint_key

  [ -z "$package" ] || prefix+="$package|"
  for constraint_key in "${!TUI_OPERATOR_CHANNEL_MIN_VERSIONS[@]}"; do
    [[ "$constraint_key" == "$prefix"* ]] || continue
    unset 'TUI_OPERATOR_CHANNEL_MIN_VERSIONS[$constraint_key]'
  done
  for constraint_key in "${!TUI_OPERATOR_CHANNEL_MAX_VERSIONS[@]}"; do
    [[ "$constraint_key" == "$prefix"* ]] || continue
    unset 'TUI_OPERATOR_CHANNEL_MAX_VERSIONS[$constraint_key]'
  done
}

operator_channel_label() {
  local catalog=$1
  local package=$2
  local channel=$3
  local minimum maximum

  operator_channel_key "$catalog" "$package" "$channel"
  minimum=${TUI_OPERATOR_CHANNEL_MIN_VERSIONS[$OPERATOR_CHANNEL_KEY]:-}
  maximum=${TUI_OPERATOR_CHANNEL_MAX_VERSIONS[$OPERATOR_CHANNEL_KEY]:-}
  OPERATOR_CHANNEL_LABEL=$channel
  if [ -n "$minimum" ] && [ "$minimum" = "$maximum" ]; then
    OPERATOR_CHANNEL_LABEL+=" @ $minimum"
  elif [ -n "$minimum" ] || [ -n "$maximum" ]; then
    OPERATOR_CHANNEL_LABEL+=" (${minimum:-start} — ${maximum:-head})"
  fi
}

load_release_channel_ranges() {
  local version=$1
  local architecture_filter=$2
  local cache_key="$version|$architecture_filter"
  local channel releases minimum maximum architecture release_architecture
  local -a channels=() range_lines=() selected_architectures=()

  if [[ -v CACHED_RELEASE_CHANNEL_RANGES["$cache_key"] ]]; then
    RELEASE_CHANNEL_RANGES=${CACHED_RELEASE_CHANNEL_RANGES[$cache_key]}
    [ "$MODE" = tui ] || echo "Using cached release channels for OpenShift $version ($architecture_filter)." >&2
    return
  fi

  if ! run_with_progress "Loading release channels for OpenShift $version" oc mirror list releases \
    --version="$version" \
    --channels \
    --v2; then
    return 1
  fi
  while IFS= read -r channel; do
    [[ "$channel" =~ ^[a-z0-9.-]+-$version$ ]] && channels+=("$channel")
  done <<< "$QUERY_OUTPUT"
  [ "${#channels[@]}" -gt 0 ] || return 1

  for channel in "${channels[@]}"; do
    if ! run_with_progress "Loading release range for $channel" oc mirror list releases \
      --channel="$channel" \
      --version="$version" \
      --filter-by-archs="$architecture_filter" \
      --v2; then
      continue
    fi
    releases=$(awk '/^[0-9]+\.[0-9]+\.[0-9]+([.-][a-zA-Z0-9]+)*$/ { print }' <<< "$QUERY_OUTPUT" | sort -Vu)
    [ -n "$releases" ] || continue
    minimum=$(head -n1 <<< "$releases")
    maximum=$(tail -n1 <<< "$releases")
    range_lines+=("$channel|$minimum|$maximum")
    IFS=',' read -r -a selected_architectures <<< "$architecture_filter"
    for architecture in "${selected_architectures[@]}"; do
      release_architecture=$(release_metadata_architecture "$architecture") || continue
      CACHED_CURRENT_RELEASES["$release_architecture|$channel"]=$maximum
    done
  done
  [ "${#range_lines[@]}" -gt 0 ] || return 1

  printf -v RELEASE_CHANNEL_RANGES '%s\n' "${range_lines[@]}"
  RELEASE_CHANNEL_RANGES=${RELEASE_CHANNEL_RANGES%$'\n'}
  CACHED_RELEASE_CHANNEL_RANGES["$cache_key"]=$RELEASE_CHANNEL_RANGES
}

release_metadata_architecture() {
  case "$1" in
    amd64|multi) printf '%s\n' x86_64 ;;
    arm64) printf '%s\n' aarch64 ;;
    ppc64le|s390x) printf '%s\n' "$1" ;;
    *) return 1 ;;
  esac
}

resolve_current_release() {
  local channel=$1
  local platform_architecture=$2
  local release_architecture cache_key version release_version releases

  [[ "$channel" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || return 1
  release_architecture=$(release_metadata_architecture "$platform_architecture") || return 1
  cache_key="$release_architecture|$channel"
  if [[ -v CACHED_CURRENT_RELEASES["$cache_key"] ]]; then
    RESOLVED_CURRENT_RELEASE=${CACHED_CURRENT_RELEASES[$cache_key]}
    RESOLVED_CURRENT_RELEASE_ARCH=$release_architecture
    return 0
  fi

  if [[ "$channel" =~ -([0-9]+\.[0-9]+)$ ]]; then
    version=${BASH_REMATCH[1]}
  else
    return 1
  fi
  if ! run_with_progress "Resolving the current release for $channel" oc mirror list releases \
    --channel="$channel" \
    --version="$version" \
    --filter-by-archs="$platform_architecture" \
    --v2; then
    return 1
  fi
  releases=$(awk '/^[0-9]+\.[0-9]+\.[0-9]+([.-][a-zA-Z0-9]+)*$/ { print }' \
    <<< "$QUERY_OUTPUT" | sort -Vu)
  release_version=$(tail -n1 <<< "$releases")
  [ -n "$release_version" ] || return 1
  validate_release_version "$release_version" || return 1

  CACHED_CURRENT_RELEASES["$cache_key"]=$release_version
  RESOLVED_CURRENT_RELEASE=$release_version
  RESOLVED_CURRENT_RELEASE_ARCH=$release_architecture
}

# -----------------------------------------------------------------------------
# Reusable dialogs and scrolling previews
# -----------------------------------------------------------------------------

parse_number_selection() {
  local input=${1//[[:space:]]/}
  local maximum=$2
  local token start end number index
  local -A seen=()
  local -a tokens=()
  SELECTED_INDICES=()

  IFS=',' read -r -a tokens <<< "$input"
  for token in "${tokens[@]}"; do
    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start=$((10#${BASH_REMATCH[1]}))
      end=$((10#${BASH_REMATCH[2]}))
      [ "$start" -le "$end" ] || { echo "Invalid descending range: $token" >&2; return 1; }
    elif [[ "$token" =~ ^[0-9]+$ ]]; then
      start=$((10#$token))
      end=$start
    else
      echo "Invalid selection: $token" >&2
      return 1
    fi

    for ((number = start; number <= end; number++)); do
      [ "$number" -ge 1 ] && [ "$number" -le "$maximum" ] || {
        echo "Selection $number is outside 1-$maximum." >&2
        return 1
      }
      index=$((number - 1))
      if [[ ! -v seen["$index"] ]]; then
        SELECTED_INDICES+=("$index")
        seen["$index"]=1
      fi
    done
  done
  [ "${#SELECTED_INDICES[@]}" -gt 0 ]
}

choose_one() {
  local prompt=$1
  shift
  local -a options=("$@")
  local selection index menu_height
  local -a menu_items=()

  tui_update_geometry

  for index in "${!options[@]}"; do
    menu_items+=("$((index + 1))" "${options[$index]}")
  done
  menu_height=${#options[@]}
  [ "$menu_height" -le "$TUI_LIST_HEIGHT" ] || menu_height=$TUI_LIST_HEIGHT
  if ! selection=$(tui_whiptail --title "$TUI_TITLE" \
    --ok-button "Enter: Select" --cancel-button "Esc: Back" \
    --menu "$prompt" "$TUI_HEIGHT" "$TUI_WIDTH" "$menu_height" \
    "${menu_items[@]}" 3>&1 1>&2 2>&3); then
    return 1
  fi
  CHOSEN_VALUE=${options[$((10#$selection - 1))]}
}

tui_input() {
  local prompt=$1
  local default_value=${2:-}

  tui_update_geometry

  if ! TUI_VALUE=$(tui_whiptail --title "$TUI_TITLE" \
    --ok-button "Enter: Continue" --cancel-button "Esc: Back" \
    --inputbox "$prompt" "$TUI_INPUT_HEIGHT" "$TUI_WIDTH" "$default_value" 3>&1 1>&2 2>&3); then
    return 1
  fi
}

choose_tui_version() {
  local prompt=$1
  local default_version=${2:-$VERSION}

  while true; do
    if ! tui_input "$prompt" "$default_version"; then
      return 1
    fi
    if [[ "$TUI_VALUE" =~ ^[0-9]+\.[0-9]+$ ]]; then
      TUI_SELECTED_VERSION=$TUI_VALUE
      return 0
    fi
    tui_error "Version must use major.minor format, such as 4.20."
    default_version=$TUI_VALUE
  done
}

tui_close_scroll_viewer() {
  printf '\033[?1000l\033[?1006l\033[?25h\033[2J\033[H' >&2
}

tui_scroll_viewer() {
  local title=$1
  local message=$2
  local action=${3:-Close}
  local viewport_height content_width inner_width line_count maximum_top maximum_left
  local window_top window_left right_column
  local top=0 left=0 row screen_row line_index visible_line status_line help_line border
  local key next_key final_key mouse_sequence max_line_length=0
  local -a viewer_lines=()

  tui_update_geometry
  viewport_height=$((TUI_HEIGHT - 5))
  [ "$viewport_height" -ge 3 ] || viewport_height=3
  inner_width=$((TUI_WIDTH - 2))
  content_width=$((TUI_WIDTH - 4))
  [ "$content_width" -ge 18 ] || content_width=18
  window_top=$(((TUI_TERMINAL_LINES - TUI_HEIGHT) / 2 + 1))
  window_left=$(((TUI_TERMINAL_COLUMNS - TUI_WIDTH) / 2 + 1))
  [ "$window_top" -ge 1 ] || window_top=1
  [ "$window_left" -ge 1 ] || window_left=1
  right_column=$((window_left + TUI_WIDTH - 1))
  printf -v border '%*s' "$inner_width" ""
  border=${border// /-}
  mapfile -t viewer_lines <<< "$message"
  [ "${#viewer_lines[@]}" -gt 0 ] || viewer_lines=("")
  line_count=${#viewer_lines[@]}
  maximum_top=$((line_count - viewport_height))
  [ "$maximum_top" -ge 0 ] || maximum_top=0
  for visible_line in "${viewer_lines[@]}"; do
    [ "${#visible_line}" -le "$max_line_length" ] || max_line_length=${#visible_line}
  done
  maximum_left=$((max_line_length - content_width))
  [ "$maximum_left" -ge 0 ] || maximum_left=0
  printf '\033[?25l\033[?1000h\033[?1006h' >&2

  while true; do
    {
      printf '\033[0;37;40m\033[2J\033[H'
      printf '\033[1;36m%s\033[0;37;40m' "${TUI_TITLE:0:$TUI_TERMINAL_COLUMNS}"
      printf '\033[%d;%dH+%s+' "$window_top" "$window_left" "$border"
      screen_row=$((window_top + 1))
      printf '\033[%d;%dH%-*s' "$screen_row" "$((window_left + 1))" "$inner_width" ""
      printf '\033[%d;%dH\033[1;36m%s\033[0;37;40m' \
        "$screen_row" "$((window_left + 2))" "${title:0:$content_width}"
      printf '\033[%d;%dH|\033[%d;%dH|' \
        "$screen_row" "$window_left" "$screen_row" "$right_column"
      for ((row = 0; row < viewport_height; row++)); do
        screen_row=$((window_top + 2 + row))
        line_index=$((top + row))
        if [ "$line_index" -lt "$line_count" ]; then
          visible_line=${viewer_lines[$line_index]:$left:$content_width}
        else
          visible_line=""
        fi
        printf '\033[%d;%dH%-*s' "$screen_row" "$((window_left + 1))" "$inner_width" ""
        printf '\033[%d;%dH%s' "$screen_row" "$((window_left + 2))" "$visible_line"
        printf '\033[%d;%dH|\033[%d;%dH|' \
          "$screen_row" "$window_left" "$screen_row" "$right_column"
      done
      status_line="Lines $((top + 1))-$((top + viewport_height < line_count ? top + viewport_height : line_count))/$line_count"
      [ "$maximum_left" -eq 0 ] || status_line+="  Column $((left + 1))"
      screen_row=$((window_top + TUI_HEIGHT - 3))
      printf '\033[%d;%dH%-*s' "$screen_row" "$((window_left + 1))" "$inner_width" ""
      printf '\033[%d;%dH\033[1;36m%s\033[0;37;40m' \
        "$screen_row" "$((window_left + 2))" "${status_line:0:$content_width}"
      printf '\033[%d;%dH|\033[%d;%dH|' \
        "$screen_row" "$window_left" "$screen_row" "$right_column"
      help_line="Wheel/Up/Down PgUp/PgDn Home/End"
      [ "$maximum_left" -eq 0 ] || help_line+="  Left/Right horizontal"
      help_line+="  Enter: $action  Esc: Back"
      screen_row=$((window_top + TUI_HEIGHT - 2))
      printf '\033[%d;%dH%-*s' "$screen_row" "$((window_left + 1))" "$inner_width" ""
      printf '\033[%d;%dH%s' \
        "$screen_row" "$((window_left + 2))" "${help_line:0:$content_width}"
      printf '\033[%d;%dH|\033[%d;%dH|' \
        "$screen_row" "$window_left" "$screen_row" "$right_column"
      printf '\033[%d;%dH+%s+' "$((window_top + TUI_HEIGHT - 1))" "$window_left" "$border"
    } >&2

    key=""
    if ! IFS= read -rsn1 key <&0; then
      tui_close_scroll_viewer
      return 1
    fi
    case "$key" in
      "")
        tui_close_scroll_viewer
        return 0
        ;;
      k) if [ "$top" -gt 0 ]; then top=$((top - 1)); fi ;;
      j) if [ "$top" -lt "$maximum_top" ]; then top=$((top + 1)); fi ;;
      $'\033')
        next_key=""
        if ! IFS= read -rsn1 -t 0.1 next_key <&0; then
          tui_close_scroll_viewer
          return 1
        fi
        if [ "$next_key" != "[" ] && [ "$next_key" != O ]; then
          tui_close_scroll_viewer
          return 1
        fi
        final_key=""
        IFS= read -rsn1 -t 0.1 final_key <&0 || continue
        case "$final_key" in
          A) if [ "$top" -gt 0 ]; then top=$((top - 1)); fi ;;
          B) if [ "$top" -lt "$maximum_top" ]; then top=$((top + 1)); fi ;;
          C) [ "$left" -lt "$maximum_left" ] && left=$((left + 4)); [ "$left" -le "$maximum_left" ] || left=$maximum_left ;;
          D) [ "$left" -gt 0 ] && left=$((left - 4)); [ "$left" -ge 0 ] || left=0 ;;
          H) top=0 ;;
          F) top=$maximum_top ;;
          1|4|5|6)
            next_key=""
            IFS= read -rsn1 -t 0.1 next_key <&0 || true
            case "$final_key" in
              1) top=0 ;;
              4) top=$maximum_top ;;
              5) top=$((top - viewport_height)); [ "$top" -ge 0 ] || top=0 ;;
              6) top=$((top + viewport_height)); [ "$top" -le "$maximum_top" ] || top=$maximum_top ;;
            esac
            ;;
          '<')
            mouse_sequence=""
            while IFS= read -rsn1 -t 0.1 next_key <&0; do
              mouse_sequence+=$next_key
              [[ "$next_key" = M || "$next_key" = m ]] && break
            done
            case "$mouse_sequence" in
              64\;*M)
                top=$((top - 3))
                [ "$top" -ge 0 ] || top=0
                ;;
              65\;*M)
                top=$((top + 3))
                [ "$top" -le "$maximum_top" ] || top=$maximum_top
                ;;
            esac
            ;;
        esac
        ;;
    esac
  done
}

tui_message() {
  local title=$1
  local message=$2
  local action=${3:-Close}
  local display_lines height status=0

  tui_update_geometry
  display_lines=$(awk -v width="$((TUI_WIDTH - 10))" \
    '{ lines += int(length($0) / width) + 1 } END { print lines }' <<< "$message")
  if [ "$display_lines" -le $((TUI_HEIGHT - 7)) ]; then
    height=$((display_lines + 7))
    [ "$height" -ge 12 ] || height=12
    [ "$height" -le "$TUI_HEIGHT" ] || height=$TUI_HEIGHT
    tui_whiptail --title "$title" --ok-button "Enter: $action" \
      --msgbox "$message" "$height" "$TUI_WIDTH" || status=$?
  else
    tui_scroll_viewer "$title" "$message" "$action" || status=$?
  fi
  if [ "$status" -ne 0 ] && [ "$action" != Close ]; then
    return 1
  fi
  return 0
}

tui_error() {
  local message=$1
  tui_update_geometry
  tui_whiptail --title "Error" --ok-button "Enter: Close" \
    --msgbox "$message" "$TUI_INPUT_HEIGHT" "$TUI_WIDTH" || true
}

choose_many() {
  local prompt=$1
  local default_selection=$2
  shift 5
  local -a options=("$@")
  local selection index selected_index status checklist_height
  local -a checklist_items=()
  local -A defaults=()
  CHOSEN_VALUES=()

  tui_update_geometry
  prompt+=$'\n\n'"Space: select or clear items  •  Enter: apply selection"
  checklist_height=$((TUI_LIST_HEIGHT - 2))
  [ "$checklist_height" -ge 4 ] || checklist_height=4

  if [ -n "$default_selection" ] && parse_number_selection "$default_selection" "${#options[@]}"; then
    for selected_index in "${SELECTED_INDICES[@]}"; do
      defaults["$selected_index"]=1
    done
  fi
  for index in "${!options[@]}"; do
    status=OFF
    [[ -v defaults["$index"] ]] && status=ON
    checklist_items+=("$((index + 1))" "${options[$index]}" "$status")
  done

  while true; do
    if ! selection=$(tui_whiptail --title "$TUI_TITLE" --separate-output \
      --ok-button "Enter: Apply" --cancel-button "Esc: Back" \
      --checklist "$prompt" "$TUI_HEIGHT" "$TUI_WIDTH" "$checklist_height" \
      "${checklist_items[@]}" 3>&1 1>&2 2>&3); then
      return 1
    fi
    [ -n "$selection" ] && break
    tui_error "Select at least one item before continuing."
  done
  while IFS= read -r selected_index; do
    [ -n "$selected_index" ] || continue
    CHOSEN_VALUES+=("${options[$((10#$selected_index - 1))]}")
  done <<< "$selection"
}

edit_tui_package_matches() {
  local selected_map_name=$1
  local prompt=$2
  local catalog_image=$3
  shift 3
  local -a packages=("$@") checklist_items=()
  local -n selected_map=$selected_map_name
  local package index status selection default_channel package_label checklist_height

  tui_update_geometry
  prompt+=$'\n\n'"Space: select or clear packages  •  Enter: apply selection"
  checklist_height=$((TUI_LIST_HEIGHT - 2))
  [ "$checklist_height" -ge 4 ] || checklist_height=4

  for index in "${!packages[@]}"; do
    package=${packages[$index]}
    status=OFF
    [[ -v selected_map["$package"] ]] && status=ON
    default_channel=${CACHED_DEFAULT_CHANNELS["$catalog_image|$package"]:-unknown}
    tui_package_label "$package" "$default_channel"
    package_label=$TUI_PACKAGE_LABEL
    checklist_items+=("$((index + 1))" "$package_label" "$status")
  done
  if ! selection=$(tui_whiptail --title "$TUI_TITLE" --separate-output \
    --ok-button "Enter: Apply" --cancel-button "Esc: Back" \
    --checklist "$prompt" "$TUI_HEIGHT" "$TUI_WIDTH" "$checklist_height" \
    "${checklist_items[@]}" 3>&1 1>&2 2>&3); then
    return 1
  fi

  for package in "${packages[@]}"; do
    unset "selected_map[$package]"
  done
  while IFS= read -r index; do
    [ -n "$index" ] || continue
    package=${packages[$((10#$index - 1))]}
    selected_map["$package"]=1
  done <<< "$selection"
}

# -----------------------------------------------------------------------------
# Operator package, channel, and version workflows
# -----------------------------------------------------------------------------

load_tui_package_metadata() {
  local catalog_image=$1
  local package=$2
  local cache_key="$catalog_image|$package"

  if [[ -v CACHED_PACKAGE_METADATA["$cache_key"] ]]; then
    TUI_PACKAGE_METADATA=${CACHED_PACKAGE_METADATA[$cache_key]}
    return
  fi
  if ! package_metadata "$catalog_image" "$package"; then
    return 1
  fi
  TUI_PACKAGE_METADATA=$PACKAGE_METADATA_OUTPUT
  CACHED_PACKAGE_METADATA["$cache_key"]=$TUI_PACKAGE_METADATA
}

load_tui_catalog_packages() {
  local catalog_image=$1
  local package default_channel

  TUI_CATALOG_PACKAGES=()
  if ! load_catalog_package_defaults "$catalog_image"; then
    tui_error "Could not query packages in '$catalog_image'."
    return 1
  fi
  while IFS=$'\t' read -r package default_channel; do
    [ -n "$package" ] || continue
    if [ -z "$default_channel" ]; then
      tui_error "Catalog data did not include a default channel for '$package'."
      return 1
    fi
    TUI_CATALOG_PACKAGES+=("$package")
    CACHED_DEFAULT_CHANNELS["$catalog_image|$package"]=$default_channel
  done <<< "$CATALOG_PACKAGE_DEFAULTS_OUTPUT"
  if [ "${#TUI_CATALOG_PACKAGES[@]}" -eq 0 ]; then
    tui_error "No packages were found in '$catalog_image'."
    return 1
  fi
  mapfile -t TUI_CATALOG_PACKAGES < <(
    printf '%s\n' "${TUI_CATALOG_PACKAGES[@]}" | sort
  )
}

# -----------------------------------------------------------------------------
# Curated Operator groups
#
# Flow:
#   add_tui_operator_group
#     -> load_operator_group_definition  (resolve the named bundle)
#     -> load/filter catalog packages    (remove unavailable entries)
#     -> review checklist                (user confirms packages)
#     -> merge_tui_operator_group_packages (preserve and extend TUI state)
# -----------------------------------------------------------------------------

odf_operator_bundle_url() {
  local version=$1
  local placeholder='{version}'
  printf '%s\n' "${ODF_OPERATOR_BUNDLE//$placeholder/$version}"
}

# Extract only <code> values in the core ODF package section. Stopping at the
# Local Storage heading keeps conditional packages out of the default set.
odf_packages_from_html() {
  sed 's/></>\n</g' | awk '
    /Packages to include for OpenShift Data Foundation/ {
      in_package_section = 1
      next
    }
    in_package_section && /Only for local storage deployments/ {
      exit
    }
    in_package_section {
      remaining = $0
      while (match(remaining, /<code[^>]*>[^<]+<\/code>/)) {
        value = substr(remaining, RSTART, RLENGTH)
        sub(/^<code[^>]*>/, "", value)
        sub(/<\/code>$/, "", value)
        if (value != "redhat-operator" &&
            value ~ /^[a-z0-9][a-z0-9.-]*$/ &&
            !seen[value]++) {
          print value
        }
        remaining = substr(remaining, RSTART + RLENGTH)
      }
    }
  '
}

# curl is optional. An empty response deliberately falls through to the
# version-independent fallback bundle rather than blocking the TUI.
fetch_url_quietly() {
  curl -fsSL --connect-timeout 10 --max-time 30 "$1" 2>/dev/null || true
}

load_odf_operator_bundle() {
  local version=$1
  local docs_url
  local -a scraped_packages=()

  docs_url=$(odf_operator_bundle_url "$version")
  ODF_OPERATOR_PACKAGES=()
  ODF_OPERATOR_PACKAGE_SOURCE="built-in fallback"

  if command -v curl >/dev/null 2>&1; then
    run_with_progress "Checking ODF $version deployment packages" \
      fetch_url_quietly "$docs_url"
    mapfile -t scraped_packages < <(odf_packages_from_html <<< "$QUERY_OUTPUT")
  fi
  if [ "${#scraped_packages[@]}" -gt 0 ]; then
    ODF_OPERATOR_PACKAGES=("${scraped_packages[@]}")
    ODF_OPERATOR_PACKAGE_SOURCE="Red Hat ODF $version documentation"
  else
    ODF_OPERATOR_PACKAGES=("${ODF_OPERATOR_BUNDLE_FALLBACK[@]}")
  fi
  ODF_OPERATOR_DOCS_URL=$docs_url
}

# Registration point 3: map every group-menu label to its package arrays.
#
# OPERATOR_GROUP_PACKAGES          packages displayed in the checklist
# OPERATOR_GROUP_DEFAULT_PACKAGES  packages initially checked
# OPERATOR_GROUP_SOURCE            source shown to the user
# OPERATOR_GROUP_PROMPT            group-specific checklist guidance
load_operator_group_definition() {
  local group=$1
  local version=$2

  OPERATOR_GROUP_PACKAGES=()
  OPERATOR_GROUP_DEFAULT_PACKAGES=()
  OPERATOR_GROUP_SOURCE="built-in bundle"
  OPERATOR_GROUP_PROMPT="All available packages are selected."

  case "$group" in
    "OpenShift Data Foundation")
      load_odf_operator_bundle "$version"
      OPERATOR_GROUP_PACKAGES=(
        "${ODF_OPERATOR_PACKAGES[@]}"
        "${ODF_LOCALSTORAGE_OPERATOR_BUNDLE[@]}"
        "${ODF_DR_OPERATOR_BUNDLE[@]}"
      )
      OPERATOR_GROUP_DEFAULT_PACKAGES=("${ODF_OPERATOR_PACKAGES[@]}")
      OPERATOR_GROUP_SOURCE=$ODF_OPERATOR_PACKAGE_SOURCE
      OPERATOR_GROUP_PROMPT="Core ODF packages are selected. Local Storage/Disaster Recovery packages are optional"
      ;;
    "OpenShift Virtualization")
      OPERATOR_GROUP_PACKAGES=("${VIRT_OPERATOR_BUNDLE[@]}")
      OPERATOR_GROUP_DEFAULT_PACKAGES=("${VIRT_OPERATOR_BUNDLE[@]}")
      ;;
    "Advanced Cluster Management")
      OPERATOR_GROUP_PACKAGES=("${ACM_OPERATOR_BUNDLE[@]}")
      OPERATOR_GROUP_DEFAULT_PACKAGES=("${ACM_OPERATOR_BUNDLE[@]}")
      ;;
    "Operations")
      OPERATOR_GROUP_PACKAGES=("${OPERATIONS_OPERATOR_BUNDLE[@]}")
      OPERATOR_GROUP_DEFAULT_PACKAGES=("${OPERATIONS_OPERATOR_BUNDLE[@]}")
      ;;
    "Security")
      OPERATOR_GROUP_PACKAGES=("${SECURITY_OPERATOR_BUNDLE[@]}")
      OPERATOR_GROUP_DEFAULT_PACKAGES=("${SECURITY_OPERATOR_BUNDLE[@]}")
      ;;
    "Logging")
      OPERATOR_GROUP_PACKAGES=("${LOGGING_OPERATOR_BUNDLE[@]}")
      OPERATOR_GROUP_DEFAULT_PACKAGES=("${LOGGING_OPERATOR_BUNDLE[@]}")
      ;;
    "Local Storage")
      OPERATOR_GROUP_PACKAGES=("${LOCALSTORAGE_OPERATOR_BUNDLE[@]}")
      OPERATOR_GROUP_DEFAULT_PACKAGES=("${LOCALSTORAGE_OPERATOR_BUNDLE[@]}")
      ;;
    *)
      return 1
      ;;
  esac
}

# This function only classifies requested packages. It does not modify the
# current image-set selections.
filter_tui_operator_group_packages() {
  local requested_name=$1
  local defaults_name=$2
  local found_name=$3
  local missing_name=$4
  local selected_name=$5
  local -n requested=$requested_name
  local -n defaults=$defaults_name
  local -n found=$found_name
  local -n missing=$missing_name
  local -n selected=$selected_name
  local package
  local -A catalog_packages=() default_packages=() seen=()

  found=()
  missing=()
  selected=()
  for package in "${TUI_CATALOG_PACKAGES[@]}"; do
    catalog_packages["$package"]=1
  done
  for package in "${defaults[@]}"; do
    default_packages["$package"]=1
  done
  for package in "${requested[@]}"; do
    [[ -v seen["$package"] ]] && continue
    seen["$package"]=1
    if [[ -v catalog_packages["$package"] ]]; then
      found+=("$package")
      [[ -v default_packages["$package"] ]] && selected["$package"]=1
    else
      missing+=("$package")
    fi
  done
}

# Merge new default-channel specs into the selected catalog without changing
# any existing package, channel, or exact-version constraints.
merge_tui_operator_group_packages() {
  local catalog_image=$1
  shift
  local -a chosen_packages=("$@") existing_specs=() merged_specs=()
  local specs_text spec package cache_key
  local -A existing_packages=() processed_packages=()

  OPERATOR_GROUP_ADDED_COUNT=0
  OPERATOR_GROUP_EXISTING_COUNT=0
  specs_text=${TUI_CATALOG_PACKAGE_SPECS[$catalog_image]:-}
  while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    existing_specs+=("$spec")
    existing_packages["${spec%%:*}"]=1
  done <<< "$specs_text"
  merged_specs=("${existing_specs[@]}")

  for package in "${chosen_packages[@]}"; do
    [[ -v processed_packages["$package"] ]] && continue
    processed_packages["$package"]=1
    if [[ -v existing_packages["$package"] ]]; then
      OPERATOR_GROUP_EXISTING_COUNT=$((OPERATOR_GROUP_EXISTING_COUNT + 1))
      continue
    fi
    cache_key="$catalog_image|$package"
    merged_specs+=("$package:${CACHED_DEFAULT_CHANNELS[$cache_key]}")
    existing_packages["$package"]=1
    OPERATOR_GROUP_ADDED_COUNT=$((OPERATOR_GROUP_ADDED_COUNT + 1))
  done

  printf -v specs_text '%s\n' "${merged_specs[@]}"
  TUI_CATALOG_PACKAGE_SPECS["$catalog_image"]=${specs_text%$'\n'}
  TUI_WHOLE_CATALOG["$catalog_image"]=false
}

add_tui_operator_group() {
  local selected_version group catalog_image package missing_text summary_text
  local specs_text spec
  local catalog_selected=false
  # Registration point 2: add the user-facing group name here. The spelling
  # must exactly match its case entry in load_operator_group_definition().
  local -a groups=(
    "OpenShift Data Foundation"
    "OpenShift Virtualization"
    "Advanced Cluster Management"
    "Operations"
    "Security"
    "Logging"
    "Local Storage"
  )
  local -a available_packages=() missing_packages=() chosen_packages=()
  local -A selected_packages=()

  if ! choose_tui_version "OpenShift version for the Operator group:" "$VERSION"; then
    return 1
  fi
  selected_version=$TUI_SELECTED_VERSION
  if ! choose_one "Choose an Operator group for OpenShift $selected_version:" \
    "${groups[@]}"; then
    return 1
  fi
  group=$CHOSEN_VALUE
  catalog_image=$(catalog_image redhat-operator-index "$selected_version")

  if [ "${TUI_WHOLE_CATALOG[$catalog_image]:-false}" = true ]; then
    tui_message "Operator group already included" \
      "$catalog_image already includes the entire catalog, so every package in the $group group is already present."
    return 0
  fi

  load_operator_group_definition "$group" "$selected_version" || return 1
  load_tui_catalog_packages "$catalog_image" || return 1
  filter_tui_operator_group_packages \
    OPERATOR_GROUP_PACKAGES OPERATOR_GROUP_DEFAULT_PACKAGES \
    available_packages missing_packages selected_packages

  if [ "${#available_packages[@]}" -eq 0 ]; then
    tui_error "None of the packages in $group were found in ${catalog_image##*/}."
    return 1
  fi
  specs_text=${TUI_CATALOG_PACKAGE_SPECS[$catalog_image]:-}
  while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    selected_packages["${spec%%:*}"]=1
  done <<< "$specs_text"
  if ! edit_tui_package_matches selected_packages \
    "$group for OpenShift $selected_version\nPackage source: $OPERATOR_GROUP_SOURCE\n\n$OPERATOR_GROUP_PROMPT\nExisting catalog selections will be preserved." \
    "$catalog_image" "${available_packages[@]}"; then
    return 1
  fi
  for package in "${available_packages[@]}"; do
    [[ -v selected_packages["$package"] ]] && chosen_packages+=("$package")
  done
  if [ "${#chosen_packages[@]}" -eq 0 ]; then
    tui_error "Select at least one package to add from $group."
    return 1
  fi

  for package in "${TUI_CATALOG_IMAGES[@]}"; do
    [ "$package" != "$catalog_image" ] || catalog_selected=true
  done
  merge_tui_operator_group_packages "$catalog_image" "${chosen_packages[@]}"
  TUI_CATALOG_VERSIONS["$catalog_image"]=$selected_version
  [ "$catalog_selected" = true ] || TUI_CATALOG_IMAGES+=("$catalog_image")

  summary_text="Group: $group\nCatalog: $catalog_image\nPackage source: $OPERATOR_GROUP_SOURCE\n\nAdded packages: $OPERATOR_GROUP_ADDED_COUNT\nAlready selected: $OPERATOR_GROUP_EXISTING_COUNT"
  if [ "${#missing_packages[@]}" -gt 0 ]; then
    missing_text=""
    for package in "${missing_packages[@]}"; do
      missing_text+=$'\n'"  • $package"
    done
    summary_text+=$'\n'"Unavailable in this catalog: ${#missing_packages[@]}$missing_text"
  fi
  tui_message "Operator group added" "$summary_text"
}

choose_tui_operator_channel_version() {
  local catalog_image=$1
  local package=$2
  local channel=$3
  local metadata=$4
  local pending_mins_name=$5
  local pending_maxes_name=$6
  local -n pending_mins=$pending_mins_name
  local -n pending_maxes=$pending_maxes_name
  local constraint_key existing_min existing_max channel_head head_label
  local keep_version_label="" version_choice selected_version

  operator_channel_key "$catalog_image" "$package" "$channel"
  constraint_key=$OPERATOR_CHANNEL_KEY
  existing_min=${TUI_OPERATOR_CHANNEL_MIN_VERSIONS[$constraint_key]:-}
  existing_max=${TUI_OPERATOR_CHANNEL_MAX_VERSIONS[$constraint_key]:-}
  channel_head=$(channel_head_from_metadata "$channel" <<< "$metadata")
  head_label="Use the channel head"
  [ -z "$channel_head" ] || head_label+=" ($channel_head)"

  if [ -n "$existing_min" ] || [ -n "$existing_max" ]; then
    if [ -n "$existing_min" ] && [ "$existing_min" = "$existing_max" ]; then
      keep_version_label="Keep specific version $existing_min"
    else
      keep_version_label="Keep existing range ${existing_min:-start} — ${existing_max:-head}"
    fi
    if ! choose_one "Package: $package\nChannel: $channel\nChannel head: ${channel_head:-unknown}\n\nMirror the channel head or choose a version:" \
      "$keep_version_label" \
      "$head_label" \
      "Choose a specific version"; then
      return 1
    fi
  elif ! choose_one "Package: $package\nChannel: $channel\nChannel head: ${channel_head:-unknown}\n\nMirror the channel head or choose a version:" \
    "$head_label" \
    "Choose a specific version"; then
    return 1
  fi

  version_choice=$CHOSEN_VALUE
  if [ -n "$keep_version_label" ] && [ "$version_choice" = "$keep_version_label" ]; then
    [ -z "$existing_min" ] || pending_mins["$constraint_key"]=$existing_min
    [ -z "$existing_max" ] || pending_maxes["$constraint_key"]=$existing_max
    return
  fi
  [ "$version_choice" = "Choose a specific version" ] || return

  if ! load_tui_operator_versions "$catalog_image" "$package" "$channel"; then
    tui_error "Could not load versions for '$package' in channel '$channel'."
    return 1
  fi
  if ! choose_one "Choose the exact version for $package / $channel:" \
    "${TUI_OPERATOR_VERSIONS[@]}"; then
    return 1
  fi
  selected_version=$CHOSEN_VALUE
  pending_mins["$constraint_key"]=$selected_version
  pending_maxes["$constraint_key"]=$selected_version
}

choose_tui_package_channels() {
  local catalog_image=$1
  local package=$2
  local default_channel=$3
  local existing_spec=$4
  local metadata=$5
  local pending_mins_name=$6
  local pending_maxes_name=$7
  local requested_channels default_selection="1" channel_index selected_channel
  local joined_channels
  local -a channels=("$default_channel") default_indices=()

  while IFS= read -r selected_channel; do
    [ -n "$selected_channel" ] || continue
    [ "$selected_channel" = "$default_channel" ] || channels+=("$selected_channel")
  done < <(available_channels_from_metadata <<< "$metadata")

  if [[ "$existing_spec" == *:* ]]; then
    requested_channels=${existing_spec#*:}
    for channel_index in "${!channels[@]}"; do
      selected_channel=${channels[$channel_index]}
      [[ ",$requested_channels," == *",$selected_channel,"* ]] && \
        default_indices+=("$((channel_index + 1))")
    done
    if [ "${#default_indices[@]}" -gt 0 ]; then
      default_selection=$(IFS=,; echo "${default_indices[*]}")
    fi
  fi

  if ! choose_many "Select channels for $package\nCurrent channels are preselected; the catalog default is listed first." \
    "$default_selection" rows b back "${channels[@]}"; then
    return 1
  fi
  for selected_channel in "${CHOSEN_VALUES[@]}"; do
    choose_tui_operator_channel_version "$catalog_image" "$package" \
      "$selected_channel" "$metadata" "$pending_mins_name" "$pending_maxes_name" || return 1
  done
  joined_channels=$(IFS=,; echo "${CHOSEN_VALUES[*]}")
  TUI_SELECTED_PACKAGE_CHANNELS=$joined_channels
}

commit_tui_operator_channel_versions() {
  local catalog_image=$1
  local edit_mode=$2
  local selected_packages_name=$3
  local customized_packages_name=$4
  local existing_specs_name=$5
  local pending_mins_name=$6
  local pending_maxes_name=$7
  local -n selected_packages=$selected_packages_name
  local -n customized_packages=$customized_packages_name
  local -n existing_specs=$existing_specs_name
  local -n pending_mins=$pending_mins_name
  local -n pending_maxes=$pending_maxes_name
  local package constraint_key

  if [ "$edit_mode" = fresh ]; then
    clear_operator_channel_versions "$catalog_image"
  else
    for package in "${!existing_specs[@]}"; do
      [[ -v selected_packages["$package"] ]] || \
        clear_operator_channel_versions "$catalog_image" "$package"
    done
  fi
  for package in "${!customized_packages[@]}"; do
    clear_operator_channel_versions "$catalog_image" "$package"
  done
  for constraint_key in "${!pending_mins[@]}"; do
    TUI_OPERATOR_CHANNEL_MIN_VERSIONS["$constraint_key"]=${pending_mins[$constraint_key]}
  done
  for constraint_key in "${!pending_maxes[@]}"; do
    TUI_OPERATOR_CHANNEL_MAX_VERSIONS["$constraint_key"]=${pending_maxes[$constraint_key]}
  done
}

browse_tui_catalog() {
  local catalog_image=$1
  local package search cache_key metadata default_channel channel
  local details version channel_label package_label channel_head browse_choice
  local -a all_packages=() matches=() channels=() channel_options=() package_options=()
  local -A channel_by_label=() package_by_label=()

  load_tui_catalog_packages "$catalog_image" || return 1
  all_packages=("${TUI_CATALOG_PACKAGES[@]}")

  while true; do
    if ! tui_input "Filter packages in ${catalog_image##*/}.\n\nLeave this blank to browse the entire catalog." ""; then
      return
    fi
    search=$TUI_VALUE
    matches=()
    for package in "${all_packages[@]}"; do
      if [ -z "$search" ] || [[ "${package,,}" == *"${search,,}"* ]]; then
        matches+=("$package")
      fi
    done
    if [ "${#matches[@]}" -eq 0 ]; then
      tui_error "No package names matched '$search'."
      continue
    fi

    package_options=()
    package_by_label=()
    tui_update_geometry
    for package in "${matches[@]}"; do
      tui_package_label "$package" "${CACHED_DEFAULT_CHANNELS["$catalog_image|$package"]}"
      package_label=$TUI_PACKAGE_LABEL
      package_options+=("$package_label")
      package_by_label["$package_label"]=$package
    done
    while choose_one "Choose a package to inspect (${#matches[@]} shown):" "${package_options[@]}"; do
      package=${package_by_label[$CHOSEN_VALUE]}
      cache_key="$catalog_image|$package"
      default_channel=${CACHED_DEFAULT_CHANNELS[$cache_key]}
      if ! load_tui_package_metadata "$catalog_image" "$package"; then
        tui_error "Could not query package '$package'."
        continue
      fi
      metadata=$TUI_PACKAGE_METADATA

      channels=("$default_channel")
      while IFS= read -r channel; do
        [ -n "$channel" ] || continue
        [ "$channel" = "$default_channel" ] || channels+=("$channel")
      done < <(available_channels_from_metadata <<< "$metadata")

      channel_options=()
      channel_by_label=()
      for channel in "${channels[@]}"; do
        if [ "$channel" = "$default_channel" ]; then
          channel_label="$channel (default)"
        else
          channel_label=$channel
        fi
        channel_options+=("$channel_label")
        channel_by_label["$channel_label"]=$channel
      done

      while choose_one "Catalog: ${catalog_image##*/}\nPackage: $package\nDefault channel: $default_channel\n\nChoose a channel to inspect:" \
        "${channel_options[@]}"; do
        channel=${channel_by_label[$CHOSEN_VALUE]}
        channel_head=$(channel_head_from_metadata "$channel" <<< "$metadata")
        while true; do
          if ! choose_one "Catalog: ${catalog_image##*/}\nPackage: $package\nChannel: $channel\nChannel head: ${channel_head:-unknown}\n\nChoose what to view:" \
            "View the channel head" \
            "Choose a specific version to view"; then
            break
          fi
          browse_choice=$CHOSEN_VALUE
          if [ "$browse_choice" = "View the channel head" ]; then
            details="Catalog: $catalog_image\n\nPackage: $package\nChannel: $channel\nChannel head: ${channel_head:-unknown}"
            tui_message "Operator channel" "$details"
            continue
          fi
          if ! load_tui_operator_versions "$catalog_image" "$package" "$channel"; then
            tui_error "Could not load versions for '$package' in channel '$channel'."
            continue
          fi
          if ! choose_one "Choose a version to view for $package / $channel:" \
            "${TUI_OPERATOR_VERSIONS[@]}"; then
            continue
          fi
          version=$CHOSEN_VALUE
          details="Catalog: $catalog_image\n\nPackage: $package\nChannel: $channel\nVersion: $version"
          [ "$version" != "$channel_head" ] || details+=$'\n'"Channel head: yes"
          tui_message "Operator version" "$details"
        done
      done
    done
  done
}

browse_tui_catalogs() {
  local selected_catalog
  local -a catalogs=("$@")

  while choose_one "Select a catalog to browse:" "${catalogs[@]}"; do
    selected_catalog=$CHOSEN_VALUE
    browse_tui_catalog "$selected_catalog" || true
  done
}

configure_tui_catalog() {
  local catalog_image=$1
  local edit_mode=${2:-fresh}
  local package metadata default_channel joined_channels search cache_key
  local customize_channels specs_text spec channel_back menu_choice
  local selected_count new_count existing_count review_text keep_channels_label
  local -a all_packages=() matches=() catalog_specs=() new_packages=()
  local -a selected_packages=()
  local -A selected_package_names=()
  local -A existing_package_specs=()
  local -A custom_channel_packages=()
  local -A pending_channel_mins=()
  local -A pending_channel_maxes=()

  if [ "$edit_mode" = append ]; then
    specs_text=${TUI_CATALOG_PACKAGE_SPECS[$catalog_image]}
    while IFS= read -r spec; do
      [ -n "$spec" ] || continue
      package=${spec%%:*}
      selected_package_names["$package"]=1
      existing_package_specs["$package"]=$spec
    done <<< "$specs_text"
  fi

  load_tui_catalog_packages "$catalog_image" || return 1
  all_packages=("${TUI_CATALOG_PACKAGES[@]}")

  while true; do
    selected_count=${#selected_package_names[@]}
    if ! choose_one "Catalog: ${catalog_image##*/}\nSelected packages: $selected_count\n\nChoose an action:" \
      "Browse all packages" \
      "Search packages" \
      "Review selected packages" \
      "Continue to channel selection"; then
      return 1
    fi
    menu_choice=$CHOSEN_VALUE

    case "$menu_choice" in
      "Browse all packages")
        matches=("${all_packages[@]}")
        edit_tui_package_matches selected_package_names \
          "Select packages from the complete catalog." "$catalog_image" "${matches[@]}" || true
        continue
        ;;
      "Search packages")
        while tui_input "Search for packages.\n\nSelections are preserved between searches. Press Esc when finished searching." ""; do
          search=$TUI_VALUE
          [ -n "$search" ] || continue
          matches=()
          for package in "${all_packages[@]}"; do
            [[ "${package,,}" == *"${search,,}"* ]] && matches+=("$package")
          done
          if [ "${#matches[@]}" -eq 0 ]; then
            tui_error "No package names matched '$search'."
            continue
          fi
          edit_tui_package_matches selected_package_names \
            "Matches for '$search' (${#matches[@]} found)." "$catalog_image" "${matches[@]}" || true
        done
        continue
        ;;
      "Review selected packages")
        if [ "$selected_count" -eq 0 ]; then
          tui_message "Selected packages" "No packages are selected."
          continue
        fi
        review_text=""
        for package in "${all_packages[@]}"; do
          [[ -v selected_package_names["$package"] ]] && review_text+=$'\n'"  • $package"
        done
        review_text=${review_text#$'\n'}
        tui_message "Selected packages ($selected_count)" "$review_text"
        continue
        ;;
      "Continue to channel selection")
        if [ "$selected_count" -eq 0 ]; then
          tui_error "Select at least one package before continuing."
          continue
        fi
        new_packages=()
        selected_packages=()
        for package in "${all_packages[@]}"; do
          [[ -v selected_package_names["$package"] ]] || continue
          selected_packages+=("$package")
          [[ -v existing_package_specs["$package"] ]] || new_packages+=("$package")
        done
        new_count=${#new_packages[@]}
        existing_count=$((selected_count - new_count))
        customize_channels=false
        custom_channel_packages=()
        pending_channel_mins=()
        pending_channel_maxes=()
        if [ "$existing_count" -gt 0 ]; then
          keep_channels_label="Keep existing channels and use defaults for new packages"
        else
          keep_channels_label="Use default channels for every package"
        fi
        if ! choose_one "Choose how channels should be handled for $selected_count selected package(s):" \
          "$keep_channels_label" \
          "Choose which packages need specific channels"; then
          continue
        fi
        if [ "$CHOSEN_VALUE" = "Choose which packages need specific channels" ]; then
          customize_channels=true
          if ! edit_tui_package_matches custom_channel_packages \
            "Select only the packages whose channels you want to customize.\nExisting choices are preserved for packages you do not select." \
            "$catalog_image" "${selected_packages[@]}"; then
            continue
          fi
          if [ "${#custom_channel_packages[@]}" -eq 0 ]; then
            tui_error "Select at least one package for specific channel selection, or keep the current/default channels."
            continue
          fi
        fi

        catalog_specs=()
        channel_back=false
        for package in "${all_packages[@]}"; do
          [[ -v selected_package_names["$package"] ]] || continue
          if [[ -v existing_package_specs["$package"] ]]; then
            if [ "$customize_channels" != true ] || [[ ! -v custom_channel_packages["$package"] ]]; then
              catalog_specs+=("${existing_package_specs[$package]}")
              continue
            fi
          fi
          cache_key="$catalog_image|$package"
          default_channel=${CACHED_DEFAULT_CHANNELS[$cache_key]}
          if [ "$customize_channels" = true ] && [[ -v custom_channel_packages["$package"] ]]; then
            if ! load_tui_package_metadata "$catalog_image" "$package"; then
              tui_error "Could not query package '$package'."
              channel_back=true
              break
            fi
            metadata=$TUI_PACKAGE_METADATA
            spec=${existing_package_specs[$package]:-}
            if ! choose_tui_package_channels "$catalog_image" "$package" "$default_channel" \
              "$spec" "$metadata" pending_channel_mins pending_channel_maxes; then
              channel_back=true
              break
            fi
            joined_channels=$TUI_SELECTED_PACKAGE_CHANNELS
          else
            joined_channels=$default_channel
          fi
          catalog_specs+=("$package:$joined_channels")
        done
        [ "$channel_back" != true ] || continue
        for package in "${!custom_channel_packages[@]}"; do
          cache_key="$catalog_image|$package"
          unset 'TUI_IMPORTED_PACKAGES[$cache_key]'
          unset 'TUI_IMPORTED_PACKAGE_DEFAULTS[$cache_key]'
        done
        commit_tui_operator_channel_versions "$catalog_image" "$edit_mode" \
          selected_package_names custom_channel_packages existing_package_specs \
          pending_channel_mins pending_channel_maxes
        break
        ;;
    esac

  done

  printf -v specs_text '%s\n' "${catalog_specs[@]}"
  TUI_CATALOG_PACKAGE_SPECS["$catalog_image"]=${specs_text%$'\n'}
  TUI_WHOLE_CATALOG["$catalog_image"]=false
  if [ "$edit_mode" = fresh ]; then
    for cache_key in "${!TUI_IMPORTED_PACKAGES[@]}"; do
      [[ "$cache_key" == "$catalog_image|"* ]] || continue
      unset 'TUI_IMPORTED_PACKAGES[$cache_key]'
      unset 'TUI_IMPORTED_PACKAGE_DEFAULTS[$cache_key]'
    done
  fi
}

validate_release_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][a-zA-Z0-9]+)*$ ]]
}

# -----------------------------------------------------------------------------
# OpenShift platform selection
# -----------------------------------------------------------------------------

configure_tui_platform() {
  local version=$1
  local channel min_version="" max_version="" lowest_version menu_choice
  local full_channel=false graph=true architecture architecture_filter valid_architectures
  local listed_minimum listed_maximum current_release current_release_arch default_architectures
  local architecture_index selected_architecture range_choice full_choice graph_yes graph_no
  local -a architectures=(amd64 arm64 ppc64le s390x multi) channel_options=() selected_architectures=()

  default_architectures="1"
  if [ "$TUI_PLATFORM_CONFIGURED" = true ] && [ "${#TUI_PLATFORM_ARCHITECTURES[@]}" -gt 0 ]; then
    default_architectures=""
    for architecture_index in "${!architectures[@]}"; do
      for selected_architecture in "${TUI_PLATFORM_ARCHITECTURES[@]}"; do
        [ "${architectures[$architecture_index]}" = "$selected_architecture" ] || continue
        [ -z "$default_architectures" ] || default_architectures+=","
        default_architectures+="$((architecture_index + 1))"
      done
    done
  fi
  while true; do
    if ! choose_many "Select OpenShift release architectures.\n\nThese architectures apply to every platform version in this image set." \
      "$default_architectures" rows b back "${architectures[@]}"; then
      return 1
    fi
    selected_architectures=("${CHOSEN_VALUES[@]}")
    valid_architectures=true
    if [ "${#selected_architectures[@]}" -gt 1 ]; then
      for architecture in "${selected_architectures[@]}"; do
        if [ "$architecture" = multi ]; then
          tui_error "Choose 'multi' by itself, or select individual architectures."
          valid_architectures=false
          break
        fi
      done
    fi
    [ "$valid_architectures" != true ] || break
  done
  architecture_filter=$(IFS=,; echo "${selected_architectures[*]}")

  while true; do
    if ! choose_one "Choose an OpenShift $version release channel:" \
      "Use stable-$version" \
      "Browse available channels and release ranges" \
      "Enter a channel name"; then
      return 1
    fi
    menu_choice=$CHOSEN_VALUE
    case "$menu_choice" in
      "Use stable-$version")
        channel="stable-$version"
        break
        ;;
      "Browse available channels and release ranges")
        if ! load_release_channel_ranges "$version" "$architecture_filter"; then
          tui_error "Could not load release channels for OpenShift $version."
          continue
        fi
        channel_options=()
        while IFS='|' read -r channel listed_minimum listed_maximum; do
          [ -n "$channel" ] || continue
          channel_options+=("$channel  ($listed_minimum — $listed_maximum)")
        done <<< "$RELEASE_CHANNEL_RANGES"
        if ! choose_one "Select a release channel (minimum — maximum):" "${channel_options[@]}"; then
          continue
        fi
        channel=${CHOSEN_VALUE%% *}
        break
        ;;
      "Enter a channel name")
        if ! tui_input "Release channel name:" "stable-$version"; then
          continue
        fi
        channel=$TUI_VALUE
        if [[ ! "$channel" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
          tui_error "Enter a channel such as stable-$version."
          continue
        fi
        break
        ;;
    esac
  done

  if [[ -v TUI_PLATFORM_VERSIONS["$channel"] ]]; then
    min_version=${TUI_PLATFORM_MIN_VERSIONS[$channel]:-}
    max_version=${TUI_PLATFORM_MAX_VERSIONS[$channel]:-}
    full_channel=${TUI_PLATFORM_FULL_CHANNELS[$channel]:-false}
  fi

  if ! resolve_current_release "$channel" "${selected_architectures[0]}"; then
    tui_error "Could not resolve the current OpenShift release for '$channel' and architecture '${selected_architectures[0]}'."
    return 1
  fi
  current_release=$RESOLVED_CURRENT_RELEASE
  current_release_arch=$RESOLVED_CURRENT_RELEASE_ARCH
  if [[ "$current_release" != "$version".* ]]; then
    tui_error "Channel '$channel' currently resolves to $current_release, not OpenShift $version."
    return 1
  fi

  range_choice="Choose an optional minimum and maximum release"
  full_choice="Mirror every release in the channel"
  if [ "$full_channel" = true ]; then
    if ! choose_one "How much of $channel should be mirrored?" "$full_choice" "$range_choice"; then
      return 1
    fi
  elif ! choose_one "How much of $channel should be mirrored?" "$range_choice" "$full_choice"; then
    return 1
  fi
  if [ "$CHOSEN_VALUE" = "$full_choice" ]; then
    full_channel=true
  else
    full_channel=false
    while true; do
      if ! tui_input "Minimum release (optional):" "$min_version"; then
        return 1
      fi
      min_version=$TUI_VALUE
      if [ -n "$min_version" ] && { ! validate_release_version "$min_version" || [[ "$min_version" != "$version".* ]]; }; then
        tui_error "Enter a release such as $version.1, or leave this blank."
        continue
      fi
      break
    done
    while true; do
      if ! tui_input "Maximum release (optional):" "$max_version"; then
        return 1
      fi
      max_version=$TUI_VALUE
      if [ -n "$max_version" ] && { ! validate_release_version "$max_version" || [[ "$max_version" != "$version".* ]]; }; then
        tui_error "Enter a release such as $version.1, or leave this blank."
        continue
      fi
      if [ -n "$min_version" ] && [ -n "$max_version" ]; then
        lowest_version=$(printf '%s\n' "$min_version" "$max_version" | sort -V | head -n1)
        if [ "$lowest_version" != "$min_version" ]; then
          tui_error "The maximum release cannot be lower than the minimum release."
          continue
        fi
      fi
      break
    done
  fi

  graph_yes="Yes — include the update graph"
  graph_no="No — omit the update graph"
  if [ "$TUI_PLATFORM_GRAPH" = false ]; then
    if ! choose_one "Include the OpenShift Update Service graph?\n\nThis setting applies to every platform version." \
      "$graph_no" "$graph_yes"; then
      return 1
    fi
  elif ! choose_one "Include the OpenShift Update Service graph?\n\nThis setting applies to every platform version." \
    "$graph_yes" "$graph_no"; then
    return 1
  fi
  [ "$CHOSEN_VALUE" = "$graph_yes" ] && graph=true || graph=false

  if [[ ! -v TUI_PLATFORM_VERSIONS["$channel"] ]]; then
    TUI_PLATFORM_CHANNELS+=("$channel")
  fi
  TUI_PLATFORM_ARCHITECTURES=("${selected_architectures[@]}")
  TUI_PLATFORM_VERSIONS["$channel"]=$version
  TUI_PLATFORM_MIN_VERSIONS["$channel"]=$min_version
  TUI_PLATFORM_MAX_VERSIONS["$channel"]=$max_version
  TUI_PLATFORM_FULL_CHANNELS["$channel"]=$full_channel
  TUI_PLATFORM_GRAPH=$graph
  TUI_PLATFORM_CURRENT_VERSIONS["$channel"]=$current_release
  TUI_PLATFORM_CURRENT_VERSION_ARCHES["$channel"]=$current_release_arch
  TUI_PLATFORM_CONFIGURED=true
}

remove_tui_platform_release() {
  local option channel selected_option remove_label
  local -a options=() remaining_channels=()
  local -A channel_by_option=()

  if [ "$TUI_PLATFORM_CONFIGURED" != true ] || \
    [ "${#TUI_PLATFORM_CHANNELS[@]}" -eq 0 ]; then
    tui_error "No Platform releases are currently selected."
    return 1
  fi

  for channel in "${TUI_PLATFORM_CHANNELS[@]}"; do
    option="OpenShift ${TUI_PLATFORM_VERSIONS[$channel]:-unknown} — $channel"
    options+=("$option")
    channel_by_option["$option"]=$channel
  done
  if ! choose_one "Choose the Platform release to remove from the in-memory configuration:" \
    "${options[@]}"; then
    return 1
  fi
  selected_option=$CHOSEN_VALUE
  channel=${channel_by_option[$selected_option]}
  remove_label="Remove ${TUI_PLATFORM_VERSIONS[$channel]:-unknown} / $channel"
  if ! choose_one "Remove this Platform release?\n\n$selected_option\n\nThe file will not change until you finish and write the configuration." \
    "Keep the Platform release" \
    "$remove_label"; then
    return 1
  fi
  [ "$CHOSEN_VALUE" = "$remove_label" ] || return 1

  for option in "${TUI_PLATFORM_CHANNELS[@]}"; do
    [ "$option" = "$channel" ] || remaining_channels+=("$option")
  done
  TUI_PLATFORM_CHANNELS=("${remaining_channels[@]}")
  unset 'TUI_PLATFORM_VERSIONS[$channel]'
  unset 'TUI_PLATFORM_MIN_VERSIONS[$channel]'
  unset 'TUI_PLATFORM_MAX_VERSIONS[$channel]'
  unset 'TUI_PLATFORM_FULL_CHANNELS[$channel]'
  unset 'TUI_PLATFORM_CURRENT_VERSIONS[$channel]'
  unset 'TUI_PLATFORM_CURRENT_VERSION_ARCHES[$channel]'

  if [ "${#TUI_PLATFORM_CHANNELS[@]}" -eq 0 ]; then
    TUI_PLATFORM_CONFIGURED=false
    TUI_PLATFORM_ARCHITECTURES=()
  fi
  tui_message "Platform release removed" \
    "Removed $selected_option from the in-memory configuration.\n\nFinish selections and write the YAML to save this change."
}

manage_tui_platform_releases() {
  local action

  if [ "$TUI_PLATFORM_CONFIGURED" = true ]; then
    if ! choose_one "How should the Platform releases be updated?" \
      "Add or edit a Platform release" \
      "Remove a Platform release"; then
      return 1
    fi
    action=$CHOSEN_VALUE
    if [ "$action" = "Remove a Platform release" ]; then
      remove_tui_platform_release
      return
    fi
  fi

  if ! choose_tui_version "OpenShift version for the Platform release:" "$VERSION"; then
    return 1
  fi
  configure_tui_platform "$TUI_SELECTED_VERSION"
}

# -----------------------------------------------------------------------------
# Selection review and ImageSet import
# -----------------------------------------------------------------------------

review_tui_selections() {
  local action=${1:-Close}
  local catalog catalog_version_value specs_text spec package channels platform_channel
  local channel channel_summary
  local -a selected_channels=()
  local review_text="Current selections"

  if [ "$TUI_PLATFORM_CONFIGURED" != true ] && [ "${#TUI_CATALOG_IMAGES[@]}" -eq 0 ]; then
    tui_message "Current selections" "Nothing configured yet."
    return
  fi

  if [ "$TUI_PLATFORM_CONFIGURED" = true ]; then
    printf -v channels '%s, ' "${TUI_PLATFORM_ARCHITECTURES[@]}"
    channels=${channels%, }
    review_text+=$'\n\n'"OpenShift platform (${#TUI_PLATFORM_CHANNELS[@]} version(s))"
    review_text+=$'\n'"  Architectures: $channels"
    review_text+=$'\n'"  Update graph: $TUI_PLATFORM_GRAPH"
    for platform_channel in "${TUI_PLATFORM_CHANNELS[@]}"; do
      review_text+=$'\n\n'"  Version: ${TUI_PLATFORM_VERSIONS[$platform_channel]:-unknown}"
      review_text+=$'\n'"  Channel: $platform_channel"
      review_text+=$'\n'"  Current release: ${TUI_PLATFORM_CURRENT_VERSIONS[$platform_channel]:-unknown}"
      [ -z "${TUI_PLATFORM_MIN_VERSIONS[$platform_channel]:-}" ] || \
        review_text+=$'\n'"  Minimum release: ${TUI_PLATFORM_MIN_VERSIONS[$platform_channel]}"
      [ -z "${TUI_PLATFORM_MAX_VERSIONS[$platform_channel]:-}" ] || \
        review_text+=$'\n'"  Maximum release: ${TUI_PLATFORM_MAX_VERSIONS[$platform_channel]}"
      [ "${TUI_PLATFORM_FULL_CHANNELS[$platform_channel]:-false}" != true ] || \
        review_text+=$'\n'"  Entire channel: yes"
    done
  fi

  for catalog in "${TUI_CATALOG_IMAGES[@]}"; do
    catalog_version_value=$(catalog_version "$catalog")
    review_text+=$'\n\n'"Operator catalog"
    review_text+=$'\n'"  Version: $catalog_version_value"
    review_text+=$'\n'"  $catalog"
    if [ "${TUI_WHOLE_CATALOG[$catalog]:-false}" = true ]; then
      review_text+=$'\n'"  Entire catalog (default channel heads)"
    else
      specs_text=${TUI_CATALOG_PACKAGE_SPECS[$catalog]}
      while IFS= read -r spec; do
        [ -n "$spec" ] || continue
        package=${spec%%:*}
        if [[ "$spec" == *:* ]]; then
          channels=${spec#*:}
          channel_summary=""
          IFS=',' read -r -a selected_channels <<< "$channels"
          for channel in "${selected_channels[@]}"; do
            operator_channel_label "$catalog" "$package" "$channel"
            [ -z "$channel_summary" ] || channel_summary+=", "
            channel_summary+="$OPERATOR_CHANNEL_LABEL"
          done
          review_text+=$'\n'"  • $package: $channel_summary"
        else
          review_text+=$'\n'"  • $package (catalog defaults)"
        fi
      done <<< "$specs_text"
    fi
  done
  tui_message "Current selections" "$review_text" "$action"
}

choose_catalog_edit_mode() {
  local catalog_image=$1
  local already_selected=$2

  CATALOG_EDIT_MODE=back
  if [ "$already_selected" != true ]; then
    if ! choose_one "How should ${catalog_image##*/} be included?" \
      "Select individual packages" \
      "Include the entire catalog"; then
      return
    fi
    [ "$CHOSEN_VALUE" = "Include the entire catalog" ] && CATALOG_EDIT_MODE=entire || CATALOG_EDIT_MODE=fresh
  elif [ "${TUI_WHOLE_CATALOG[$catalog_image]}" = true ]; then
    if ! choose_one "This catalog currently includes every package." \
      "Keep the entire catalog" \
      "Replace it with individual package selections"; then
      return
    fi
    [ "$CHOSEN_VALUE" = "Replace it with individual package selections" ] && CATALOG_EDIT_MODE=fresh
  else
    if ! choose_one "How should ${catalog_image##*/} be updated?" \
      "Edit the current package selections" \
      "Start over with new package selections" \
      "Replace them with the entire catalog"; then
      return
    fi
    case "$CHOSEN_VALUE" in
      "Edit the current package selections") CATALOG_EDIT_MODE=append ;;
      "Start over with new package selections") CATALOG_EDIT_MODE=fresh ;;
      "Replace them with the entire catalog") CATALOG_EDIT_MODE=entire ;;
    esac
  fi
}

save_entire_tui_catalog() {
  local catalog_image=$1
  local cache_key
  TUI_WHOLE_CATALOG["$catalog_image"]=true
  TUI_CATALOG_PACKAGE_SPECS["$catalog_image"]=""
  for cache_key in "${!TUI_IMPORTED_PACKAGES[@]}"; do
    [[ "$cache_key" == "$catalog_image|"* ]] || continue
    unset 'TUI_IMPORTED_PACKAGES[$cache_key]'
    unset 'TUI_IMPORTED_PACKAGE_DEFAULTS[$cache_key]'
  done
  clear_operator_channel_versions "$catalog_image"
}

# The AWK parser emits simple pipe-delimited records. Bash owns validation and
# state changes, keeping parsing separate from mutation.
parse_imageset_config_records() {
  awk '
    function scalar(line, prefix, value) {
      value = substr(line, length(prefix) + 1)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      if ((substr(value, 1, 1) == "\"" && substr(value, length(value), 1) == "\"") ||
          (substr(value, 1, 1) == "\047" && substr(value, length(value), 1) == "\047")) {
        value = substr(value, 2, length(value) - 2)
      }
      return value
    }
    function emit_package( joined, item_index) {
      if (package == "") return
      joined = ""
      for (item_index = 1; item_index <= channel_count; item_index++) {
        joined = joined (joined == "" ? "" : ",") package_channels[item_index]
      }
      print "PACKAGE|" catalog "|" package "|" joined "|" package_default
      for (item_index = 1; item_index <= channel_count; item_index++) {
        if (package_channel_mins[item_index] != "" || package_channel_maxes[item_index] != "") {
          print "OPERATOR_CHANNEL|" catalog "|" package "|" package_channels[item_index] "|" \
            package_channel_mins[item_index] "|" package_channel_maxes[item_index]
        }
        delete package_channels[item_index]
        delete package_channel_mins[item_index]
        delete package_channel_maxes[item_index]
      }
      package = ""
      package_default = ""
      channel_count = 0
    }
    function emit_platform_channel() {
      if (platform_channel == "") return
      print "PLATFORM_CHANNEL|" platform_channel "|" platform_min "|" platform_max "|" platform_full
      platform_channel = ""
      platform_min = ""
      platform_max = ""
      platform_full = ""
    }
    /^  (additionalImages|helm):/ { emit_platform_channel(); emit_package(); exit }
    /^  platform:[[:space:]]*$/ { emit_package(); section = "platform"; print "PLATFORM"; next }
    /^  operators:[[:space:]]*$/ { emit_platform_channel(); emit_package(); section = "operators"; next }
    section == "platform" && /^    architectures:[[:space:]]*$/ { platform_part = "architectures"; next }
    section == "platform" && /^    channels:[[:space:]]*$/ { platform_part = "channels"; next }
    section == "platform" && platform_part == "architectures" && /^    -[[:space:]]+/ {
      print "ARCH|" scalar($0, "    -"); next
    }
    section == "platform" && platform_part == "channels" && /^    -[[:space:]]+type:[[:space:]]*/ {
      emit_platform_channel(); next
    }
    section == "platform" && platform_part == "channels" && /^      name:[[:space:]]*/ {
      platform_channel = scalar($0, "      name:"); next
    }
    section == "platform" && platform_part == "channels" && /^      minVersion:[[:space:]]*/ {
      platform_min = scalar($0, "      minVersion:"); next
    }
    section == "platform" && platform_part == "channels" && /^      maxVersion:[[:space:]]*/ {
      platform_max = scalar($0, "      maxVersion:"); next
    }
    section == "platform" && platform_part == "channels" && /^      full:[[:space:]]*/ {
      platform_full = scalar($0, "      full:"); next
    }
    section == "platform" && /^    graph:[[:space:]]*/ {
      print "GRAPH|" scalar($0, "    graph:"); next
    }
    section == "operators" && /^  -[[:space:]]+catalog:[[:space:]]*/ {
      emit_package(); catalog = scalar($0, "  - catalog:"); print "CATALOG|" catalog; next
    }
    section == "operators" && /^    -[[:space:]]+name:[[:space:]]*/ {
      emit_package(); package = scalar($0, "    - name:"); next
    }
    section == "operators" && package != "" && /^      defaultChannel:[[:space:]]*/ {
      package_default = scalar($0, "      defaultChannel:"); next
    }
    section == "operators" && package != "" && /^      -[[:space:]]+name:[[:space:]]*/ {
      package_channels[++channel_count] = scalar($0, "      - name:"); next
    }
    section == "operators" && package != "" && channel_count > 0 && /^        minVersion:[[:space:]]*/ {
      package_channel_mins[channel_count] = scalar($0, "        minVersion:"); next
    }
    section == "operators" && package != "" && channel_count > 0 && /^        maxVersion:[[:space:]]*/ {
      package_channel_maxes[channel_count] = scalar($0, "        maxVersion:"); next
    }
    END { emit_platform_channel(); emit_package() }
  ' "$1"
}

load_tui_config() {
  local config_file=$1 parsed record_type value catalog package channels default_channel extra constraint_key
  local platform_seen=false platform_graph=true platform_channel
  local parse_error="" preserved_suffix="" lookup_architecture
  local -a platform_architectures=() platform_channels=() imported_catalogs=()
  local -A platform_mins=() platform_maxes=() platform_fulls=()
  local -A platform_versions=() platform_current_versions=() platform_current_arches=()
  local -A imported_specs=() imported_whole=() imported_packages=() imported_defaults=() catalog_seen=()
  local -A imported_channel_mins=() imported_channel_maxes=()

  if ! parsed=$(parse_imageset_config_records "$config_file"); then
    tui_error "Could not parse '${config_file##*/}'."
    return 1
  fi

  while IFS='|' read -r record_type value catalog package channels extra; do
    case "$record_type" in
      PLATFORM) platform_seen=true ;;
      ARCH) [ -n "$value" ] && platform_architectures+=("$value") ;;
      PLATFORM_CHANNEL)
        platform_channel=$value
        if [ -z "$platform_channel" ] || [[ "$platform_channel" == *'|'* || "$platform_channel" == *$'\t'* || "$platform_channel" == *$'\n'* ]]; then
          parse_error="The configuration contains an invalid platform release channel."
          break
        fi
        if [[ -v platform_versions["$platform_channel"] ]]; then
          parse_error="The configuration contains the platform channel '$platform_channel' more than once."
          break
        fi
        platform_channels+=("$platform_channel")
        platform_mins["$platform_channel"]=$catalog
        platform_maxes["$platform_channel"]=$package
        platform_fulls["$platform_channel"]=${channels:-false}
        if [[ "$platform_channel" =~ -([0-9]+\.[0-9]+)$ ]]; then
          platform_versions["$platform_channel"]=${BASH_REMATCH[1]}
        elif [[ "$catalog" =~ ^([0-9]+\.[0-9]+)\. ]]; then
          platform_versions["$platform_channel"]=${BASH_REMATCH[1]}
        elif [[ "$package" =~ ^([0-9]+\.[0-9]+)\. ]]; then
          platform_versions["$platform_channel"]=${BASH_REMATCH[1]}
        else
          platform_versions["$platform_channel"]="unknown"
        fi
        ;;
      GRAPH) platform_graph=$value ;;
      CATALOG)
        catalog=$value
        if [ -z "$catalog" ] || [[ "$catalog" == *'|'* || "$catalog" == *$'\t'* || "$catalog" == *$'\n'* ]]; then
          parse_error="The configuration contains an invalid catalog reference."
          break
        fi
        if [[ ! -v catalog_seen["$catalog"] ]]; then
          imported_catalogs+=("$catalog")
          catalog_seen["$catalog"]=1
          imported_whole["$catalog"]=true
          imported_specs["$catalog"]=""
        fi
        ;;
      PACKAGE)
        # PACKAGE records are: type | catalog | package | channels | explicit default.
        default_channel=$channels
        channels=$package
        package=$catalog
        catalog=$value
        if [ -z "$catalog" ] || [ -z "$package" ] || [[ "$package" == *'|'* || "$package" == *$'\t'* || "$package" == *$'\n'* ]]; then
          parse_error="The configuration contains an invalid operator package entry."
          break
        fi
        imported_whole["$catalog"]=false
        if [ -n "${imported_specs[$catalog]}" ]; then
          imported_specs["$catalog"]+=$'\n'
        fi
        if [ -n "$channels" ]; then
          imported_specs["$catalog"]+="$package:$channels"
        else
          imported_specs["$catalog"]+="$package"
        fi
        imported_packages["$catalog|$package"]=1
        imported_defaults["$catalog|$package"]=$default_channel
        ;;
      OPERATOR_CHANNEL)
        constraint_key="$value|$catalog|$package"
        if [ -z "$value" ] || [ -z "$catalog" ] || [ -z "$package" ] || \
          [[ "$constraint_key" == *$'\t'* || "$constraint_key" == *$'\n'* ]]; then
          parse_error="The configuration contains an invalid Operator channel version filter."
          break
        fi
        [ -z "$channels" ] || imported_channel_mins["$constraint_key"]=$channels
        [ -z "$extra" ] || imported_channel_maxes["$constraint_key"]=$extra
        ;;
    esac
  done <<< "$parsed"

  if ! grep -Eq '^[[:space:]]*kind:[[:space:]]*ImageSetConfiguration[[:space:]]*$' "$config_file"; then
    parse_error="${config_file##*/} is not an ImageSetConfiguration."
  elif [ "$platform_seen" = true ] && [ "${#platform_channels[@]}" -eq 0 ]; then
    parse_error="The platform section does not contain any release channels."
  fi
  if [ -n "$parse_error" ]; then
    tui_error "$parse_error\n\nThe file was not changed."
    return 1
  fi

  if [ "$platform_seen" = true ]; then
    lookup_architecture=${platform_architectures[0]:-amd64}
    for platform_channel in "${platform_channels[@]}"; do
      if ! resolve_current_release "$platform_channel" "$lookup_architecture"; then
        tui_error "Could not resolve the current OpenShift release for '$platform_channel' and architecture '$lookup_architecture'.\n\nThe file was not changed."
        return 1
      fi
      platform_current_versions["$platform_channel"]=$RESOLVED_CURRENT_RELEASE
      platform_current_arches["$platform_channel"]=$RESOLVED_CURRENT_RELEASE_ARCH
      if [ "${platform_versions[$platform_channel]}" = unknown ] && \
        [[ "$RESOLVED_CURRENT_RELEASE" =~ ^([0-9]+\.[0-9]+)\. ]]; then
        platform_versions["$platform_channel"]=${BASH_REMATCH[1]}
      fi
    done
  fi

  preserved_suffix=$(awk '/^  (additionalImages|helm):/ { preserve = 1 } preserve' "$config_file")

  TUI_CATALOG_IMAGES=("${imported_catalogs[@]}")
  TUI_CATALOG_PACKAGE_SPECS=()
  TUI_CATALOG_VERSIONS=()
  TUI_WHOLE_CATALOG=()
  TUI_IMPORTED_PACKAGES=()
  TUI_IMPORTED_PACKAGE_DEFAULTS=()
  TUI_OPERATOR_CHANNEL_MIN_VERSIONS=()
  TUI_OPERATOR_CHANNEL_MAX_VERSIONS=()
  for catalog in "${imported_catalogs[@]}"; do
    TUI_CATALOG_PACKAGE_SPECS["$catalog"]=${imported_specs[$catalog]}
    TUI_CATALOG_VERSIONS["$catalog"]=$(catalog_version "$catalog")
    TUI_WHOLE_CATALOG["$catalog"]=${imported_whole[$catalog]}
  done
  for value in "${!imported_packages[@]}"; do
    TUI_IMPORTED_PACKAGES["$value"]=1
    TUI_IMPORTED_PACKAGE_DEFAULTS["$value"]=${imported_defaults[$value]}
  done
  for value in "${!imported_channel_mins[@]}"; do
    TUI_OPERATOR_CHANNEL_MIN_VERSIONS["$value"]=${imported_channel_mins[$value]}
  done
  for value in "${!imported_channel_maxes[@]}"; do
    TUI_OPERATOR_CHANNEL_MAX_VERSIONS["$value"]=${imported_channel_maxes[$value]}
  done
  TUI_PLATFORM_CONFIGURED=$platform_seen
  TUI_PLATFORM_ARCHITECTURES=("${platform_architectures[@]}")
  TUI_PLATFORM_CHANNELS=("${platform_channels[@]}")
  TUI_PLATFORM_VERSIONS=()
  TUI_PLATFORM_MIN_VERSIONS=()
  TUI_PLATFORM_MAX_VERSIONS=()
  TUI_PLATFORM_FULL_CHANNELS=()
  TUI_PLATFORM_CURRENT_VERSIONS=()
  TUI_PLATFORM_CURRENT_VERSION_ARCHES=()
  for platform_channel in "${platform_channels[@]}"; do
    TUI_PLATFORM_VERSIONS["$platform_channel"]=${platform_versions[$platform_channel]}
    TUI_PLATFORM_MIN_VERSIONS["$platform_channel"]=${platform_mins[$platform_channel]}
    TUI_PLATFORM_MAX_VERSIONS["$platform_channel"]=${platform_maxes[$platform_channel]}
    TUI_PLATFORM_FULL_CHANNELS["$platform_channel"]=${platform_fulls[$platform_channel]}
    TUI_PLATFORM_CURRENT_VERSIONS["$platform_channel"]=${platform_current_versions[$platform_channel]}
    TUI_PLATFORM_CURRENT_VERSION_ARCHES["$platform_channel"]=${platform_current_arches[$platform_channel]}
  done
  TUI_PLATFORM_GRAPH=$platform_graph
  TUI_PRESERVED_CONFIG_SUFFIX=$preserved_suffix
  TUI_LOADED_FILE=$config_file
  OUTPUT_FILE=$config_file
  return 0
}

select_existing_tui_config() {
  local config_file file_label
  local -a config_files=() file_labels=()

  while IFS= read -r config_file; do
    grep -Eq '^[[:space:]]*kind:[[:space:]]*ImageSetConfiguration[[:space:]]*$' "$config_file" || continue
    config_files+=("$config_file")
    file_labels+=("${config_file##*/}")
  done < <(find "$ORIGINAL_DIR" -maxdepth 1 -type f \( -iname '*.yaml' -o -iname '*.yml' \) -print | sort)

  if [ "${#config_files[@]}" -eq 0 ]; then
    tui_error "No ImageSetConfiguration .yaml or .yml files were found in:\n\n$ORIGINAL_DIR"
    return 1
  fi
  if ! choose_one "Choose a configuration from the directory where the script was launched:\n\n$ORIGINAL_DIR" "${file_labels[@]}"; then
    return 1
  fi
  file_label=$CHOSEN_VALUE
  for config_file in "${config_files[@]}"; do
    [ "${config_file##*/}" = "$file_label" ] || continue
    load_tui_config "$config_file" || return 1
    tui_message "Configuration loaded" "Editing: ${config_file##*/}\n\nPlatform and Operator selections are ready to review or upgrade. Additional images, Helm settings, and following content will be preserved."
    return 0
  done
  return 1
}

catalog_defaults_into_map() {
  local defaults_output=$1
  local target_map_name=$2
  local -n target_map=$target_map_name
  local package default_channel

  target_map=()
  while IFS=$'\t' read -r package default_channel; do
    [ -n "$package" ] || continue
    target_map["$package"]=$default_channel
  done <<< "$defaults_output"
}

selected_catalog_packages() {
  local catalog_image=$1
  local defaults_output=$2
  local target_array_name=$3
  local -n target_array=$target_array_name
  local package spec specs_text
  local -A seen=()

  target_array=()
  if [ "${TUI_WHOLE_CATALOG[$catalog_image]:-false}" = true ]; then
    while IFS=$'\t' read -r package _; do
      [ -n "$package" ] || continue
      target_array+=("$package")
    done <<< "$defaults_output"
    return
  fi

  specs_text=${TUI_CATALOG_PACKAGE_SPECS[$catalog_image]}
  while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    package=${spec%%:*}
    [[ -v seen["$package"] ]] && continue
    target_array+=("$package")
    seen["$package"]=1
  done <<< "$specs_text"
}

catalog_package_spec() {
  local catalog_image=$1
  local wanted_package=$2
  local spec specs_text

  TUI_CATALOG_PACKAGE_SPEC=$wanted_package
  [ "${TUI_WHOLE_CATALOG[$catalog_image]:-false}" != true ] || return
  specs_text=${TUI_CATALOG_PACKAGE_SPECS[$catalog_image]}
  while IFS= read -r spec; do
    [ "${spec%%:*}" = "$wanted_package" ] || continue
    TUI_CATALOG_PACKAGE_SPEC=$spec
    return
  done <<< "$specs_text"
}

append_unique_value() {
  local array_name=$1
  local value=$2
  local -n values=$array_name
  local existing

  for existing in "${values[@]}"; do
    [ "$existing" != "$value" ] || return
  done
  values+=("$value")
}

operator_version_available() {
  local wanted=$1
  local version

  for version in "${TUI_OPERATOR_VERSIONS[@]}"; do
    [ "$version" != "$wanted" ] || return 0
  done
  return 1
}

build_retained_upgrade_spec() {
  local source_catalog=$1
  local target_catalog=$2
  local package=$3
  local configured_channels=$4
  local target_channel=$5
  local pending_mins_name=$6
  local pending_maxes_name=$7
  local -n pending_mins=$pending_mins_name
  local -n pending_maxes=$pending_maxes_name
  local source_metadata target_metadata current_channel current_version target_version
  local source_key target_key existing_min existing_max lowest_version joined_channels
  local retained_detail="" warning_text=""
  local -a current_channels=() retained_channels=("$target_channel")

  RETAINED_UPGRADE_SPEC=""
  RETAINED_UPGRADE_DETAIL=""
  RETAINED_UPGRADE_WARNING=""
  RETAINED_UPGRADE_CURRENT_COUNT=0

  if ! load_tui_package_metadata "$source_catalog" "$package"; then
    return 1
  fi
  source_metadata=$TUI_PACKAGE_METADATA
  if ! load_tui_package_metadata "$target_catalog" "$package"; then
    return 1
  fi
  target_metadata=$TUI_PACKAGE_METADATA
  target_version=$(channel_head_from_metadata "$target_channel" <<< "$target_metadata")
  [ -n "$target_version" ] || return 1

  operator_channel_key "$target_catalog" "$package" "$target_channel"
  target_key=$OPERATOR_CHANNEL_KEY
  pending_mins["$target_key"]=$target_version
  pending_maxes["$target_key"]=$target_version

  IFS=',' read -r -a current_channels <<< "$configured_channels"
  for current_channel in "${current_channels[@]}"; do
    [ -n "$current_channel" ] || continue
    operator_channel_key "$source_catalog" "$package" "$current_channel"
    source_key=$OPERATOR_CHANNEL_KEY
    existing_min=${TUI_OPERATOR_CHANNEL_MIN_VERSIONS[$source_key]:-}
    existing_max=${TUI_OPERATOR_CHANNEL_MAX_VERSIONS[$source_key]:-}
    if [ -n "$existing_min" ] && [ "$existing_min" = "$existing_max" ]; then
      current_version=$existing_min
    elif [ -n "$existing_max" ]; then
      current_version=$existing_max
    else
      current_version=$(channel_head_from_metadata "$current_channel" <<< "$source_metadata")
    fi
    if [ -z "$current_version" ]; then
      warning_text+=$'\n'"  • $package / $current_channel: current version could not be determined"
      continue
    fi
    if ! channel_exists_in_metadata "$current_channel" <<< "$target_metadata"; then
      warning_text+=$'\n'"  • $package / $current_channel @ $current_version: channel is unavailable in the target catalog"
      continue
    fi
    if ! load_tui_operator_versions "$target_catalog" "$package" "$current_channel" || \
      ! operator_version_available "$current_version"; then
      warning_text+=$'\n'"  • $package / $current_channel @ $current_version: version is unavailable in the target catalog"
      continue
    fi

    operator_channel_key "$target_catalog" "$package" "$current_channel"
    target_key=$OPERATOR_CHANNEL_KEY
    if [ "$current_channel" = "$target_channel" ]; then
      lowest_version=$(printf '%s\n' "$current_version" "$target_version" | sort -V | head -n1)
      pending_mins["$target_key"]=$lowest_version
      if [ "$lowest_version" = "$current_version" ]; then
        pending_maxes["$target_key"]=$target_version
      else
        pending_maxes["$target_key"]=$current_version
      fi
    else
      append_unique_value retained_channels "$current_channel"
      pending_mins["$target_key"]=$current_version
      pending_maxes["$target_key"]=$current_version
    fi
    [ -z "$retained_detail" ] || retained_detail+=", "
    retained_detail+="$current_channel @ $current_version"
    RETAINED_UPGRADE_CURRENT_COUNT=$((RETAINED_UPGRADE_CURRENT_COUNT + 1))
  done

  joined_channels=$(IFS=,; echo "${retained_channels[*]}")
  RETAINED_UPGRADE_SPEC="$package:$joined_channels"
  RETAINED_UPGRADE_DETAIL="$package: ${retained_detail:-no current bundle retained}; target $target_channel @ $target_version"
  RETAINED_UPGRADE_WARNING=$warning_text
}

# -----------------------------------------------------------------------------
# Operator default-channel upgrades
# -----------------------------------------------------------------------------

upgrade_tui_loaded_catalog() {
  local source_catalog target_catalog source_version target_version default_target_version
  local source_major source_minor lowest_version catalog package cache_key
  local old_default new_default configured_channels original_spec source_defaults_output target_defaults_output
  local report changed_text="" missing_text="" target_specs_text="" apply_label retention_label
  local retained_text="" retention_warning_text=""
  local refresh_current=false keep_current_versions=false
  local changed_count=0 unchanged_count=0 missing_count=0 retained_count=0 retention_warning_count=0
  local -a source_packages=() target_specs=() upgraded_packages=()
  local -A source_defaults=() target_defaults=() retain_version_packages=()
  local -A retained_channel_mins=() retained_channel_maxes=()

  if [ -z "$TUI_LOADED_FILE" ]; then
    tui_error "Load an existing ImageSetConfiguration before running an Operator upgrade."
    return 1
  fi
  if [ "${#TUI_CATALOG_IMAGES[@]}" -eq 0 ]; then
    tui_error "The loaded configuration does not contain any Operator catalogs."
    return 1
  fi
  if ! choose_one "Choose the Operator catalog whose selected packages should be upgraded:" \
    "${TUI_CATALOG_IMAGES[@]}"; then
    return 1
  fi
  source_catalog=$CHOSEN_VALUE
  source_version=$(catalog_version "$source_catalog")
  if ! target_catalog=$(catalog_image_for_version "$source_catalog" "$source_version"); then
    tui_error "The selected catalog does not use a version tag such as :v4.20, so its upgrade image cannot be determined automatically."
    return 1
  fi

  IFS=. read -r source_major source_minor <<< "$source_version"
  default_target_version="$source_major.$((10#$source_minor + 1))"
  if ! choose_one "Where should package default channels be refreshed?" \
    "Refresh defaults in the current catalog (v$source_version)" \
    "Use a newer catalog version"; then
    return 1
  fi
  if [ "$CHOSEN_VALUE" = "Refresh defaults in the current catalog (v$source_version)" ]; then
    refresh_current=true
    target_version=$source_version
  else
    if ! choose_tui_version "Target OpenShift version for the upgraded Operator catalog:" \
      "$default_target_version"; then
      return 1
    fi
    target_version=$TUI_SELECTED_VERSION
  fi
  target_catalog=$(catalog_image_for_version "$source_catalog" "$target_version")
  if [ "$refresh_current" != true ]; then
    if [ "$target_version" = "$source_version" ]; then
      tui_error "Choose the current-catalog refresh option to update defaults without changing catalog versions."
      return 1
    fi
    lowest_version=$(printf '%s\n' "$source_version" "$target_version" | sort -V | head -n1)
    if [ "$lowest_version" != "$source_version" ]; then
      tui_error "Target version $target_version is older than source version $source_version."
      return 1
    fi
  fi
  for catalog in "${TUI_CATALOG_IMAGES[@]}"; do
    if [ "$refresh_current" != true ] && [ "$catalog" = "$target_catalog" ]; then
      tui_error "The target catalog is already selected:\n\n$target_catalog\n\nEdit that catalog directly or choose another target version."
      return 1
    fi
  done

  if ! load_catalog_package_defaults "$source_catalog"; then
    tui_error "Could not load current package defaults from '$source_catalog'."
    return 1
  fi
  source_defaults_output=$CATALOG_PACKAGE_DEFAULTS_OUTPUT
  catalog_defaults_into_map "$source_defaults_output" source_defaults
  for package in "${!source_defaults[@]}"; do
    CACHED_DEFAULT_CHANNELS["$source_catalog|$package"]=${source_defaults[$package]}
  done

  if [ "$refresh_current" != true ]; then
    TUI_CATALOG_VERSIONS["$target_catalog"]=$target_version
  fi
  if ! load_catalog_package_defaults "$target_catalog"; then
    [ "$refresh_current" = true ] || unset 'TUI_CATALOG_VERSIONS[$target_catalog]'
    tui_error "Could not load package defaults from target catalog '$target_catalog'."
    return 1
  fi
  target_defaults_output=$CATALOG_PACKAGE_DEFAULTS_OUTPUT
  catalog_defaults_into_map "$target_defaults_output" target_defaults
  for package in "${!target_defaults[@]}"; do
    new_default=${target_defaults[$package]}
    CACHED_DEFAULT_CHANNELS["$target_catalog|$package"]=$new_default
  done
  selected_catalog_packages "$source_catalog" "$source_defaults_output" source_packages
  if [ "${TUI_WHOLE_CATALOG[$source_catalog]:-false}" != true ]; then
    retention_label="Keep current and target bundle versions for selected packages"
    if ! choose_one "Should any packages keep both their current and target bundles in the upgraded catalog?\n\nUse this when an Operator upgrade path requires both bundles in the same pruned catalog." \
      "Use upgraded defaults only" \
      "$retention_label"; then
      [ "$refresh_current" = true ] || unset 'TUI_CATALOG_VERSIONS[$target_catalog]'
      return 1
    fi
    if [ "$CHOSEN_VALUE" = "$retention_label" ]; then
      keep_current_versions=true
      if ! edit_tui_package_matches retain_version_packages \
        "Select packages that must retain both current and target bundle versions in the upgraded catalog." \
        "$source_catalog" "${source_packages[@]}"; then
        [ "$refresh_current" = true ] || unset 'TUI_CATALOG_VERSIONS[$target_catalog]'
        return 1
      fi
      if [ "${#retain_version_packages[@]}" -eq 0 ]; then
        [ "$refresh_current" = true ] || unset 'TUI_CATALOG_VERSIONS[$target_catalog]'
        tui_error "Select at least one package to retain, or choose upgraded defaults only."
        return 1
      fi
    fi
  fi

  for package in "${source_packages[@]}"; do
    old_default=${source_defaults[$package]:-}
    catalog_package_spec "$source_catalog" "$package"
    original_spec=$TUI_CATALOG_PACKAGE_SPEC
    cache_key="$source_catalog|$package"
    if [[ -v TUI_IMPORTED_PACKAGE_DEFAULTS["$cache_key"] ]] && \
      [ -n "${TUI_IMPORTED_PACKAGE_DEFAULTS[$cache_key]}" ]; then
      old_default=${TUI_IMPORTED_PACKAGE_DEFAULTS[$cache_key]}
    fi
    if [[ "$original_spec" == *:* ]]; then
      configured_channels=${original_spec#*:}
      if [[ ! -v TUI_IMPORTED_PACKAGE_DEFAULTS["$cache_key"] ]] || \
        [ -z "${TUI_IMPORTED_PACKAGE_DEFAULTS[$cache_key]}" ]; then
        old_default=${configured_channels%%,*}
      fi
    fi

    new_default=${target_defaults[$package]:-}
    if [ -z "$new_default" ]; then
      missing_count=$((missing_count + 1))
      missing_text+=$'\n'"  • $package"
      if [ "$refresh_current" = true ] && \
        [ "${TUI_WHOLE_CATALOG[$source_catalog]:-false}" != true ]; then
        target_specs+=("$original_spec")
      fi
      continue
    fi
    if [ "${TUI_WHOLE_CATALOG[$source_catalog]:-false}" != true ]; then
      if [ "$keep_current_versions" = true ] && [[ -v retain_version_packages["$package"] ]]; then
        configured_channels=$old_default
        [[ "$original_spec" != *:* ]] || configured_channels=${original_spec#*:}
        if build_retained_upgrade_spec "$source_catalog" "$target_catalog" "$package" \
          "$configured_channels" "$new_default" retained_channel_mins retained_channel_maxes; then
          target_specs+=("$RETAINED_UPGRADE_SPEC")
          if [ "$RETAINED_UPGRADE_CURRENT_COUNT" -gt 0 ]; then
            retained_count=$((retained_count + 1))
            retained_text+=$'\n'"  • $RETAINED_UPGRADE_DETAIL"
          fi
          if [ -n "$RETAINED_UPGRADE_WARNING" ]; then
            retention_warning_count=$((retention_warning_count + 1))
            retention_warning_text+="$RETAINED_UPGRADE_WARNING"
          fi
        else
          target_specs+=("$package:$new_default")
          retention_warning_count=$((retention_warning_count + 1))
          retention_warning_text+=$'\n'"  • $package: bundle metadata could not be loaded; using the target default only"
        fi
      else
        target_specs+=("$package:$new_default")
      fi
      upgraded_packages+=("$package")
    fi
    if [ "$old_default" != "$new_default" ]; then
      changed_count=$((changed_count + 1))
      [ -n "$old_default" ] || old_default="unknown"
      changed_text+=$'\n'"  • $package: $old_default → $new_default"
    else
      unchanged_count=$((unchanged_count + 1))
    fi
  done

  report="Operator upgrade comparison\n\nSource: $source_catalog\nTarget: $target_catalog"
  report+=$'\n\n'"Packages receiving new default channels: $changed_count"
  if [ "$changed_count" -gt 0 ]; then
    report+="$changed_text"
  else
    report+=$'\n'"  None"
  fi
  report+=$'\n\n'"Packages already using the target default: $unchanged_count"
  report+=$'\n'"Packages unavailable or without a default in the target catalog: $missing_count"
  [ "$missing_count" -eq 0 ] || report+="$missing_text"
  if [ "$keep_current_versions" = true ]; then
    report+=$'\n\n'"Packages keeping current and target bundles in the upgraded catalog: $retained_count"
    if [ "$retained_count" -gt 0 ]; then
      report+="$retained_text"
    else
      report+=$'\n'"  None"
    fi
    report+=$'\n\n'"Retention warnings: $retention_warning_count"
    [ "$retention_warning_count" -eq 0 ] || report+="$retention_warning_text"
  fi
  if [ "$refresh_current" = true ]; then
    if [ "${TUI_WHOLE_CATALOG[$source_catalog]:-false}" = true ]; then
      report+=$'\n\n'"This configuration includes the entire catalog, so it already follows the current defaults without package-level changes."
    else
      report+=$'\n\n'"The selected packages will be updated in place within the current catalog version."
    fi
  else
    report+=$'\n\n'"The source catalog will be kept and the target catalog will be added for the upgrade."
  fi

  if ! tui_message "Operator upgrade changes" "$report" Continue; then
    [ "$refresh_current" = true ] || unset 'TUI_CATALOG_VERSIONS[$target_catalog]'
    return 1
  fi
  if [ "$refresh_current" = true ] && \
    [ "${TUI_WHOLE_CATALOG[$source_catalog]:-false}" = true ]; then
    return 0
  fi
  if [ "$refresh_current" = true ]; then
    apply_label="Update packages in the current catalog"
  else
    apply_label="Add the upgraded catalog"
  fi
  if ! choose_one "Apply this Operator upgrade to the in-memory configuration?" \
    "$apply_label" \
    "Cancel without changing the configuration"; then
    [ "$refresh_current" = true ] || unset 'TUI_CATALOG_VERSIONS[$target_catalog]'
    return 1
  fi
  if [ "$CHOSEN_VALUE" != "$apply_label" ]; then
    [ "$refresh_current" = true ] || unset 'TUI_CATALOG_VERSIONS[$target_catalog]'
    return 1
  fi

  if [ "${TUI_WHOLE_CATALOG[$source_catalog]:-false}" = true ]; then
    save_entire_tui_catalog "$target_catalog"
  else
    if [ "${#target_specs[@]}" -eq 0 ]; then
      [ "$refresh_current" = true ] || unset 'TUI_CATALOG_VERSIONS[$target_catalog]'
      tui_error "None of the selected packages are available in the target catalog, so no upgraded catalog was added."
      return 1
    fi
    printf -v target_specs_text '%s\n' "${target_specs[@]}"
    TUI_CATALOG_PACKAGE_SPECS["$target_catalog"]=${target_specs_text%$'\n'}
    TUI_WHOLE_CATALOG["$target_catalog"]=false
  fi
  for package in "${upgraded_packages[@]}"; do
    cache_key="$target_catalog|$package"
    unset 'TUI_IMPORTED_PACKAGES[$cache_key]'
    unset 'TUI_IMPORTED_PACKAGE_DEFAULTS[$cache_key]'
    clear_operator_channel_versions "$target_catalog" "$package"
  done
  for cache_key in "${!retained_channel_mins[@]}"; do
    TUI_OPERATOR_CHANNEL_MIN_VERSIONS["$cache_key"]=${retained_channel_mins[$cache_key]}
  done
  for cache_key in "${!retained_channel_maxes[@]}"; do
    TUI_OPERATOR_CHANNEL_MAX_VERSIONS["$cache_key"]=${retained_channel_maxes[$cache_key]}
  done
  if [ "$refresh_current" = true ]; then
    tui_message "Operator defaults refreshed" \
      "Updated $target_catalog\n\nChanged default channels: $changed_count\nUnchanged default channels: $unchanged_count\nPackages retaining current and target bundles: $retained_count\nPackages retaining their existing selection: $missing_count"
  else
    TUI_CATALOG_IMAGES+=("$target_catalog")
    tui_message "Operator upgrade added" \
      "Added $target_catalog\n\nChanged default channels: $changed_count\nUnchanged default channels: $unchanged_count\nPackages retaining current and target bundles: $retained_count\nUnavailable packages omitted: $missing_count"
  fi
  return 0
}

# -----------------------------------------------------------------------------
# Main TUI navigation
# -----------------------------------------------------------------------------

tui_configure() {
  local selected_catalog selected_version already_selected menu_choice edit_mode platform_status loaded_status
  local catalog_option catalog_tag option_exists
  local -a catalogs catalog_options menu_options

  if [ "$CATALOG" != all ] && [ "$TUI_INITIAL_CATALOG_HANDLED" != true ]; then
    TUI_INITIAL_CATALOG_HANDLED=true
    if choose_tui_version "OpenShift version for the initial Operator catalog:" "$VERSION"; then
      selected_version=$TUI_SELECTED_VERSION
      selected_catalog=$(catalog_image "$CATALOG" "$selected_version")
      TUI_CATALOG_VERSIONS["$selected_catalog"]=$selected_version
      choose_catalog_edit_mode "$selected_catalog" false
      if [ "$CATALOG_EDIT_MODE" = entire ]; then
        save_entire_tui_catalog "$selected_catalog"
        TUI_CATALOG_IMAGES+=("$selected_catalog")
      elif [ "$CATALOG_EDIT_MODE" = fresh ] && configure_tui_catalog "$selected_catalog" fresh; then
        TUI_CATALOG_IMAGES+=("$selected_catalog")
      fi
    fi
  fi

  while true; do
    platform_status="not configured"
    if [ "$TUI_PLATFORM_CONFIGURED" = true ]; then
      platform_status="${#TUI_PLATFORM_CHANNELS[@]} version(s)"
    fi
    loaded_status="New configuration"
    [ -z "$TUI_LOADED_FILE" ] || loaded_status="Editing ${TUI_LOADED_FILE##*/}"
    menu_options=("$TUI_ACTION_EDIT_CONFIG")
    if [ -n "$TUI_LOADED_FILE" ]; then
      menu_options+=("$TUI_ACTION_UPGRADE_OPERATORS")
    fi
    menu_options+=("$TUI_ACTION_EDIT_PLATFORM")
    menu_options+=(
      "$TUI_ACTION_EDIT_CATALOG" \
      "$TUI_ACTION_ADD_OPERATOR_GROUP" \
      "$TUI_ACTION_BROWSE_CATALOGS" \
      "$TUI_ACTION_VIEW_SELECTIONS" \
      "$TUI_ACTION_FINISH" \
      "$TUI_ACTION_EXIT"
    )
    if ! choose_one "$loaded_status\nPlatform: $platform_status  •  Operator catalogs: ${#TUI_CATALOG_IMAGES[@]}\n\nChoose the next action:" \
      "${menu_options[@]}"; then
      continue
    fi
    menu_choice=$CHOSEN_VALUE

    case "$menu_choice" in
      "$TUI_ACTION_EDIT_CONFIG")
        if [ "$TUI_PLATFORM_CONFIGURED" = true ] || [ "${#TUI_CATALOG_IMAGES[@]}" -gt 0 ]; then
          if ! choose_one "Loading a file replaces the current in-memory selections.\nNo file will be written yet." \
            "Return to the builder" \
            "Choose a file and replace selections"; then
            continue
          fi
          [ "$CHOSEN_VALUE" = "Choose a file and replace selections" ] || continue
        fi
        select_existing_tui_config || true
        ;;
      "$TUI_ACTION_UPGRADE_OPERATORS")
        upgrade_tui_loaded_catalog || true
        ;;
      "$TUI_ACTION_EDIT_PLATFORM")
        manage_tui_platform_releases || true
        ;;
      "$TUI_ACTION_EDIT_CATALOG")
        if ! choose_tui_version "OpenShift version for the Operator catalog:" "$VERSION"; then
          continue
        fi
        selected_version=$TUI_SELECTED_VERSION
        mapfile -t catalogs < <(available_catalogs "$selected_version")
        [ "${#catalogs[@]}" -gt 0 ] || {
          tui_error "No catalogs were found for OpenShift $selected_version."
          continue
        }
        catalog_options=("${catalogs[@]}")
        for catalog_option in "${TUI_CATALOG_IMAGES[@]}"; do
          catalog_tag=${catalog_option##*:}
          if [[ "$catalog_tag" =~ ^v[0-9]+\.[0-9]+$ ]] && [ "$catalog_tag" != "v$selected_version" ]; then
            continue
          fi
          option_exists=false
          for selected_catalog in "${catalog_options[@]}"; do
            [ "$selected_catalog" != "$catalog_option" ] || option_exists=true
          done
          [ "$option_exists" = true ] || catalog_options+=("$catalog_option")
        done
        if ! choose_one "Select a catalog:" "${catalog_options[@]}"; then
          continue
        fi
        selected_catalog=$CHOSEN_VALUE
        TUI_CATALOG_VERSIONS["$selected_catalog"]=$selected_version
        already_selected=false
        edit_mode=fresh
        if [[ -v TUI_WHOLE_CATALOG["$selected_catalog"] ]]; then
          already_selected=true
        fi
        choose_catalog_edit_mode "$selected_catalog" "$already_selected"
        edit_mode=$CATALOG_EDIT_MODE
        [ "$edit_mode" != back ] || continue

        if [ "$edit_mode" = entire ]; then
          save_entire_tui_catalog "$selected_catalog"
          if [ "$already_selected" != true ]; then
            TUI_CATALOG_IMAGES+=("$selected_catalog")
          fi
          continue
        fi

        if ! configure_tui_catalog "$selected_catalog" "$edit_mode"; then
          continue
        fi
        if [ "$already_selected" != true ]; then
          TUI_CATALOG_IMAGES+=("$selected_catalog")
        fi
        ;;
      "$TUI_ACTION_ADD_OPERATOR_GROUP")
        add_tui_operator_group || true
        ;;
      "$TUI_ACTION_BROWSE_CATALOGS")
        if ! choose_tui_version "OpenShift version whose Operator catalogs you want to browse:" "$VERSION"; then
          continue
        fi
        selected_version=$TUI_SELECTED_VERSION
        mapfile -t catalogs < <(available_catalogs "$selected_version")
        browse_tui_catalogs "${catalogs[@]}"
        ;;
      "$TUI_ACTION_VIEW_SELECTIONS")
        review_tui_selections
        ;;
      "$TUI_ACTION_FINISH")
        if [ "$TUI_PLATFORM_CONFIGURED" != true ] && [ "${#TUI_CATALOG_IMAGES[@]}" -eq 0 ]; then
          tui_error "Configure platform releases or at least one operator catalog before building the YAML."
          continue
        fi
        if ! review_tui_selections Continue; then
          continue
        fi
        if [ -z "$OUTPUT_FILE" ]; then
          if ! tui_input "Output file:" "imageset-config.yaml"; then
            continue
          fi
          OUTPUT_FILE=$TUI_VALUE
          [ -n "$OUTPUT_FILE" ] || {
            tui_error "Enter an output file name."
            OUTPUT_FILE=""
            continue
          }
        fi
        CATALOG_IMAGE=${TUI_CATALOG_IMAGES[0]:-}
        return
        ;;
      "$TUI_ACTION_EXIT")
        if choose_one "Exit without writing a configuration?" \
          "Return to the builder" \
          "Exit without saving" && [ "$CHOSEN_VALUE" = "Exit without saving" ]; then
          tui_restore_terminal
          echo "Cancelled; no file was written."
          exit 0
        fi
        ;;
    esac
  done

}

# -----------------------------------------------------------------------------
# ImageSet YAML output
# -----------------------------------------------------------------------------

validate_operator_version() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]]
}

write_operator_channel_yaml() {
  local image=$1
  local package=$2
  local channel=$3
  local minimum maximum

  operator_channel_key "$image" "$package" "$channel"
  minimum=${TUI_OPERATOR_CHANNEL_MIN_VERSIONS[$OPERATOR_CHANNEL_KEY]:-}
  maximum=${TUI_OPERATOR_CHANNEL_MAX_VERSIONS[$OPERATOR_CHANNEL_KEY]:-}

  printf '      - name: %s\n' "$channel"
  if [ -n "$minimum" ]; then
    validate_operator_version "$minimum" || die "Invalid minimum Operator version '$minimum' for $package / $channel."
    printf "        minVersion: '%s'\n" "$minimum"
  fi
  if [ -n "$maximum" ]; then
    validate_operator_version "$maximum" || die "Invalid maximum Operator version '$maximum' for $package / $channel."
    printf "        maxVersion: '%s'\n" "$maximum"
  fi
}

write_package_yaml() {
  local image=$1
  local spec=$2
  local package requested_channels metadata default_channel channel cache_key
  local -a channels=()

  if [[ "$spec" == *:* ]]; then
    package=${spec%%:*}
    requested_channels=${spec#*:}
    [ -n "$requested_channels" ] || die "Package '$package' has an empty channel selection."
  else
    package=$spec
    requested_channels=""
  fi

  validate_name "package name" "$package"
  cache_key="$image|$package"
  if [[ -v SEEN_PACKAGES["$cache_key"] ]]; then
    die "Package '$package' was selected more than once in '$image'; use a comma-separated channel list."
  fi
  SEEN_PACKAGES["$cache_key"]=1

  if [ "$MODE" = tui ] && [[ -v TUI_IMPORTED_PACKAGES["$cache_key"] ]]; then
    printf '    - name: %s\n' "$package"
    default_channel=${TUI_IMPORTED_PACKAGE_DEFAULTS[$cache_key]}
    if [ -n "$default_channel" ]; then
      validate_name "default channel for $package" "$default_channel"
      printf '      defaultChannel: %s\n' "$default_channel"
    fi
    if [ -n "$requested_channels" ]; then
      printf '%s\n' '      channels:'
      IFS=',' read -r -a channels <<< "$requested_channels"
      for channel in "${channels[@]}"; do
        validate_name "channel for $package" "$channel"
        write_operator_channel_yaml "$image" "$package" "$channel"
      done
    fi
    return
  fi

  if [[ -v CACHED_DEFAULT_CHANNELS["$cache_key"] ]]; then
    default_channel=${CACHED_DEFAULT_CHANNELS[$cache_key]}
    metadata=${CACHED_PACKAGE_METADATA[$cache_key]:-}
  else
    [ "$MODE" = tui ] || echo "Resolving package: $package" >&2
    package_metadata "$image" "$package" || die "Could not query package '$package' in '$image'."
    metadata=$PACKAGE_METADATA_OUTPUT
    default_channel=$(default_channel_from_metadata <<< "$metadata")
    [ -n "$default_channel" ] || die "Package '$package' was not found in '$image'."
  fi
  validate_name "default channel for $package" "$default_channel"

  if [ -z "$requested_channels" ]; then
    requested_channels=$default_channel
  fi

  printf '    - name: %s\n' "$package"
  if [[ ",$requested_channels," != *",$default_channel,"* ]]; then
    printf '      defaultChannel: %s\n' "$default_channel"
  fi
  printf '      channels:\n'

  IFS=',' read -r -a channels <<< "$requested_channels"
  for channel in "${channels[@]}"; do
    validate_name "channel for $package" "$channel"
    if [ -n "$metadata" ]; then
      channel_exists_in_metadata "$channel" <<< "$metadata" || die "Channel '$channel' was not found for package '$package'."
    elif [ "$channel" != "$default_channel" ]; then
      die "Channel '$channel' for '$package' was not validated against catalog metadata."
    fi
    write_operator_channel_yaml "$image" "$package" "$channel"
  done
}

write_tui_platform_yaml() {
  local architecture platform_channel

  [ "$TUI_PLATFORM_CONFIGURED" = true ] || return 0
  printf '%s\n' '  platform:'
  if [ "${#TUI_PLATFORM_ARCHITECTURES[@]}" -gt 0 ]; then
    printf '%s\n' '    architectures:'
    for architecture in "${TUI_PLATFORM_ARCHITECTURES[@]}"; do
      printf '    - %s\n' "$architecture"
    done
  fi
  printf '%s\n' '    channels:'
  for platform_channel in "${TUI_PLATFORM_CHANNELS[@]}"; do
    printf '%s\n' '    - type: ocp'
    printf '      name: %s\n' "$platform_channel"
    [ -z "${TUI_PLATFORM_MIN_VERSIONS[$platform_channel]:-}" ] || \
      printf '      minVersion: %s\n' "${TUI_PLATFORM_MIN_VERSIONS[$platform_channel]}"
    [ -z "${TUI_PLATFORM_MAX_VERSIONS[$platform_channel]:-}" ] || \
      printf '      maxVersion: %s\n' "${TUI_PLATFORM_MAX_VERSIONS[$platform_channel]}"
    [ "${TUI_PLATFORM_FULL_CHANNELS[$platform_channel]:-false}" != true ] || \
      printf '%s\n' '      full: true'
  done
  printf '    graph: %s\n' "$TUI_PLATFORM_GRAPH"
}

write_tui_operator_yaml() {
  local catalog specs_text spec

  [ "${#TUI_CATALOG_IMAGES[@]}" -gt 0 ] || return 0
  [ "$TUI_PLATFORM_CONFIGURED" != true ] || printf '\n'
  printf '%s\n' '  operators:'
  for catalog in "${TUI_CATALOG_IMAGES[@]}"; do
    printf '  - catalog: %s\n' "$catalog"
    if [ "${TUI_WHOLE_CATALOG[$catalog]:-false}" != true ]; then
      printf '%s\n' '    packages:'
      specs_text=${TUI_CATALOG_PACKAGE_SPECS[$catalog]}
      while IFS= read -r spec; do
        [ -n "$spec" ] && write_package_yaml "$catalog" "$spec"
      done <<< "$specs_text"
    fi
  done
}

write_tui_preserved_yaml() {
  if [ -n "$TUI_PRESERVED_CONFIG_SUFFIX" ]; then
    printf '\n%s\n' "$TUI_PRESERVED_CONFIG_SUFFIX"
  else
    printf '\n%s\n' '  additionalImages: []'
    printf '%s\n' '  helm: {}'
  fi
}

write_cli_operator_yaml() {
  local image=$1
  local spec

  printf '%s\n' '  operators:'
  printf '  - catalog: %s\n' "$image"
  [ "${#PACKAGE_SPECS[@]}" -gt 0 ] || return 0
  printf '%s\n' '    packages:'
  for spec in "${PACKAGE_SPECS[@]}"; do
    write_package_yaml "$image" "$spec"
  done
}

generate_yaml() {
  local image=$1
  local temporary_output=$2

  {
    printf '%s\n' '---'
    printf '%s\n' 'kind: ImageSetConfiguration'
    printf '%s\n\n' 'apiVersion: mirror.openshift.io/v2alpha1'
    printf '%s\n' 'mirror:'
    if [ "$MODE" = tui ]; then
      write_tui_platform_yaml
      write_tui_operator_yaml
      write_tui_preserved_yaml
    else
      write_cli_operator_yaml "$image"
    fi
  } > "$temporary_output"
}

prepare_output_file() {
  local default_name=${1:-}

  [ -n "$OUTPUT_FILE" ] || OUTPUT_FILE=$default_name
  [ -n "$OUTPUT_FILE" ] || die "An output file name is required."
  [[ "$OUTPUT_FILE" == /* ]] || OUTPUT_FILE="$ORIGINAL_DIR/$OUTPUT_FILE"
  mkdir -p "$(dirname "$OUTPUT_FILE")"
  [ ! -d "$OUTPUT_FILE" ] || die "Output path '$OUTPUT_FILE' is a directory."
}

run_tui_mode() {
  local temporary_yaml="$WORK_DIR/imageset-config.yaml"

  while true; do
    tui_configure
    prepare_output_file
    SEEN_PACKAGES=()
    generate_yaml "$CATALOG_IMAGE" "$temporary_yaml"
    if ! tui_message "Configuration preview" "$(<"$temporary_yaml")" Continue; then
      continue
    fi
    if ! choose_one "The configuration is ready. What would you like to do?" \
      "Write the configuration" \
      "Return to the builder" \
      "Cancel without writing"; then
      continue
    fi
    case "$CHOSEN_VALUE" in
      "Write the configuration") break ;;
      "Return to the builder") continue ;;
      "Cancel without writing")
        tui_restore_terminal
        echo "Cancelled; no file was written."
        return
        ;;
    esac
  done
  mv -f "$temporary_yaml" "$OUTPUT_FILE"
  tui_restore_terminal
  echo "ImageSetConfiguration written to: $OUTPUT_FILE"
}

run_yaml_mode() {
  local catalog_image temporary_yaml="$WORK_DIR/imageset-config.yaml"

  catalog_image=$(catalog_image "$CATALOG")
  prepare_output_file "imageset-config-v$VERSION.yaml"
  SEEN_PACKAGES=()
  generate_yaml "$catalog_image" "$temporary_yaml"
  mv -f "$temporary_yaml" "$OUTPUT_FILE"
  echo "ImageSetConfiguration written to: $OUTPUT_FILE"
}

run_list_mode() {
  local catalog_image
  local -a catalogs=()

  if [ "$CATALOG" = all ]; then
    mapfile -t catalogs < <(available_catalogs)
    for catalog_image in "${catalogs[@]}"; do
      fetch_catalog "$catalog_image"
    done
  else
    fetch_catalog "$(catalog_image "$CATALOG")"
  fi
}

# -----------------------------------------------------------------------------
# Built-in regression tests
# -----------------------------------------------------------------------------

SELF_TEST_COUNT=0
SELF_TEST_FAILURES=0

self_test_equal() {
  local label=$1
  local expected=$2
  local actual=$3

  SELF_TEST_COUNT=$((SELF_TEST_COUNT + 1))
  if [ "$actual" != "$expected" ]; then
    printf 'not ok %d - %s\n  expected: %s\n  actual:   %s\n' \
      "$SELF_TEST_COUNT" "$label" "$expected" "$actual" >&2
    SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    return
  fi
  printf 'ok %d - %s\n' "$SELF_TEST_COUNT" "$label"
}

self_test_contains() {
  local label=$1
  local haystack=$2
  local needle=$3

  SELF_TEST_COUNT=$((SELF_TEST_COUNT + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'not ok %d - %s\n  missing: %s\n' \
      "$SELF_TEST_COUNT" "$label" "$needle" >&2
    SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
    return
  fi
  printf 'ok %d - %s\n' "$SELF_TEST_COUNT" "$label"
}

run_self_tests() {
  local fixture="$WORK_DIR/self-test-imageset.yaml"
  local generated="$WORK_DIR/self-test-generated.yaml"
  local catalog="registry.redhat.io/redhat/redhat-operator-index:v4.20"
  local group_catalog="registry.redhat.io/redhat/redhat-operator-index:v4.19"
  local metadata package_yaml generated_yaml selected odf_html parsed_odf
  local -a test_requested_group=() test_default_group=()
  local -a test_available_group=() test_missing_group=()
  local -A test_pending_mins=() test_pending_maxes=()
  local -A test_retained_mins=() test_retained_maxes=()
  local -A test_selected_group=()

  metadata=$'NAME  DISPLAY NAME  DEFAULT CHANNEL\nadvanced-cluster-management  example  release-2.17\n\nPACKAGE  CHANNEL  HEAD\nadvanced-cluster-management  release-2.16  advanced-cluster-management.v2.16.2\nadvanced-cluster-management  release-2.17  advanced-cluster-management.v2.17.0'

  self_test_equal "catalog short name resolution" "$catalog" \
    "$(catalog_image redhat-operator-index 4.20)"
  self_test_equal "catalog tag version parsing" "4.20" "$(catalog_version "$catalog")"
  self_test_equal "default channel parsing" "release-2.17" \
    "$(default_channel_from_metadata <<< "$metadata")"
  self_test_equal "channel head version parsing" "2.16.2" \
    "$(channel_head_from_metadata release-2.16 <<< "$metadata")"
  self_test_equal "channel enumeration" $'release-2.16\nrelease-2.17' \
    "$(available_channels_from_metadata <<< "$metadata")"

  self_test_equal "ODF documentation URL uses selected version" \
    "https://docs.redhat.com/en/documentation/red_hat_openshift_data_foundation/4.19/html/planning_your_deployment/disconnected-environment_rhodf" \
    "$(odf_operator_bundle_url 4.19)"
  odf_html='<h2>Packages to include for OpenShift Data Foundation</h2><p>Prune <code>redhat-operator</code>.</p><ul><li><code>ocs-operator</code></li><li><code>odf-operator</code></li><li><code>mcg-operator</code></li></ul><p>Only for local storage deployments:</p><code>local-storage-operator</code>'
  parsed_odf=$(odf_packages_from_html <<< "$odf_html")
  self_test_equal "ODF documentation package parsing" \
    $'ocs-operator\nodf-operator\nmcg-operator' "$parsed_odf"
  self_test_contains "ODF fallback includes the core operator" \
    "${ODF_OPERATOR_BUNDLE_FALLBACK[*]}" "odf-operator"

  TUI_CATALOG_PACKAGES=(odf-operator local-storage-operator)
  test_requested_group=(odf-operator local-storage-operator unavailable-operator)
  test_default_group=(odf-operator)
  filter_tui_operator_group_packages \
    test_requested_group test_default_group test_available_group \
    test_missing_group test_selected_group
  self_test_equal "Operator group filters against catalog version" \
    "odf-operator local-storage-operator" "${test_available_group[*]}"
  self_test_equal "Operator group reports unavailable packages" \
    "unavailable-operator" "${test_missing_group[*]}"
  self_test_equal "conditional group packages start cleared" \
    "1" "${#test_selected_group[@]}"

  TUI_CATALOG_PACKAGE_SPECS["$group_catalog"]="existing-operator:stable"
  CACHED_DEFAULT_CHANNELS["$group_catalog|existing-operator"]=stable
  CACHED_DEFAULT_CHANNELS["$group_catalog|odf-operator"]=stable-4.19
  merge_tui_operator_group_packages "$group_catalog" \
    existing-operator odf-operator odf-operator
  self_test_equal "Operator group preserves existing package spec" \
    "existing-operator:stable" \
    "${TUI_CATALOG_PACKAGE_SPECS[$group_catalog]%%$'\n'*}"
  self_test_contains "Operator group adds catalog default channel" \
    "${TUI_CATALOG_PACKAGE_SPECS[$group_catalog]}" \
    "odf-operator:stable-4.19"
  self_test_equal "Operator group deduplicates selected packages" \
    "1" "$OPERATOR_GROUP_ADDED_COUNT"
  unset 'TUI_CATALOG_PACKAGE_SPECS[$group_catalog]'
  unset 'TUI_WHOLE_CATALOG[$group_catalog]'

  selected=""
  if parse_number_selection "1,3-4" 5; then
    printf -v selected '%s,' "${SELECTED_INDICES[@]}"
    selected=${selected%,}
  fi
  self_test_equal "numeric checklist range parsing" "0,2,3" "$selected"

  printf '%s\n' \
    '---' \
    'kind: ImageSetConfiguration' \
    'apiVersion: mirror.openshift.io/v2alpha1' \
    'mirror:' \
    '  operators:' \
    "  - catalog: $catalog" \
    '    packages:' \
    '    - name: advanced-cluster-management' \
    '      defaultChannel: release-2.17' \
    '      channels:' \
    '      - name: release-2.16' \
    "        minVersion: '2.16.2'" \
    "        maxVersion: '2.16.2'" \
    '  additionalImages: []' \
    '  helm: {}' > "$fixture"

  MODE=tui
  load_tui_config "$fixture"
  self_test_equal "loaded package selection" \
    "advanced-cluster-management:release-2.16" \
    "${TUI_CATALOG_PACKAGE_SPECS[$catalog]:-}"
  self_test_equal "loaded exact minimum version" "2.16.2" \
    "${TUI_OPERATOR_CHANNEL_MIN_VERSIONS[$catalog|advanced-cluster-management|release-2.16]:-}"
  self_test_equal "loaded exact maximum version" "2.16.2" \
    "${TUI_OPERATOR_CHANNEL_MAX_VERSIONS[$catalog|advanced-cluster-management|release-2.16]:-}"

  SEEN_PACKAGES=()
  package_yaml=$(write_package_yaml "$catalog" \
    "advanced-cluster-management:release-2.16")
  self_test_contains "package YAML writes selected channel" "$package_yaml" \
    "      - name: release-2.16"
  self_test_contains "package YAML writes exact minimum" "$package_yaml" \
    "        minVersion: '2.16.2'"
  self_test_contains "package YAML writes exact maximum" "$package_yaml" \
    "        maxVersion: '2.16.2'"

  SEEN_PACKAGES=()
  generate_yaml "" "$generated"
  generated_yaml=$(<"$generated")
  self_test_contains "generated YAML preserves additional images" "$generated_yaml" \
    "  additionalImages: []"
  self_test_contains "generated YAML preserves Helm settings" "$generated_yaml" \
    "  helm: {}"

  # These query/UI mocks are intentionally last; --self-test exits immediately
  # after this function, so production functions are never called afterward.
  unset 'CACHED_CURRENT_RELEASES[x86_64|eus-4.20]'
  run_with_progress() {
    QUERY_OUTPUT=$'4.20.17\n4.20.19\n4.20.18'
  }
  resolve_current_release eus-4.20 amd64
  self_test_equal "EUS current release resolution" "4.20.19" \
    "$RESOLVED_CURRENT_RELEASE"
  self_test_equal "release architecture mapping" "x86_64" \
    "$RESOLVED_CURRENT_RELEASE_ARCH"

  load_tui_package_metadata() {
    if [[ "$1" == *:v4.20 ]]; then
      TUI_PACKAGE_METADATA=$'PACKAGE  CHANNEL  HEAD\nodf-operator  stable-4.20  odf-operator.v4.20.8-rhodf\nexample-operator  stable  example-operator.v1.2.0'
    else
      TUI_PACKAGE_METADATA=$'PACKAGE  CHANNEL  HEAD\nodf-operator  stable-4.20  odf-operator.v4.20.9-rhodf\nodf-operator  stable-4.21  odf-operator.v4.21.3-rhodf\nexample-operator  stable  example-operator.v1.4.0'
    fi
  }
  load_tui_operator_versions() {
    case "$3" in
      stable-4.20) TUI_OPERATOR_VERSIONS=(4.20.9-rhodf 4.20.8-rhodf) ;;
      stable-4.21) TUI_OPERATOR_VERSIONS=(4.21.3-rhodf) ;;
      stable) TUI_OPERATOR_VERSIONS=(1.4.0 1.3.0 1.2.0) ;;
    esac
  }
  build_retained_upgrade_spec \
    registry.redhat.io/redhat/redhat-operator-index:v4.20 \
    registry.redhat.io/redhat/redhat-operator-index:v4.21 \
    odf-operator stable-4.20 stable-4.21 \
    test_retained_mins test_retained_maxes
  self_test_equal "retained upgrade keeps both ODF channels" \
    "odf-operator:stable-4.21,stable-4.20" "$RETAINED_UPGRADE_SPEC"
  self_test_equal "retained upgrade pins current ODF bundle" "4.20.8-rhodf" \
    "${test_retained_mins[registry.redhat.io/redhat/redhat-operator-index:v4.21|odf-operator|stable-4.20]:-}"
  self_test_equal "retained upgrade pins target ODF bundle" "4.21.3-rhodf" \
    "${test_retained_maxes[registry.redhat.io/redhat/redhat-operator-index:v4.21|odf-operator|stable-4.21]:-}"

  test_retained_mins=()
  test_retained_maxes=()
  build_retained_upgrade_spec \
    registry.redhat.io/redhat/redhat-operator-index:v4.20 \
    registry.redhat.io/redhat/redhat-operator-index:v4.21 \
    example-operator stable stable \
    test_retained_mins test_retained_maxes
  self_test_equal "shared-channel retention uses one channel" \
    "example-operator:stable" "$RETAINED_UPGRADE_SPEC"
  self_test_equal "shared-channel retention starts at current bundle" "1.2.0" \
    "${test_retained_mins[registry.redhat.io/redhat/redhat-operator-index:v4.21|example-operator|stable]:-}"
  self_test_equal "shared-channel retention ends at target bundle" "1.4.0" \
    "${test_retained_maxes[registry.redhat.io/redhat/redhat-operator-index:v4.21|example-operator|stable]:-}"

  SELF_TEST_MENU_RESPONSES=("Choose a specific version" "2.16.1")
  SELF_TEST_MENU_INDEX=0
  choose_many() {
    CHOSEN_VALUES=(release-2.16)
  }
  choose_one() {
    CHOSEN_VALUE=${SELF_TEST_MENU_RESPONSES[$SELF_TEST_MENU_INDEX]}
    SELF_TEST_MENU_INDEX=$((SELF_TEST_MENU_INDEX + 1))
  }
  load_tui_operator_versions() {
    TUI_OPERATOR_VERSIONS=(2.16.2 2.16.1 2.16.0)
  }
  choose_tui_package_channels "$catalog" advanced-cluster-management release-2.17 \
    "advanced-cluster-management:release-2.16" "$metadata" \
    test_pending_mins test_pending_maxes
  self_test_equal "custom channel selection" "release-2.16" \
    "$TUI_SELECTED_PACKAGE_CHANNELS"
  self_test_equal "specific version selection minimum" "2.16.1" \
    "${test_pending_mins[$catalog|advanced-cluster-management|release-2.16]:-}"
  self_test_equal "specific version selection maximum" "2.16.1" \
    "${test_pending_maxes[$catalog|advanced-cluster-management|release-2.16]:-}"

  tui_message() {
    return 0
  }
  TUI_PLATFORM_CONFIGURED=true
  TUI_PLATFORM_ARCHITECTURES=(amd64)
  TUI_PLATFORM_CHANNELS=(stable-4.19 eus-4.20)
  TUI_PLATFORM_VERSIONS[stable-4.19]=4.19
  TUI_PLATFORM_VERSIONS[eus-4.20]=4.20
  TUI_PLATFORM_CURRENT_VERSIONS[stable-4.19]=4.19.37
  TUI_PLATFORM_CURRENT_VERSIONS[eus-4.20]=4.20.29
  SELF_TEST_MENU_RESPONSES=(
    "OpenShift 4.19 — stable-4.19"
    "Remove 4.19 / stable-4.19"
  )
  SELF_TEST_MENU_INDEX=0
  remove_tui_platform_release
  self_test_equal "remove one Platform release" "eus-4.20" \
    "${TUI_PLATFORM_CHANNELS[*]}"
  self_test_equal "remaining Platform stays configured" "true" \
    "$TUI_PLATFORM_CONFIGURED"
  self_test_equal "removed Platform state is cleared" "" \
    "${TUI_PLATFORM_CURRENT_VERSIONS[stable-4.19]:-}"

  SELF_TEST_MENU_RESPONSES=(
    "OpenShift 4.20 — eus-4.20"
    "Remove 4.20 / eus-4.20"
  )
  SELF_TEST_MENU_INDEX=0
  remove_tui_platform_release
  self_test_equal "removing final Platform clears configuration" "false" \
    "$TUI_PLATFORM_CONFIGURED"
  self_test_equal "removing final Platform clears architectures" "0" \
    "${#TUI_PLATFORM_ARCHITECTURES[@]}"

  SELF_TEST_PLATFORM_REMOVE_COUNT=0
  remove_tui_platform_release() {
    SELF_TEST_PLATFORM_REMOVE_COUNT=$((SELF_TEST_PLATFORM_REMOVE_COUNT + 1))
  }
  TUI_PLATFORM_CONFIGURED=true
  TUI_PLATFORM_CHANNELS=(stable-4.20)
  SELF_TEST_MENU_RESPONSES=("Remove a Platform release")
  SELF_TEST_MENU_INDEX=0
  manage_tui_platform_releases
  self_test_equal "Platform management routes to removal" "1" \
    "$SELF_TEST_PLATFORM_REMOVE_COUNT"

  SELF_TEST_MENU_RESPONSES=("$TUI_ACTION_VIEW_SELECTIONS" "$TUI_ACTION_FINISH")
  SELF_TEST_MENU_INDEX=0
  SELF_TEST_REVIEW_COUNT=0
  review_tui_selections() {
    SELF_TEST_REVIEW_COUNT=$((SELF_TEST_REVIEW_COUNT + 1))
  }
  CATALOG=all
  TUI_PLATFORM_CONFIGURED=true
  TUI_PLATFORM_CHANNELS=(stable-4.20)
  OUTPUT_FILE="$WORK_DIR/self-test-output.yaml"
  tui_configure
  self_test_equal "main menu labels dispatch to their actions" "2" \
    "$SELF_TEST_REVIEW_COUNT"

  if [ "$SELF_TEST_FAILURES" -gt 0 ]; then
    printf '\n%d of %d self-tests failed.\n' "$SELF_TEST_FAILURES" "$SELF_TEST_COUNT" >&2
    return 1
  fi
  printf '\nAll %d self-tests passed.\n' "$SELF_TEST_COUNT"
}

# -----------------------------------------------------------------------------
# Argument parsing and mode dispatch
# -----------------------------------------------------------------------------

while [ "$#" -gt 0 ]; do
  case "$1" in
    -v|--version)
      require_value "$@"
      VERSION=$2
      shift 2
      ;;
    -c|--catalog)
      require_value "$@"
      CATALOG=$2
      shift 2
      ;;
    -y|--yaml)
      MODE=yaml
      shift
      ;;
    -t|--tui)
      MODE=tui
      shift
      ;;
    --self-test)
      MODE=self-test
      shift
      ;;
    -p|--package)
      shift
      [ "$#" -gt 0 ] && [[ "$1" != -* ]] || die "Option --package requires at least one package name."
      while [ "$#" -gt 0 ] && [[ "$1" != -* ]]; do
        PACKAGE_SPECS+=("$1")
        shift
      done
      ;;
    -o|--output)
      require_value "$@"
      OUTPUT_FILE=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1. Run $(basename "$0") --help for usage."
      ;;
  esac
done

ORIGINAL_DIR=$(pwd -P)
WORK_DIR=$(mktemp -d "$ORIGINAL_DIR/.catalog-fetcher.XXXXXX")
cleanup() {
  rm -rf -- "$WORK_DIR"
  if [ "$MODE" = tui ] && [ "$TUI_SCREEN_INITIALIZED" = true ] && \
    [ "$TUI_TERMINAL_RESTORED" != true ]; then
    tui_restore_terminal
  fi
}
trap cleanup EXIT
export TMPDIR="$WORK_DIR/tmp"
mkdir -p "$TMPDIR"

if [ "$MODE" = tui ]; then
  command -v whiptail >/dev/null 2>&1 || die "Required command 'whiptail' was not found. Install it with: dnf install newt"
  tui_prepare_terminal_profile
  tui_initialize_screen
fi

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+$ ]] || die "Version must use major.minor format, such as 4.20."
[ "$MODE" != list ] || [ "${#PACKAGE_SPECS[@]}" -eq 0 ] || die "--package requires --yaml or --tui."
[ "$MODE" != list ] || [ -z "$OUTPUT_FILE" ] || die "--output requires --yaml or --tui."
[ "$MODE" != tui ] || [ "${#PACKAGE_SPECS[@]}" -eq 0 ] || die "--package cannot be combined with --tui; select packages interactively."
if [ "$MODE" = yaml ] && [ "$CATALOG" = all ]; then
  die "YAML mode requires one catalog selected with --catalog."
fi

if [ "$MODE" = self-test ]; then
  run_self_tests
  exit
fi

check_dependencies
cd "$WORK_DIR"

if [ "$MODE" != tui ]; then
  echo "OpenShift version: $VERSION"
  echo "Catalog: $CATALOG"
fi

case "$MODE" in
  tui) run_tui_mode ;;
  yaml) run_yaml_mode ;;
  list) run_list_mode ;;
esac
