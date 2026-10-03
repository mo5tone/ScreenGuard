#!/bin/sh
# =============================================================================================
# Scripts/ci/check-destination.sh — resolve the requested iOS Simulator destination, or FAIL LOUDLY.
#
# WHY THIS EXISTS
#   The runner image is not this machine: the installed Simulator runtimes differ, and the default
#   runtime drifts as images are updated. A missing runtime must not be papered over with a
#   "fallback" device — building the package for a runtime nobody asked for silently changes what
#   "CI is green" means, and it does so exactly when the intended runtime is broken or absent.
#   So: resolve the destination BEFORE the build, and if it does not exist, print the reason and
#   the full list of available destinations, and exit 1. There is no fallback path in this script.
#
# USAGE
#   Scripts/ci/check-destination.sh "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2"
#   DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2" Scripts/ci/check-destination.sh
#
# Accepted keys: platform (must be "iOS Simulator"), name, OS, id. Unknown keys are an error.
#   * name + OS  -> the documented default; both must match exactly
#   * name only  -> accepted ONLY when exactly one runtime has that device, otherwise the request
#                   is ambiguous and this script fails rather than let xcodebuild pick a runtime
#   * id         -> the UDID must be an available device
#
# Exit codes: 0 = the destination exists, 1 = it does not (or is ambiguous), 2 = usage error.
# =============================================================================================
set -eu

die() {
    reason=$1
    shift
    printf '\nFAIL: %s\n' "$reason" >&2
    for detail in "$@"; do
        printf '%s\n' "$detail" >&2
    done
    exit 1
}

usage_error() {
    printf 'usage: %s "platform=iOS Simulator,name=<device>,OS=<runtime>"\n' "$0" >&2
    printf '       DESTINATION="platform=iOS Simulator,name=<device>,OS=<runtime>" %s\n' "$0" >&2
    exit 2
}

destination="${1:-${DESTINATION:-}}"
if [ -z "$destination" ]; then
    usage_error
fi
if [ "$#" -gt 1 ]; then
    usage_error
fi

# --- parse key=value pairs ---------------------------------------------------------------------
platform=
name=
os=
id=
old_ifs=$IFS
IFS=,
# Word splitting on "," is exactly what is wanted here; nothing else is unquoted.
# shellcheck disable=SC2086
set -- $destination
IFS=$old_ifs
for field in "$@"; do
    field=$(printf '%s' "$field" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case $field in
        *=*) : ;;
        *) die "destination field '$field' is not key=value" \
               "  requested: $destination" \
               "  expected : platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2" ;;
    esac
    key=${field%%=*}
    value=${field#*=}
    case $key in
        platform) platform=$value ;;
        name)     name=$value ;;
        OS|os)    os=$value ;;
        id)       id=$value ;;
        *) die "unsupported destination key '$key'" \
               "  requested: $destination" \
               "  this check validates iOS Simulator destinations only: platform, name, OS, id" \
               "  e.g. platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2" ;;
    esac
done

if [ -z "$platform" ]; then
    die "the destination does not say which platform it is for" \
        "  requested: $destination" \
        "  expected : platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2"
fi
if [ "$platform" != "iOS Simulator" ]; then
    die "unsupported platform '$platform' — this workflow validates iOS Simulator destinations only" \
        "  requested: $destination"
fi
if [ -z "$name" ] && [ -z "$id" ]; then
    die "the destination names no device" \
        "  requested: $destination" \
        "  give name=<device> (with OS=<runtime>) or id=<UDID>"
fi

# --- every available Simulator device, as: <runtime><TAB><device><TAB><udid> -------------------
if ! command -v xcrun >/dev/null 2>&1; then
    die "xcrun is not on PATH, so no Simulator destination can be checked" \
        "  install Xcode and make sure 'xcode-select -p' points at it"
fi
if ! available_raw=$(xcrun simctl list devices available 2>&1); then
    die "'xcrun simctl list devices available' failed" "$available_raw"
fi

devices=$(
    printf '%s\n' "$available_raw" | awk '
        /^-- / {
            runtime = $0
            sub(/^--[[:space:]]*/, "", runtime)
            sub(/[[:space:]]*--$/, "", runtime)
            next
        }
        /^[[:space:]]+[^[:space:]]/ {
            if (runtime == "" || runtime ~ /^Unavailable:/) next
            line = $0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)                     # simctl pads every device line
            sub(/[[:space:]]*\([^()]*\)$/, "", line)          # drop the "(Shutdown)" / "(Booted)" state
            if (match(line, /\([^()]*\)$/)) {
                udid = substr(line, RSTART + 1, RLENGTH - 2)
                device = substr(line, 1, RSTART - 1)
                sub(/[[:space:]]+$/, "", device)
                printf "%s\t%s\t%s\n", runtime, device, udid
            }
        }
    '
)

available_list=$(printf '%s\n' "$devices" | awk -F'\t' '{ printf "    %-12s %-30s %s\n", $1, $2, $3 }')

if [ -z "$devices" ]; then
    # Either this machine really has no Simulator device, or simctl printed something this parser
    # does not understand. Both are failures, and the raw output below says which one it is.
    die "no iOS Simulator destination could be read from 'xcrun simctl list devices available'" \
        "  requested: $destination" \
        "  raw output of 'xcrun simctl list devices available':" \
        "$available_raw" \
        "  if that output lists devices, this script's parser is wrong (and not the runner)" \
        "  if it lists none, install a Simulator runtime:  xcodebuild -downloadPlatform iOS"
fi

# --- match ------------------------------------------------------------------------------------
matches=$(
    printf '%s\n' "$devices" | awk -F'\t' -v want_name="$name" -v want_os="$os" -v want_id="$id" '
        {
            want = $1
            sub(/^iOS /, "", want)
            if (want_os != "") {
                wanted_os = want_os
                sub(/^iOS /, "", wanted_os)
                if (want != wanted_os) next
            }
            if (want_id != "" && $3 != want_id) next
            if (want_name != "" && $2 != want_name) next
            print
        }
    '
)

if [ -z "$matches" ]; then
    reason="no available device matches this destination"
    if [ -n "$name" ] && [ -n "$os" ]; then
        reason="no available device named '$name' on runtime '$os'"
    fi
    runtimes_with_name=$(printf '%s\n' "$devices" | awk -F'\t' -v want_name="$name" '$2 == want_name { print $1 }' | sort -u | tr '\n' ' ')
    devices_on_runtime=$(printf '%s\n' "$devices" | awk -F'\t' -v want_os="$os" '{ r = $1; sub(/^iOS /, "", r); w = want_os; sub(/^iOS /, "", w); if (want_os == "" || r == w) print $2 }' | sort -u | tr '\n' ' ')
    die "$reason" \
        "  requested         : $destination" \
        "  device name       : ${name:-<not given>}" \
        "  requested runtime : ${os:-<not given>}" \
        "  runtimes with that device : ${runtimes_with_name:-none}" \
        "  devices in that runtime   : ${devices_on_runtime:-none}" \
        "" \
        "  every available iOS Simulator destination:" \
        "$available_list" \
        "" \
        "  This step FAILS on purpose: a missing runtime must not silently fall back to another one." \
        "  Fix by naming a destination that exists (DESTINATION=... / the DESTINATION Actions variable), or install the runtime:" \
        "    xcodebuild -downloadPlatform iOS"
fi

match_count=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
if [ "$match_count" -gt 1 ]; then
    die "the destination matches $match_count runtimes, so it is ambiguous" \
        "  requested: $destination" \
        "  matched  :" \
        "$(printf '%s\n' "$matches" | awk -F'\t' '{ printf "    %-12s %-30s %s\n", $1, $2, $3 }')" \
        "" \
        "  Add OS=<runtime> to pin the runtime — an unspecified runtime is how a green run silently" \
        "  drifts onto a different iOS version."
fi
resolved_runtime=$(printf '%s\n' "$matches" | cut -f1)
resolved_device=$(printf '%s\n' "$matches" | cut -f2)
resolved_udid=$(printf '%s\n' "$matches" | cut -f3)

printf 'check-destination: OK\n'
printf '  requested : %s\n' "$destination"
printf '  resolved  : %s / %s (%s)\n' "$resolved_runtime" "$resolved_device" "$resolved_udid"
if command -v xcodebuild >/dev/null 2>&1; then
    printf '  xcodebuild: %s\n' "$(xcodebuild -version | head -1)"
fi
