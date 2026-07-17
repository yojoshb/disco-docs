#!/bin/bash
set -euo pipefail

VERSION="${VERSION:-4.20}"
CATALOG="${CATALOG:-all}"
MODE=list
OUTPUT_FILE=""
PACKAGE_SPECS=()
VERSION_EXPLICIT=false
declare -A CACHED_DEFAULT_CHANNELS=()
declare -A CACHED_PACKAGE_METADATA=()
declare -A CACHED_CATALOG_PACKAGE_DEFAULTS=()
declare -A CACHED_RELEASE_CHANNEL_RANGES=()
TUI_CATALOG_IMAGES=()
TUI_INITIAL_CATALOG_HANDLED=false
TUI_PLATFORM_CONFIGURED=false
TUI_PLATFORM_ARCHITECTURES=()
TUI_PLATFORM_CHANNEL=""
TUI_PLATFORM_MIN_VERSION=""
TUI_PLATFORM_MAX_VERSION=""
TUI_PLATFORM_FULL=false
TUI_PLATFORM_GRAPH=true
declare -A TUI_CATALOG_PACKAGE_SPECS=()
declare -A TUI_WHOLE_CATALOG=()
KNOWN_CATALOGS=(
  redhat-operator-index
  certified-operator-index
  community-operator-index
  redhat-marketplace-index
)

usage() {
  cat <<EOF
List OpenShift Operator catalog contents or build a complete oc-mirror v2
ImageSetConfiguration YAML file with platform and Operator content.

Usage: $(basename "$0") [OPTIONS]

Options:
  -v, --version VERSION     OpenShift version (default: 4.20)
  -c, --catalog CATALOG     Catalog short name or full image reference
                            (default for list mode: all)
  -t, --tui                 Open the interactive builder
  -y, --yaml                Generate an ImageSetConfiguration YAML file
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
package's default channel. TUI mode can combine OpenShift platform releases and
multiple Operator catalogs. Packages use their default channels without
additional queries; channel cherry-picking is opt-in. Enter 'l' at the platform
channel prompt to list available channels and their release ranges.

Examples:
  $(basename "$0") --version 4.17
  $(basename "$0") --tui --version 4.18
  $(basename "$0") --version 4.19 --catalog certified-operator-index
  $(basename "$0") --yaml --version 4.19 --catalog redhat-operator-index --package ansible-automation-platform-operator:stable-2.6
  $(basename "$0") --yaml --catalog redhat-operator-index --package lvms-operator cincinnati-operator:stable
EOF
}

die() {
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

  if [[ "$catalog" == */* ]]; then
    [[ "$catalog" == *:* ]] || die "A full catalog image reference must include a tag."
    [[ "$catalog" != *[[:space:]]* ]] || die "Catalog image references cannot contain whitespace."
    printf '%s\n' "$catalog"
  else
    validate_name "catalog name" "$catalog"
    printf 'registry.redhat.io/redhat/%s:v%s\n' "$catalog" "$VERSION"
  fi
}

catalog_filename() {
  local image=${1##*/}
  printf '%s_v%s.txt\n' "${image%%:*}" "$VERSION"
}

check_dependencies() {
  local command
  for command in oc oc-mirror awk sort mktemp; do
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

run_with_progress() {
  local label=$1
  shift
  local output_file error_file query_pid status elapsed frame_index=0
  local -a frames=('|' '/' '-' $'\\')

  output_file=$(mktemp "$WORK_DIR/query-output.XXXXXX")
  error_file=$(mktemp "$WORK_DIR/query-error.XXXXXX")
  local started_at=$SECONDS

  "$@" >"$output_file" 2>"$error_file" &
  query_pid=$!
  trap 'kill "$query_pid" 2>/dev/null || true; wait "$query_pid" 2>/dev/null || true; exit 130' INT TERM

  if [ -t 2 ]; then
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
    if [ -t 2 ]; then
      printf '\r\033[K[done] %s (%ss)\n' "$label" "$elapsed" >&2
    else
      printf '[done] %s (%ss)\n' "$label" "$elapsed" >&2
    fi
    QUERY_OUTPUT=$(<"$output_file")
  else
    if [ -t 2 ]; then
      printf '\r\033[K[failed] %s (%ss)\n' "$label" "$elapsed" >&2
    else
      printf '[failed] %s (%ss)\n' "$label" "$elapsed" >&2
    fi
    sed 's/^/oc-mirror: /' "$error_file" >&2
  fi

  rm -f -- "$output_file" "$error_file"
  return "$status"
}

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

  if ! run_with_progress "Loading channels for $package" oc mirror list operators \
    --catalog="$image" \
    --version="$VERSION" \
    --package="$package" \
    --v1; then
    return 1
  fi
  printf '%s\n' "$QUERY_OUTPUT"
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
  local catalog
  for catalog in "${KNOWN_CATALOGS[@]}"; do
    catalog_image "$catalog"
  done
}

load_catalog_package_defaults() {
  local image=$1

  if [[ -v CACHED_CATALOG_PACKAGE_DEFAULTS["$image"] ]]; then
    CATALOG_PACKAGE_DEFAULTS_OUTPUT=${CACHED_CATALOG_PACKAGE_DEFAULTS[$image]}
    echo "Using cached packages for ${image##*/}." >&2
    return
  fi

  if ! run_with_progress "Loading packages from ${image##*/}" oc mirror list operators \
    --catalog="$image" \
    --version="$VERSION" \
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

load_release_channel_ranges() {
  local architecture_filter=$1
  local cache_key="$VERSION|$architecture_filter"
  local channel releases minimum maximum
  local -a channels=() range_lines=()

  if [[ -v CACHED_RELEASE_CHANNEL_RANGES["$cache_key"] ]]; then
    RELEASE_CHANNEL_RANGES=${CACHED_RELEASE_CHANNEL_RANGES[$cache_key]}
    echo "Using cached release channels for OpenShift $VERSION ($architecture_filter)." >&2
    return
  fi

  if ! run_with_progress "Loading release channels for OpenShift $VERSION" oc mirror list releases \
    --version="$VERSION" \
    --channels \
    --v2; then
    return 1
  fi
  while IFS= read -r channel; do
    [[ "$channel" =~ ^[a-z0-9.-]+-$VERSION$ ]] && channels+=("$channel")
  done <<< "$QUERY_OUTPUT"
  [ "${#channels[@]}" -gt 0 ] || return 1

  for channel in "${channels[@]}"; do
    if ! run_with_progress "Loading release range for $channel" oc mirror list releases \
      --channel="$channel" \
      --version="$VERSION" \
      --filter-by-archs="$architecture_filter" \
      --v2; then
      continue
    fi
    releases=$(awk '/^[0-9]+\.[0-9]+\.[0-9]+([.-][a-zA-Z0-9]+)*$/ { print }' <<< "$QUERY_OUTPUT" | sort -Vu)
    [ -n "$releases" ] || continue
    minimum=$(head -n1 <<< "$releases")
    maximum=$(tail -n1 <<< "$releases")
    range_lines+=("$channel|$minimum|$maximum")
  done
  [ "${#range_lines[@]}" -gt 0 ] || return 1

  printf -v RELEASE_CHANNEL_RANGES '%s\n' "${range_lines[@]}"
  RELEASE_CHANNEL_RANGES=${RELEASE_CHANNEL_RANGES%$'\n'}
  CACHED_RELEASE_CHANNEL_RANGES["$cache_key"]=$RELEASE_CHANNEL_RANGES
}

print_release_channel_ranges() {
  local ranges=$1
  local index=1 channel minimum maximum

  echo
  printf '  %-4s %-24s %-18s %-18s\n' '#' 'CHANNEL' 'MINIMUM RELEASE' 'MAXIMUM RELEASE'
  printf '  %-4s %-24s %-18s %-18s\n' '---' '-----------------------' '-----------------' '-----------------'
  while IFS='|' read -r channel minimum maximum; do
    [ -n "$channel" ] || continue
    printf '  %-4d %-24s %-18s %-18s\n' "$index" "$channel" "$minimum" "$maximum"
    index=$((index + 1))
  done <<< "$ranges"
}

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

is_back() {
  [[ "${1,,}" = b || "${1,,}" = back ]]
}

choose_one() {
  local prompt=$1
  shift
  local -a options=("$@")
  local answer index

  while true; do
    echo
    echo "$prompt"
    for index in "${!options[@]}"; do
      printf '  %d) %s\n' "$((index + 1))" "${options[$index]}"
    done
    read -r -p "Selection [1-${#options[@]}, b=back]: " answer || die "Input was closed."
    if is_back "$answer"; then
      return 1
    fi
    if parse_number_selection "$answer" "${#options[@]}" && [ "${#SELECTED_INDICES[@]}" -eq 1 ]; then
      CHOSEN_VALUE=${options[${SELECTED_INDICES[0]}]}
      return
    fi
    echo "Choose exactly one number." >&2
  done
}

print_numbered_columns() {
  local -a options=("$@")
  local detected_width=""
  if [ -t 1 ] && command -v stty >/dev/null 2>&1; then
    detected_width=$(stty size 2>/dev/null | awk '{ print $2 }' || true)
  fi
  local terminal_width=${COLUMNS:-${detected_width:-120}}
  local count=${#options[@]}
  local digits=${#count}
  local longest=0 index option cell_width column_count value_width row_count row column

  for option in "${options[@]}"; do
    [ "${#option}" -le "$longest" ] || longest=${#option}
  done
  cell_width=$((digits + longest + 5))
  column_count=$((terminal_width / cell_width))
  [ "$column_count" -ge 1 ] || column_count=1
  [ "$column_count" -le 4 ] || column_count=4
  value_width=$((cell_width - digits - 5))
  row_count=$(((count + column_count - 1) / column_count))

  for ((row = 0; row < row_count; row++)); do
    for ((column = 0; column < column_count; column++)); do
      index=$((row + column * row_count))
      [ "$index" -lt "$count" ] || continue
      printf '  %*d) %-*s' "$digits" "$((index + 1))" "$value_width" "${options[$index]}"
    done
    printf '\n'
  done
}

print_text_columns() {
  local -a options=("$@")
  local detected_width=""
  if [ -t 1 ] && command -v stty >/dev/null 2>&1; then
    detected_width=$(stty size 2>/dev/null | awk '{ print $2 }' || true)
  fi
  local terminal_width=${COLUMNS:-${detected_width:-120}}
  local count=${#options[@]}
  local longest=0 option cell_width column_count row_count row column index

  for option in "${options[@]}"; do
    [ "${#option}" -le "$longest" ] || longest=${#option}
  done
  cell_width=$((longest + 4))
  column_count=$((terminal_width / cell_width))
  [ "$column_count" -ge 1 ] || column_count=1
  [ "$column_count" -le 4 ] || column_count=4
  row_count=$(((count + column_count - 1) / column_count))

  for ((row = 0; row < row_count; row++)); do
    for ((column = 0; column < column_count; column++)); do
      index=$((row + column * row_count))
      [ "$index" -lt "$count" ] || continue
      printf '  %-*s' "$longest" "${options[$index]}"
    done
    printf '\n'
  done
}

choose_many() {
  local prompt=$1
  local default_selection=$2
  local layout=$3
  local cancel_key=$4
  local cancel_label=$5
  shift 5
  local -a options=("$@")
  local answer index
  CHOSEN_VALUES=()

  while true; do
    echo
    echo "$prompt"
    if [ "$layout" = columns ]; then
      print_numbered_columns "${options[@]}"
    else
      for index in "${!options[@]}"; do
        printf '  %d) %s\n' "$((index + 1))" "${options[$index]}"
      done
    fi
    if [ -n "$default_selection" ]; then
      read -r -p "Selections (comma/ranges supported) [$default_selection, $cancel_key=$cancel_label]: " answer || die "Input was closed."
    else
      read -r -p "Selections (comma/ranges supported, $cancel_key=$cancel_label): " answer || die "Input was closed."
    fi
    if [[ "${answer,,}" = "$cancel_key" || "${answer,,}" = "$cancel_label" ]]; then
      return 1
    fi
    if [ -z "$answer" ] && [ -z "$default_selection" ]; then
      echo "Select at least one number, or enter '$cancel_key' to return to $cancel_label." >&2
      continue
    fi
    answer=${answer:-$default_selection}
    if parse_number_selection "$answer" "${#options[@]}"; then
      for index in "${SELECTED_INDICES[@]}"; do
        CHOSEN_VALUES+=("${options[$index]}")
      done
      return
    fi
  done
}

configure_tui_catalog() {
  local catalog_image=$1
  local edit_mode=${2:-fresh}
  local package metadata default_channel joined_channels answer search cache_key
  local selected_list package_defaults_output cherry_pick_channels specs_text spec channel_back
  local index candidate catalog_number_width
  local -a all_packages matches last_matches match_labels selected_packages display_packages channels catalog_specs
  local -a remaining_packages remaining_specs pending_specs
  local -A selected_package_names=()
  local -A package_numbers=()
  all_packages=()
  matches=()
  last_matches=()
  match_labels=()
  selected_packages=()
  display_packages=()
  channels=()
  catalog_specs=()
  remaining_packages=()
  remaining_specs=()
  pending_specs=()

  if [ "$edit_mode" = append ]; then
    specs_text=${TUI_CATALOG_PACKAGE_SPECS[$catalog_image]}
    while IFS= read -r spec; do
      [ -n "$spec" ] || continue
      catalog_specs+=("$spec")
      package=${spec%%:*}
      display_packages+=("$package")
      selected_package_names["$package"]=1
    done <<< "$specs_text"
  fi

  echo
  echo "Configuring catalog: $catalog_image"
  if [ "$edit_mode" = append ]; then
    printf -v selected_list '%s, ' "${display_packages[@]}"
    selected_list=${selected_list%, }
    echo "Keeping existing packages: $selected_list"
  fi

  load_catalog_package_defaults "$catalog_image" || die "Could not query packages in '$catalog_image'."
  package_defaults_output=$CATALOG_PACKAGE_DEFAULTS_OUTPUT
  while IFS=$'\t' read -r package default_channel; do
    [ -n "$package" ] || continue
    [ -n "$default_channel" ] || die "Catalog data did not include a default channel for '$package'."
    all_packages+=("$package")
    CACHED_DEFAULT_CHANNELS["$catalog_image|$package"]=$default_channel
  done <<< "$package_defaults_output"
  [ "${#all_packages[@]}" -gt 0 ] || die "No packages were found in '$catalog_image'."
  mapfile -t all_packages < <(printf '%s\n' "${all_packages[@]}" | sort)
  catalog_number_width=${#all_packages[@]}
  catalog_number_width=${#catalog_number_width}
  for index in "${!all_packages[@]}"; do
    package_numbers["${all_packages[$index]}"]=$((index + 1))
  done

  while true; do
    echo
    echo "Search by name or enter package numbers. Use '*' to display every package."
    echo "Package choices toggle: selecting an included package removes it."
    echo "After a search, ENTER selects the first match; otherwise ENTER continues to channels."
    echo "Enter 'b' to return to the build menu."
    while true; do
    read -r -p "Package search/number: " search || die "Input was closed."
    is_back "$search" && return 1
    if [ -z "$search" ]; then
      if [ "${#last_matches[@]}" -gt 0 ]; then
        CHOSEN_VALUES=("${last_matches[0]}")
        last_matches=()
      else
        if [ "${#selected_packages[@]}" -gt 0 ]; then
          break
        elif [ "${#display_packages[@]}" -gt 0 ] && [ "$edit_mode" = append ]; then
          printf -v specs_text '%s\n' "${catalog_specs[@]}"
          TUI_CATALOG_PACKAGE_SPECS["$catalog_image"]=${specs_text%$'\n'}
          TUI_WHOLE_CATALOG["$catalog_image"]=false
          echo "Existing package selections were updated."
          return
        fi
        echo "Select at least one package, or enter 'b' to return to the build menu." >&2
        continue
      fi
    elif [[ "${search//[[:space:]]/}" =~ ^[0-9]+([,-][0-9]+)*$ ]]; then
      if ! parse_number_selection "$search" "${#all_packages[@]}"; then
        continue
      fi
      last_matches=()
      CHOSEN_VALUES=()
      for index in "${SELECTED_INDICES[@]}"; do
        CHOSEN_VALUES+=("${all_packages[$index]}")
      done
    else
      matches=()
      match_labels=()
      for package in "${all_packages[@]}"; do
        if [ "$search" = '*' ] || [[ "${package,,}" == *"${search,,}"* ]]; then
          matches+=("$package")
          printf -v selected_list '%*d) %s' "$catalog_number_width" "${package_numbers[$package]}" "$package"
          match_labels+=("$selected_list")
        fi
      done
      if [ "${#matches[@]}" -eq 0 ]; then
        last_matches=()
        echo "No package names matched '$search'." >&2
        continue
      fi
      last_matches=("${matches[@]}")
      echo
      echo "Matching packages (ENTER selects the first match; numbers select any match):"
      print_text_columns "${match_labels[@]}"
      continue
    fi

    for package in "${CHOSEN_VALUES[@]}"; do
      if [[ -v selected_package_names["$package"] ]]; then
        unset "selected_package_names[$package]"

        remaining_packages=()
        for candidate in "${display_packages[@]}"; do
          [ "$candidate" = "$package" ] || remaining_packages+=("$candidate")
        done
        display_packages=("${remaining_packages[@]}")

        remaining_packages=()
        for candidate in "${selected_packages[@]}"; do
          [ "$candidate" = "$package" ] || remaining_packages+=("$candidate")
        done
        selected_packages=("${remaining_packages[@]}")

        remaining_specs=()
        for spec in "${catalog_specs[@]}"; do
          [ "${spec%%:*}" = "$package" ] || remaining_specs+=("$spec")
        done
        catalog_specs=("${remaining_specs[@]}")
        echo "Removed package: $package"
      else
        selected_packages+=("$package")
        display_packages+=("$package")
        selected_package_names["$package"]=1
        echo "Added package: $package"
      fi
    done
    if [ "${#display_packages[@]}" -gt 0 ]; then
      printf -v selected_list '%s, ' "${display_packages[@]}"
      selected_list=${selected_list%, }
      echo "Selected packages: $selected_list"
    else
      echo "Selected packages: none"
    fi
    done

    echo
    channel_back=false
    while true; do
      read -r -p "Use each package's default channel? [Y/n/b]: " answer || die "Input was closed."
      case "${answer,,}" in
        ""|y|yes) cherry_pick_channels=false; break ;;
        n|no) cherry_pick_channels=true; break ;;
        b|back) channel_back=true; break ;;
        *) echo "Enter y, n, or b." >&2 ;;
      esac
    done
    if [ "$channel_back" = true ]; then
      echo "Returning to package selection; current choices were preserved."
      continue
    fi

    pending_specs=()
    for package in "${selected_packages[@]}"; do
      cache_key="$catalog_image|$package"
      default_channel=${CACHED_DEFAULT_CHANNELS[$cache_key]}
      if [ "$cherry_pick_channels" = true ]; then
        if [[ -v CACHED_PACKAGE_METADATA["$cache_key"] ]]; then
          metadata=${CACHED_PACKAGE_METADATA[$cache_key]}
          echo "Using cached channels for $package." >&2
        else
          metadata=$(package_metadata "$catalog_image" "$package") || die "Could not query package '$package'."
          CACHED_PACKAGE_METADATA["$cache_key"]=$metadata
        fi
        channels=("$default_channel")
        while IFS= read -r answer; do
          [ "$answer" = "$default_channel" ] || channels+=("$answer")
        done < <(available_channels_from_metadata <<< "$metadata")
        if ! choose_many "Select channels for $package (default channel listed first):" "1" rows b back "${channels[@]}"; then
          channel_back=true
          break
        fi
        joined_channels=$(IFS=,; echo "${CHOSEN_VALUES[*]}")
      else
        joined_channels=$default_channel
      fi
      pending_specs+=("$package:$joined_channels")
    done
    if [ "$channel_back" = true ]; then
      echo "Returning to package selection; current choices were preserved."
      continue
    fi
    catalog_specs+=("${pending_specs[@]}")
    break
  done

  printf -v specs_text '%s\n' "${catalog_specs[@]}"
  TUI_CATALOG_PACKAGE_SPECS["$catalog_image"]=${specs_text%$'\n'}
  TUI_WHOLE_CATALOG["$catalog_image"]=false
}

validate_release_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][a-zA-Z0-9]+)*$ ]]
}

configure_tui_platform() {
  local channel answer min_version="" max_version="" lowest_version
  local full_channel=false graph=true architecture architecture_filter listed_index
  local listed_minimum listed_maximum
  local -a architectures=(amd64 arm64 ppc64le s390x multi)
  local -a listed_channels=() listed_minimums=() listed_maximums=()

  echo
  echo "Configuring OpenShift platform releases"
  if ! choose_many "Select release architectures:" "1" rows b back "${architectures[@]}"; then
    return 1
  fi
  if [ "${#CHOSEN_VALUES[@]}" -gt 1 ]; then
    for architecture in "${CHOSEN_VALUES[@]}"; do
      if [ "$architecture" = multi ]; then
        echo "Choose 'multi' by itself, or select individual architectures." >&2
        return 1
      fi
    done
  fi
  architecture_filter=$(IFS=,; echo "${CHOSEN_VALUES[*]}")

  while true; do
    read -r -p "Release channel [stable-$VERSION, l=list, b=back]: " channel || die "Input was closed."
    is_back "$channel" && return 1
    if [[ "${channel,,}" = l || "${channel,,}" = list ]]; then
      if ! load_release_channel_ranges "$architecture_filter"; then
        echo "Could not load release channels for OpenShift $VERSION." >&2
        continue
      fi
      listed_channels=()
      listed_minimums=()
      listed_maximums=()
      while IFS='|' read -r channel listed_minimum listed_maximum; do
        [ -n "$channel" ] || continue
        listed_channels+=("$channel")
        listed_minimums+=("$listed_minimum")
        listed_maximums+=("$listed_maximum")
      done <<< "$RELEASE_CHANNEL_RANGES"
      print_release_channel_ranges "$RELEASE_CHANNEL_RANGES"
      echo "Enter a channel number or name at the same prompt."
      continue
    fi
    if [[ "$channel" =~ ^[0-9]+$ ]]; then
      if [ "${#listed_channels[@]}" -eq 0 ]; then
        echo "Enter 'l' to list channels before selecting one by number." >&2
        continue
      fi
      listed_index=$((10#$channel - 1))
      if [ "$listed_index" -lt 0 ] || [ "$listed_index" -ge "${#listed_channels[@]}" ]; then
        echo "Channel selection is outside 1-${#listed_channels[@]}." >&2
        continue
      fi
      channel=${listed_channels[$listed_index]}
      echo "Selected $channel (${listed_minimums[$listed_index]} through ${listed_maximums[$listed_index]})."
    fi
    channel=${channel:-stable-$VERSION}
    if [[ "$channel" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
      break
    fi
    echo "Enter a channel such as stable-$VERSION." >&2
  done
  while true; do
    read -r -p "Mirror every release in this channel? [y/N/b]: " answer || die "Input was closed."
    case "${answer,,}" in
      y|yes) full_channel=true; break ;;
      ""|n|no) full_channel=false; break ;;
      b|back) return 1 ;;
      *) echo "Enter y, n, or b." >&2 ;;
    esac
  done

  if [ "$full_channel" != true ]; then
    while true; do
      read -r -p "Minimum release [none, b=back]: " min_version || die "Input was closed."
      is_back "$min_version" && return 1
      [ -z "$min_version" ] || validate_release_version "$min_version" || {
        echo "Enter a release such as $VERSION.1, or leave it empty." >&2
        continue
      }
      break
    done
    while true; do
      read -r -p "Maximum release [none, b=back]: " max_version || die "Input was closed."
      is_back "$max_version" && return 1
      [ -z "$max_version" ] || validate_release_version "$max_version" || {
        echo "Enter a release such as $VERSION.1, or leave it empty." >&2
        continue
      }
      if [ -n "$min_version" ] && [ -n "$max_version" ]; then
        lowest_version=$(printf '%s\n' "$min_version" "$max_version" | sort -V | head -n1)
        if [ "$lowest_version" != "$min_version" ]; then
          echo "Maximum release must not be lower than the minimum release." >&2
          continue
        fi
      fi
      break
    done
  fi

  while true; do
    read -r -p "Include the OpenShift Update Service graph? [Y/n/b]: " answer || die "Input was closed."
    case "${answer,,}" in
      ""|y|yes) graph=true; break ;;
      n|no) graph=false; break ;;
      b|back) return 1 ;;
      *) echo "Enter y, n, or b." >&2 ;;
    esac
  done

  TUI_PLATFORM_ARCHITECTURES=("${CHOSEN_VALUES[@]}")
  TUI_PLATFORM_CHANNEL=$channel
  TUI_PLATFORM_MIN_VERSION=$min_version
  TUI_PLATFORM_MAX_VERSION=$max_version
  TUI_PLATFORM_FULL=$full_channel
  TUI_PLATFORM_GRAPH=$graph
  TUI_PLATFORM_CONFIGURED=true
}

review_tui_selections() {
  local catalog specs_text spec package channels architecture

  echo
  echo "Current selections"
  echo "=================="
  if [ "$TUI_PLATFORM_CONFIGURED" != true ] && [ "${#TUI_CATALOG_IMAGES[@]}" -eq 0 ]; then
    echo "Nothing configured yet."
    return
  fi

  if [ "$TUI_PLATFORM_CONFIGURED" = true ]; then
    echo
    echo "- OpenShift platform"
    printf -v channels '%s, ' "${TUI_PLATFORM_ARCHITECTURES[@]}"
    channels=${channels%, }
    echo "    Architectures: $channels"
    echo "    Channel: $TUI_PLATFORM_CHANNEL"
    [ -z "$TUI_PLATFORM_MIN_VERSION" ] || echo "    Minimum release: $TUI_PLATFORM_MIN_VERSION"
    [ -z "$TUI_PLATFORM_MAX_VERSION" ] || echo "    Maximum release: $TUI_PLATFORM_MAX_VERSION"
    [ "$TUI_PLATFORM_FULL" != true ] || echo "    Entire channel: yes"
    echo "    Update graph: $TUI_PLATFORM_GRAPH"
  fi

  for catalog in "${TUI_CATALOG_IMAGES[@]}"; do
    echo
    echo "- $catalog"
    if [ "${TUI_WHOLE_CATALOG[$catalog]:-false}" = true ]; then
      echo "    Entire catalog (default channel heads)"
    else
      specs_text=${TUI_CATALOG_PACKAGE_SPECS[$catalog]}
      while IFS= read -r spec; do
        [ -n "$spec" ] || continue
        package=${spec%%:*}
        channels=${spec#*:}
        echo "    $package: $channels"
      done <<< "$specs_text"
    fi
  done
}

choose_catalog_edit_mode() {
  local catalog_image=$1
  local already_selected=$2
  local answer

  while true; do
    if [ "$already_selected" != true ]; then
      read -r -p "Configure this catalog: select packages or include entire catalog? [S/e/b]: " answer || die "Input was closed."
      case "${answer,,}" in
        ""|s|select) CATALOG_EDIT_MODE=fresh; return ;;
        e|entire|all) CATALOG_EDIT_MODE=entire; return ;;
        b|back) CATALOG_EDIT_MODE=back; return ;;
        *) echo "Enter s, e, or b." >&2 ;;
      esac
    elif [ "${TUI_WHOLE_CATALOG[$catalog_image]}" = true ]; then
      echo "This catalog already includes every package."
      read -r -p "Start fresh with a package selection? [y/N/b]: " answer || die "Input was closed."
      case "${answer,,}" in
        y|yes) CATALOG_EDIT_MODE=fresh; return ;;
        ""|n|no|b|back) CATALOG_EDIT_MODE=back; return ;;
        *) echo "Enter y, n, or b." >&2 ;;
      esac
    else
      read -r -p "Edit this catalog: append, start fresh, or include entire catalog? [A/r/e/b]: " answer || die "Input was closed."
      case "${answer,,}" in
        ""|a|append) CATALOG_EDIT_MODE=append; return ;;
        r|reset|fresh) CATALOG_EDIT_MODE=fresh; return ;;
        e|entire|all) CATALOG_EDIT_MODE=entire; return ;;
        b|back) CATALOG_EDIT_MODE=back; return ;;
        *) echo "Enter a, r, e, or b." >&2 ;;
      esac
    fi
  done
}

save_entire_tui_catalog() {
  local catalog_image=$1
  TUI_WHOLE_CATALOG["$catalog_image"]=true
  TUI_CATALOG_PACKAGE_SPECS["$catalog_image"]=""
}

tui_configure() {
  local output_answer selected_catalog already_selected menu_choice edit_mode
  local -a catalogs

  mapfile -t catalogs < <(available_catalogs)
  [ "${#catalogs[@]}" -gt 0 ] || die "No catalogs were found for OpenShift $VERSION."

  if [ "$CATALOG" != all ] && [ "$TUI_INITIAL_CATALOG_HANDLED" != true ]; then
    TUI_INITIAL_CATALOG_HANDLED=true
    selected_catalog=$(catalog_image "$CATALOG")
    choose_catalog_edit_mode "$selected_catalog" false
    if [ "$CATALOG_EDIT_MODE" = entire ]; then
      save_entire_tui_catalog "$selected_catalog"
      TUI_CATALOG_IMAGES+=("$selected_catalog")
    elif [ "$CATALOG_EDIT_MODE" = fresh ] && configure_tui_catalog "$selected_catalog" fresh; then
      TUI_CATALOG_IMAGES+=("$selected_catalog")
    fi
  fi

  while true; do
    echo
    echo "ImageSet build menu (platform: $TUI_PLATFORM_CONFIGURED, catalogs: ${#TUI_CATALOG_IMAGES[@]})"
    if ! choose_one "Choose the next action:" \
      "Configure platform releases" \
      "Add or edit an operator catalog" \
      "Review current selections" \
      "Finish selections and build YAML" \
      "Cancel"; then
      continue
    fi
    menu_choice=$CHOSEN_VALUE

    case "$menu_choice" in
      "Configure platform releases")
        if configure_tui_platform; then
          echo "Platform releases saved. Returning to the build menu."
        else
          echo "Platform edit abandoned. Returning to the build menu."
        fi
        ;;
      "Add or edit an operator catalog")
        if ! choose_one "Select a catalog:" "${catalogs[@]}"; then
          continue
        fi
        selected_catalog=$CHOSEN_VALUE
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
          echo "Entire catalog saved. Returning to the build menu."
          continue
        fi

        if ! configure_tui_catalog "$selected_catalog" "$edit_mode"; then
          echo "Catalog edit abandoned. Returning to the build menu."
          continue
        fi
        if [ "$already_selected" != true ]; then
          TUI_CATALOG_IMAGES+=("$selected_catalog")
        fi
        echo "Catalog saved. Returning to the build menu."
        ;;
      "Review current selections")
        review_tui_selections
        ;;
      "Finish selections and build YAML")
        if [ "$TUI_PLATFORM_CONFIGURED" != true ] && [ "${#TUI_CATALOG_IMAGES[@]}" -eq 0 ]; then
          echo "Configure platform releases or at least one operator catalog before building the YAML." >&2
          continue
        fi
        review_tui_selections
        if [ -z "$OUTPUT_FILE" ]; then
          read -r -p "Output file [imageset-config-v$VERSION.yaml, b=back]: " output_answer || die "Input was closed."
          is_back "$output_answer" && continue
          OUTPUT_FILE=${output_answer:-imageset-config-v$VERSION.yaml}
        fi
        CATALOG_IMAGE=${TUI_CATALOG_IMAGES[0]:-}
        return
        ;;
      "Cancel")
        echo "Cancelled; no file was written."
        exit 0
        ;;
    esac
  done

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

  if [[ -v CACHED_DEFAULT_CHANNELS["$cache_key"] ]]; then
    default_channel=${CACHED_DEFAULT_CHANNELS[$cache_key]}
    metadata=${CACHED_PACKAGE_METADATA[$cache_key]:-}
  else
    echo "Resolving package: $package" >&2
    metadata=$(package_metadata "$image" "$package") || die "Could not query package '$package' in '$image'."
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
    printf '      - name: %s\n' "$channel"
  done
}

generate_yaml() {
  local image=$1
  local temporary_output=$2
  local spec catalog specs_text architecture

  {
    printf '%s\n' '---'
    printf '%s\n' 'kind: ImageSetConfiguration'
    printf '%s\n\n' 'apiVersion: mirror.openshift.io/v2alpha1'
    printf '%s\n' 'mirror:'
    if [ "$MODE" = tui ]; then
      if [ "$TUI_PLATFORM_CONFIGURED" = true ]; then
        printf '%s\n' '  platform:'
        printf '%s\n' '    architectures:'
        for architecture in "${TUI_PLATFORM_ARCHITECTURES[@]}"; do
          printf '    - %s\n' "$architecture"
        done
        printf '%s\n' '    channels:'
        printf '%s\n' '    - type: ocp'
        printf '      name: %s\n' "$TUI_PLATFORM_CHANNEL"
        [ -z "$TUI_PLATFORM_MIN_VERSION" ] || printf '      minVersion: %s\n' "$TUI_PLATFORM_MIN_VERSION"
        [ -z "$TUI_PLATFORM_MAX_VERSION" ] || printf '      maxVersion: %s\n' "$TUI_PLATFORM_MAX_VERSION"
        [ "$TUI_PLATFORM_FULL" != true ] || printf '%s\n' '      full: true'
        printf '    graph: %s\n' "$TUI_PLATFORM_GRAPH"
      fi
      if [ "${#TUI_CATALOG_IMAGES[@]}" -gt 0 ]; then
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
      fi
      printf '\n%s\n' '  additionalImages: []'
      printf '%s\n' '  helm: {}'
    else
      printf '%s\n' '  operators:'
      printf '  - catalog: %s\n' "$image"
      if [ "${#PACKAGE_SPECS[@]}" -gt 0 ]; then
        printf '%s\n' '    packages:'
        for spec in "${PACKAGE_SPECS[@]}"; do
          write_package_yaml "$image" "$spec"
        done
      fi
    fi
  } > "$temporary_output"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -v|--version)
      require_value "$@"
      VERSION=$2
      VERSION_EXPLICIT=true
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

if [ "$MODE" = tui ] && [ "$VERSION_EXPLICIT" != true ]; then
  read -r -p "OpenShift version [$VERSION]: " TUI_VERSION
  VERSION=${TUI_VERSION:-$VERSION}
fi

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+$ ]] || die "Version must use major.minor format, such as 4.20."
[ "$MODE" != list ] || [ "${#PACKAGE_SPECS[@]}" -eq 0 ] || die "--package requires --yaml or --tui."
[ "$MODE" != list ] || [ -z "$OUTPUT_FILE" ] || die "--output requires --yaml or --tui."
[ "$MODE" != tui ] || [ "${#PACKAGE_SPECS[@]}" -eq 0 ] || die "--package cannot be combined with --tui; select packages interactively."
if [ "$MODE" = yaml ] && [ "$CATALOG" = all ]; then
  die "YAML mode requires one catalog selected with --catalog."
fi

check_dependencies

ORIGINAL_DIR=$(pwd -P)
WORK_DIR=$(mktemp -d "$ORIGINAL_DIR/.catalog-fetcher.XXXXXX")
cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT
export TMPDIR="$WORK_DIR/tmp"
mkdir -p "$TMPDIR"
cd "$WORK_DIR"

echo "OpenShift version: $VERSION"
echo "Catalog: $CATALOG"

if [ "$MODE" = tui ]; then
  declare -A SEEN_PACKAGES=()
  while true; do
    tui_configure
    if [[ "$OUTPUT_FILE" != /* ]]; then
      OUTPUT_FILE="$ORIGINAL_DIR/$OUTPUT_FILE"
    fi
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    [ ! -d "$OUTPUT_FILE" ] || die "Output path '$OUTPUT_FILE' is a directory."

    SEEN_PACKAGES=()
    TEMPORARY_YAML="$WORK_DIR/imageset-config.yaml"
    generate_yaml "$CATALOG_IMAGE" "$TEMPORARY_YAML"
    echo
    echo "Configuration preview:"
    echo "----------------------"
    cat "$TEMPORARY_YAML"
    echo "----------------------"
    while true; do
      read -r -p "Write this configuration? [Y/n/b]: " CONFIRM || die "Input was closed."
      case "${CONFIRM,,}" in
        ""|y|yes) CONFIRM=yes; break ;;
        n|no) echo "Cancelled; no file was written."; exit 0 ;;
        b|back) CONFIRM=back; break ;;
        *) echo "Enter y, n, or b." >&2 ;;
      esac
    done
    [ "$CONFIRM" = back ] && continue
    break
  done
  mv -f "$TEMPORARY_YAML" "$OUTPUT_FILE"
  echo "ImageSetConfiguration written to: $OUTPUT_FILE"
elif [ "$MODE" = yaml ]; then
  CATALOG_IMAGE=$(catalog_image "$CATALOG")
  if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="imageset-config-v$VERSION.yaml"
  elif [[ "$OUTPUT_FILE" != /* ]]; then
    OUTPUT_FILE="$ORIGINAL_DIR/$OUTPUT_FILE"
  fi
  [[ "$OUTPUT_FILE" == /* ]] || OUTPUT_FILE="$ORIGINAL_DIR/$OUTPUT_FILE"
  mkdir -p "$(dirname "$OUTPUT_FILE")"
  [ ! -d "$OUTPUT_FILE" ] || die "Output path '$OUTPUT_FILE' is a directory."

  declare -A SEEN_PACKAGES=()
  TEMPORARY_YAML="$WORK_DIR/imageset-config.yaml"
  generate_yaml "$CATALOG_IMAGE" "$TEMPORARY_YAML"
  mv -f "$TEMPORARY_YAML" "$OUTPUT_FILE"
  echo "ImageSetConfiguration written to: $OUTPUT_FILE"
else
  if [ "$CATALOG" = all ]; then
    mapfile -t CATALOGS < <(available_catalogs)
    for CATALOG_IMAGE in "${CATALOGS[@]}"; do
      fetch_catalog "$CATALOG_IMAGE"
    done
  else
    fetch_catalog "$(catalog_image "$CATALOG")"
  fi
fi
