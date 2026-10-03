#!/usr/bin/env bash
# Device validation run: build the CaptureMatrix harness for a CONNECTED PHYSICAL DEVICE, run the
# full measurement suite on it, and pull the artifacts back into the repo.
#
#   Research/Scripts/capture_matrix_device.sh --device 00008101-000A0C123456001E
#   Research/Scripts/capture_matrix_device.sh --device "My iPhone" --team ABCDE12345
#   Research/Scripts/capture_matrix_device.sh --device <UDID> --modes "matrix feasibility renderSanity"
#
# Why this exists: several cells in docs/evidence/capability-matrix.md are marked
# "not measurable on Simulator - requires device". This is the one command that fills them.
#
# TWO RULES THIS SCRIPT ENFORCES, because breaking either corrupts the evidence:
#   1. A device is REQUIRED and must be named explicitly. There is no default, and there is NO
#      fallback to a Simulator. A Simulator result for these cells is unearned.
#   2. Host-side capture is never a no-leak verdict. Any host/device screenshot this script takes is
#      written with a CONTRAST- or DISPLAY- prefix and is only ever used to establish whether a
#      layer RENDERS, never whether content was protected.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HARNESS="$ROOT/Research/CaptureMatrix"
BUNDLE_ID="com.screenguard.capturematrix"
MODES="matrix feasibility renderSanity"
DEVICE=""
TEAM="${DEVELOPMENT_TEAM:-}"
DERIVED="${DEVICE_DERIVED_DATA:-$HARNESS/Derived/DD-device}"
# renderSanity holds this long on device so the operator can photograph the screen.
RENDER_SANITY_HOLD="${RENDER_SANITY_HOLD:-30}"

usage() {
    cat <<'EOF'
Device validation run: build the CaptureMatrix harness for a CONNECTED PHYSICAL DEVICE, run the
full measurement suite on it, and pull the artifacts back into the repo.

  Research/Scripts/capture_matrix_device.sh --device 00008101-000A0C123456001E
  Research/Scripts/capture_matrix_device.sh --device "My iPhone" --team ABCDE12345
  Research/Scripts/capture_matrix_device.sh --device <UDID> --modes "matrix feasibility renderSanity"

Why this exists: several cells in docs/evidence/capability-matrix.md are marked
"not measurable on Simulator - requires device". This is the one command that fills them.

TWO RULES THIS SCRIPT ENFORCES, because breaking either corrupts the evidence:
  1. A device is REQUIRED and must be named explicitly. There is no default, and there is NO
     fallback to a Simulator. A Simulator result for these cells is unearned.
  2. Host-side capture is never a no-leak verdict. Any screenshot this script takes is written
     with a DISPLAY- prefix and is only ever used to establish whether a layer RENDERS, never
     whether content was protected.

Arguments:
  --device <UDID|name>   REQUIRED. The physical device, by UDID or by its devicectl name.
  --team <TEAMID>        Apple Developer Team ID for signing (or set DEVELOPMENT_TEAM).
  --modes "<list>"       Modes to run. Default: "matrix feasibility renderSanity".
  --derived <path>       Derived data path (default Research/CaptureMatrix/Derived/DD-device).
  -h, --help             This help.

Exit codes:
  0  all requested modes ran and artifacts were collected
  2  usage error
  3  no physical device connected / named device not found or not physical
  4  build or signing failure
  5  install, launch, or artifact collection failure
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)  DEVICE="${2:-}"; shift 2 ;;
        --team)    TEAM="${2:-}"; shift 2 ;;
        --modes)   MODES="${2:-}"; shift 2 ;;
        --derived) DERIVED="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; echo >&2; usage >&2; exit 2 ;;
    esac
done

fail() { echo >&2; echo "ERROR: $*" >&2; }

# --- Precondition 1: a device was named explicitly ---------------------------------------------
#
# There is deliberately no default device. Selecting one implicitly is how a Simulator result ends
# up in the evidence for cells that only a physical device can answer.

if [[ -z "$DEVICE" ]]; then
    fail "--device is required, and there is no default on purpose."
    cat >&2 <<'EOF'

  These cells can ONLY be measured on a physical device. A Simulator would silently produce an
  unearned verdict for the public preventsCapture API and for the whole recording path, so this
  script will not choose a device for you.

  List connected devices and pick one:

      xcrun devicectl list devices

  Then pass it by UDID or name:

      Research/Scripts/capture_matrix_device.sh --device <UDID-or-name>
EOF
    exit 2
fi

# --- Precondition 2: the named device exists, is PHYSICAL, and is usable ------------------------

echo "resolving device: $DEVICE"
DEVICE_JSON="$(mktemp -t capturematrix-devices)"
trap 'rm -f "$DEVICE_JSON"' EXIT

if ! xcrun devicectl list devices --json-output "$DEVICE_JSON" --quiet >/dev/null 2>&1; then
    fail "could not enumerate devices with 'xcrun devicectl list devices'."
    echo "  Check that Xcode and the CoreDevice tooling are installed and that the device is" >&2
    echo "  connected and unlocked. Run it by hand to see the underlying error:" >&2
    echo "      xcrun devicectl list devices" >&2
    exit 3
fi

RESOLVED=$(python3 - "$DEVICE_JSON" "$DEVICE" <<'PY'
import json, sys

path, wanted = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception as exc:
    sys.exit(f"could not parse device list JSON: {exc}")

devices = data.get("result", {}).get("devices", [])
physical = [d for d in devices if d.get("hardwareProperties", {}).get("reality") == "physical"]

if not physical:
    simulated = [d.get("deviceProperties", {}).get("name") for d in devices
                 if d.get("hardwareProperties", {}).get("reality") == "simulated"]
    print("NO-PHYSICAL", file=sys.stderr)
    print(f"devicectl knows {len(devices)} device(s), all simulated: {simulated}", file=sys.stderr)
    sys.exit(0)

# Match by exact UDID/identifier first, then by exact name, then by unique substring.
def ident(d): return d.get("identifier", "")
def name(d): return d.get("deviceProperties", {}).get("name", "")

exact = [d for d in physical if ident(d) == wanted or name(d) == wanted]
if len(exact) == 1:
    print(f"{ident(exact[0])}\t{name(exact[0])}")
    sys.exit(0)

partial = [d for d in physical if wanted.lower() in name(d).lower() or wanted.lower() in ident(d).lower()]
if len(partial) == 1:
    print(f"{ident(partial[0])}\t{name(partial[0])}")
    sys.exit(0)

print("AMBIGUOUS" if partial else "NOT-FOUND", file=sys.stderr)
print(f"connected physical devices: {[name(d) for d in physical]}", file=sys.stderr)
if len(partial) > 1:
    print(f"'{wanted}' matched several: {[name(d) for d in partial]}", file=sys.stderr)
sys.exit(0)
PY
) || { fail "device resolution failed"; exit 3; }

if [[ -z "$RESOLVED" ]]; then
    fail "'$DEVICE' is not a connected physical device."
    cat >&2 <<'EOF'

  This script will NOT fall back to a Simulator: the cells it fills are exactly the ones a
  Simulator cannot answer honestly.

  To proceed:
    1. Connect the iPhone by cable (or pair it wirelessly) and UNLOCK it.
    2. Trust this computer when the device prompts.
    3. Enable Developer Mode: Settings > Privacy & Security > Developer Mode, then reboot.
    4. Confirm it appears as 'physical' in:  xcrun devicectl list devices
EOF
    exit 3
fi

DEVICE_UDID="${RESOLVED%%$'\t'*}"
DEVICE_NAME_RESOLVED="${RESOLVED##*$'\t'}"
echo "device      : $DEVICE_NAME_RESOLVED ($DEVICE_UDID)"
echo "reality     : physical  ✓"

# --- Precondition 3: the device is paired and its developer services are up ---------------------

PAIR_STATE=$(python3 - "$DEVICE_JSON" "$DEVICE_UDID" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for d in data.get("result", {}).get("devices", []):
    if d.get("identifier") == sys.argv[2]:
        c = d.get("connectionProperties", {})
        p = d.get("deviceProperties", {})
        print(c.get("pairingState", "unknown"), p.get("ddiServicesAvailable", False),
              c.get("tunnelState", "unknown"), p.get("bootState", "unknown"))
        break
PY
)
read -r PAIRING DDI TUNNEL BOOTSTATE <<< "$PAIR_STATE"
echo "pairing     : $PAIRING | ddiServices=$DDI | tunnel=$TUNNEL | boot=$BOOTSTATE"

if [[ "$PAIRING" != "paired" ]]; then
    fail "device pairing state is '$PAIRING', expected 'paired'."
    echo "  Unlock the device, reconnect it, and tap Trust. Then re-run." >&2
    exit 3
fi
if [[ "$DDI" != "True" ]]; then
    echo "WARNING: ddiServicesAvailable=$DDI. The developer disk image may not be mounted yet." >&2
    echo "         Xcode usually mounts it on first install. If the build/install step fails, open" >&2
    echo "         Xcode > Window > Devices and Simulators and wait for 'Preparing device'." >&2
fi

# --- Precondition 4: signing ---------------------------------------------------------------------
#
# Research/CaptureMatrix/project.yml sets CODE_SIGNING_ALLOWED: NO so the Simulator build needs no
# identity. A physical device needs a development signature with get-task-allow, so this script
# overrides that on the command line rather than editing the (out-of-scope) project manifest.

# NOTE: BSD sed does not support \+ in basic regexes, so `sed -n 's/.*\([0-9]\+\) .../\1/p'`
# silently yields an empty string on macOS and the gate below then fires for the wrong reason.
# grep -oE is portable across BSD and GNU, so use that.
IDENTITY_REPORT="$(security find-identity -v -p codesigning 2>/dev/null || true)"
VALID_COUNT="$(printf '%s\n' "$IDENTITY_REPORT" | grep -oE '[0-9]+ valid identities found' | grep -oE '^[0-9]+' | head -1)"
VALID_COUNT="${VALID_COUNT:-0}"
echo "signing ids : $VALID_COUNT valid codesigning identity(ies)"

if [[ "$VALID_COUNT" == "0" ]]; then
    fail "no valid codesigning identities found on this machine."
    cat >&2 <<'EOF'

  A physical-device build must be development-signed (the app needs get-task-allow to launch from
  devicectl). To fix:
    1. Open Xcode > Settings > Accounts and add your Apple ID.
    2. Select the team and click 'Manage Certificates' > '+' > 'Apple Development'.
    3. Re-run with the team id:   --team <TEAMID>
  A free Apple ID works, but the app then expires after 7 days.
EOF
    exit 4
fi

if [[ -z "$TEAM" ]]; then
    fail "--team <TEAMID> is required for a device build (or set DEVELOPMENT_TEAM)."
    echo "  Find your team id with:  security find-identity -v -p codesigning" >&2
    echo "  The team id is the 10-character code in parentheses, e.g. ABCDE12345." >&2
    exit 4
fi

# --- Run -----------------------------------------------------------------------------------------

RUN_ID="$(date +%Y%m%d-%H%M%S)-device"
OUT="$ROOT/Research/Artifacts/$RUN_ID"
mkdir -p "$OUT"
echo "run-id      : $RUN_ID"
echo "modes       : $MODES"
echo "artifacts   : $OUT"
echo

# Provenance marker. A device run and a Simulator run write the same artifact layout on purpose (so
# analyze_capture.py consumes both unchanged), which means the ONLY thing distinguishing them is a
# marker like this. Write it before any measurement so it cannot be forgotten if a later step fails.
cat > "$OUT/RUN-PROVENANCE.txt" <<PROVEOF
capture-matrix-run: DEVICE
run-id: $RUN_ID
device-udid: $DEVICE_UDID
device-name: $DEVICE_NAME_RESOLVED
reality: physical
pairing: $PAIRING
boot-state: $BOOTSTATE
team: $TEAM
modes: $MODES
started: $(date -u +%Y-%m-%dT%H:%M:%SZ)
PROVEOF
python3 - "$DEVICE_JSON" "$DEVICE_UDID" >> "$OUT/RUN-PROVENANCE.txt" <<'PROVEOF2' || true
import json, sys
data = json.load(open(sys.argv[1]))
for d in data.get("result", {}).get("devices", []):
    if d.get("identifier") == sys.argv[2]:
        hw, props = d.get("hardwareProperties", {}), d.get("deviceProperties", {})
        print("product-type: " + str(hw.get("productType")))
        print("marketing-name: " + str(hw.get("marketingName")))
        print("os-version: " + str(props.get("osVersionNumber")))
        print("os-build: " + str(props.get("osBuildUpdate")))
PROVEOF2
echo "provenance  : $OUT/RUN-PROVENANCE.txt (reality=physical)"


# Build once for the device; every mode reuses the same binary.
echo "building for device…"
set +e
xcodebuild build -project "$HARNESS/CaptureMatrix.xcodeproj" -scheme CaptureMatrix \
    -destination "platform=iOS,id=$DEVICE_UDID" -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="Apple Development" \
    > "$OUT/build.log" 2>&1
BUILD_STATUS=$?
set -e
grep -E "BUILD (SUCCEEDED|FAILED)|error:" "$OUT/build.log" | tail -5 || true

if [[ $BUILD_STATUS -ne 0 ]]; then
    fail "device build failed (exit $BUILD_STATUS). Full log: $OUT/build.log"
    if grep -q "Unable to find a device matching" "$OUT/build.log"; then
        cat >&2 <<'EOF'

  xcodebuild could not match the destination to a real device. This is almost always one of:
    - The device is not actually reachable for DEVELOPMENT (connected to devicectl is not the
      same as being a valid xcodebuild destination). Confirm with:
          xcodebuild -showdestinations -project Research/CaptureMatrix/CaptureMatrix.xcodeproj -scheme CaptureMatrix
      and check that a 'platform:iOS, id:<UDID>' entry is listed.
    - Developer Mode is off, or the device has not been trusted/unlocked.
    - The device has never been prepared by Xcode. Open Xcode > Window > Devices and Simulators,
      wait for 'Preparing device' to finish, then re-run.
EOF
    else
        cat >&2 <<'EOF'

  Common causes:
    - Wrong or missing --team. The team id is the 10-character code in
      'security find-identity -v -p codesigning'.
    - The device is not registered for the team. Open Xcode > Window > Devices and Simulators,
      or let Xcode manage it once, then re-run.
    - Trust/Developer Mode not accepted on the device.
EOF
    fi
    exit 4
fi

APP="$DERIVED/Build/Products/Debug-iphoneos/CaptureMatrix.app"
if [[ ! -d "$APP" ]]; then
    fail "build reported success but $APP does not exist."
    exit 4
fi

# Provenance, mirroring the Simulator runs' toolchain.txt.
{
    xcodebuild -version
    swift --version 2>&1 || true
    echo "--- device ---"
    echo "$DEVICE_NAME_RESOLVED ($DEVICE_UDID) reality=physical"
    python3 - "$DEVICE_JSON" "$DEVICE_UDID" <<'PY' || true
import json, sys
data = json.load(open(sys.argv[1]))
for d in data.get("result", {}).get("devices", []):
    if d.get("identifier") == sys.argv[2]:
        hw, props = d.get("hardwareProperties", {}), d.get("deviceProperties", {})
        print(f"productType={hw.get('productType')} marketingName={hw.get('marketingName')} "
              f"platform={hw.get('platform')} osVersion={props.get('osVersionNumber')} "
              f"osBuild={props.get('osBuildUpdate')} hasInternalOSBuild={props.get('hasInternalOSBuild')}")
PY
    echo "--- signing ---"
    echo "team=$TEAM"
} > "$OUT/toolchain.txt" 2>&1


echo "installing…"
if ! xcrun devicectl device install app --device "$DEVICE_UDID" "$APP" > "$OUT/install.txt" 2>&1; then
    fail "install failed. See $OUT/install.txt"
    tail -20 "$OUT/install.txt" >&2
    exit 5
fi
echo "installed   ✓"

collect_container() {
    # Pull the app's Documents directory (logs + PNGs) off the device.
    #
    # This is the PRIMARY evidence source: the harness writes its measurements into its own
    # Documents directory, and nothing on the host can forge or filter them.
    local stage="$OUT/.stage"
    mkdir -p "$stage" "$OUT/app-documents"
    if ! xcrun devicectl device copy from \
            --device "$DEVICE_UDID" \
            --domain-type appDataContainer \
            --domain-identifier "$BUNDLE_ID" \
            --source Documents \
            --destination "$stage" > "$OUT/copy-from.txt" 2>&1; then
        echo "WARNING: could not copy Documents off the device; see $OUT/copy-from.txt" >&2
        tail -5 "$OUT/copy-from.txt" >&2 || true
        return 1
    fi
    # devicectl may stage as <stage>/Documents/* or <stage>/*; flatten either shape.
    find "$stage" -type f -exec cp -f {} "$OUT/app-documents/" \; 2>/dev/null || true
    rm -rf "$stage"
    ls -la "$OUT/app-documents/"
}

collect_device_log() {
    # Supplementary: the device's unified log for our subsystem, for cross-checking the file log.
    local archive="$OUT/device-log.logarchive"
    if ! log collect --device-udid "$DEVICE_UDID" --last 5m --output "$archive" >/dev/null 2>&1; then
        echo "note: 'log collect' from the device was unavailable; the app-side log is primary anyway" \
            > "$OUT/unified-log.txt"
        return 0
    fi
    log show --archive "$archive" --predicate \
        'subsystem == "com.screenguard.capturematrix"' --style compact \
        > "$OUT/unified-log.txt" 2>&1 || true
    rm -rf "$archive"
}

# `-Hold` means "how long to keep the on-screen state up so the display can be looked at". Both
# probes that read it (renderSanity, feasibility) default to a value that is too short for an
# operator to react, so it is passed explicitly per mode rather than shared. A single shared value
# would silently stretch the feasibility hold, which is a different phase of that probe.
hold_for_mode() {
    case "$1" in
        renderSanity) echo "${RENDER_SANITY_HOLD:-30}" ;;
        feasibility)  echo "${FEASIBILITY_HOLD:-12}" ;;
        *)            echo "1" ;;   # matrix does not read -Hold
    esac
}

# `devicectl device capture screenshot` is a DEVICE-side capture. Whether it honours capture
# protection is NOT something this harness has measured, so its output is classified DISPLAY- and is
# used ONLY to answer "is the protected layer painting on screen at all?". It is never a no-leak
# verdict. That is why the operator is also asked for a photograph: a camera is the one display view
# no capture API can influence, and it is the tie-breaker if the device screenshot disagrees.
device_screenshot() {
    xcrun devicectl device capture screenshot \
        --device "$DEVICE_UDID" --destination "$OUT/DISPLAY-ground-truth.png" \
        > "$OUT/device-screenshot.txt" 2>&1 || true
}

for MODE in $MODES; do
    echo
    echo "=== mode: $MODE ==="
    HOLD="$(hold_for_mode "$MODE")"
    echo "hold        : ${HOLD}s"

    if ! xcrun devicectl device process launch \
            --device "$DEVICE_UDID" \
            --terminate-existing \
            --activate \
            "$BUNDLE_ID" -Mode "$MODE" -RunID "$RUN_ID" -Hold "$HOLD" \
            > "$OUT/launch-$MODE.txt" 2>&1; then
        fail "launch failed for mode=$MODE. See $OUT/launch-$MODE.txt"
        tail -10 "$OUT/launch-$MODE.txt" >&2
        exit 5
    fi

    case "$MODE" in
        renderSanity)
            # Wait until the app is holding the three cases, then look at the DISPLAY.
            sleep 8
            device_screenshot
            cat <<EOF

  ---------------------------------------------------------------
  PHOTOGRAPH THE DEVICE SCREEN NOW (~$((HOLD - 8)) s remaining).

  Three bands, top to bottom:
    A  preventsCapture=true  (set after add)   expected rgb(229,25,25) red
    B  preventsCapture=true  (set before add)  expected rgb(38,191,64)  green
    C  preventsCapture=false (control)         expected rgb(242,216,25) yellow

  A magenta (rgb 200,0,160) band means that layer painted NOTHING.
  The photograph is the only view of the display that no capture API can
  influence, so it is the tie-breaker if the device screenshot disagrees.
  Save it as:
      $OUT/DISPLAY-photograph.png
  ---------------------------------------------------------------

EOF
            sleep $((HOLD - 8))
            ;;
        feasibility)
            # The probe holds HOLD seconds for the display view, then runs two 60-frame passes.
            sleep 8
            device_screenshot
            sleep $((HOLD - 8 + 10))
            ;;
        replayKit)
            # 30s startCapture bound + 15s recording bound + slack.
            sleep 60
            ;;
        *)
            # matrix: app-render, then RPScreenRecorder (12s bounded), then layer.render.
            sleep 40
            ;;
    esac

    collect_container || true
    collect_device_log

    # Per-mode log excerpts, printed as the Simulator script does.
    for candidate in "$OUT/app-documents/matrix-$RUN_ID.log" \
                     "$OUT/app-documents/feasibility-$RUN_ID.log" \
                     "$OUT/app-documents/rendersanity-$RUN_ID.log"; do
        if [[ -f "$candidate" ]]; then
            echo "--- $(basename "$candidate") ---"
            cat "$candidate"
            echo
        fi
    done
done

# --- Interpretation ------------------------------------------------------------------------------

echo
echo "=== renderSanity interpretation ==="
# Prefer the operator's photograph: it is the only display view no capture API can influence.
SANITY_IMAGE=""
for candidate in "$OUT/DISPLAY-photograph.png" "$OUT/DISPLAY-ground-truth.png"; do
    [[ -f "$candidate" ]] && { SANITY_IMAGE="$candidate"; break; }
done

if [[ -z "$SANITY_IMAGE" ]]; then
    echo "NOT INTERPRETED: no display image found."
    echo "  The device screenshot may not have been written, and no photograph was saved."
else
    echo "using: $SANITY_IMAGE"
    python3 "$ROOT/Research/Scripts/interpret_render_sanity.py" "$SANITY_IMAGE" || true
fi

echo
echo "=== verdicts from the app-side renders (the paths that matter) ==="
# Auto-discover every capture PNG rather than hardcoding two names. On a device the
# RPScreenRecorder path may FINALLY deliver frames, which writes a third PNG
# (capture-system-capture-RPScreenRecorder.png) that did not exist on Simulator - and that file is
# the single most important new artifact of the whole run. Hardcoding the list would silently skip it.
shopt -s nullglob
CAPTURE_PNGS=("$OUT/app-documents/capture-"*.png)
shopt -u nullglob

if [[ ${#CAPTURE_PNGS[@]} -eq 0 ]]; then
    echo "NONE FOUND: no capture-*.png in $OUT/app-documents"
    echo "  The app-side renders produced nothing. Check the mode logs above and $OUT/launch-*.txt."
else
    for png in "${CAPTURE_PNGS[@]}"; do
        echo
        echo "### $(basename "$png")"
        python3 "$ROOT/Research/Scripts/analyze_capture.py" "$png" || true
    done
fi

echo
echo "=== recording-path status ==="
if [[ -f "$OUT/app-documents/capture-system-capture-RPScreenRecorder.png" ]]; then
    echo "The recording path DELIVERED FRAMES on this device (see the PNG analysed above)."
    echo "This is the first real recording-path data for the project - treat it as the headline result."
else
    echo "The recording path produced NO analysable frame on this device."
    grep -E "system-capture|RPScreenRecorder|RK " "$OUT/app-documents/matrix-$RUN_ID.log" 2>/dev/null \
        | tail -8 || echo "  (no system-capture lines in the matrix log)"
    cat <<'MSG'
  That is a RESULT, not a failure of the run. Record it verbatim, including whether a consent
  prompt appeared. Do not retry until it produces frames.
MSG
fi

cat <<EOF

=== device run complete ===
artifacts : $OUT

NOTHING HERE IS A VERDICT YET. These are raw measurements from one device and one OS build.
To turn them into evidence, compare each cell against docs/evidence/capability-matrix.md and
record the device model, iOS build, and date alongside it. In particular:

  * renderSanity answers "does the protected layer paint on screen?" - read its VERDICT line.
  * matrix answers the screenshot-like (drawHierarchy) and recording (RPScreenRecorder) cells.
  * feasibility answers fidelity and cost for arbitrary content.
  * The recording path may prompt for consent on first run. If it reports no frames, that is a
    result: record it as such rather than retrying until it looks better.

Re-verify any PNG independently with:
  python3 Research/Scripts/analyze_capture.py <png>
EOF
