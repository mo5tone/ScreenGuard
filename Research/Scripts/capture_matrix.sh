#!/usr/bin/env bash
# Capture-protection capability matrix: build the harness, run it on a Simulator, and pull the raw
# measurement artifacts (log + PNG per capture path) back into the repo.
#
#   Research/Scripts/capture_matrix.sh                 # technique x capture-path matrix
#   Research/Scripts/capture_matrix.sh --mode feasibility
#   Research/Scripts/capture_matrix.sh --device "iPhone 17 Pro" --runtime 26.2
#
# Everything this script produces lands in Research/Artifacts/<run-id>/ and is quoted verbatim in
# docs/evidence/capability-matrix.md. The script never interprets the numbers - it only moves them.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HARNESS="$ROOT/Research/CaptureMatrix"
BUNDLE_ID="com.screenguard.capturematrix"
MODE="matrix"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
RUNTIME_FILTER="${RUNTIME_FILTER:-}"
KEEP_CONTRAST=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) MODE="$2"; shift 2 ;;
        --device) DEVICE_NAME="$2"; shift 2 ;;
        --runtime) RUNTIME_FILTER="$2"; shift 2 ;;
        --no-contrast) KEEP_CONTRAST=0; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

RUN_ID="$(date +%Y%m%d-%H%M%S)-$MODE"
OUT="$ROOT/Research/Artifacts/$RUN_ID"
DD="$HARNESS/Derived/DD"
mkdir -p "$OUT"

# --- Resolve the simulator -------------------------------------------------

UDID=$(python3 - "$DEVICE_NAME" "$RUNTIME_FILTER" <<'PY'
import json, subprocess, sys
name, runtime_filter = sys.argv[1], sys.argv[2]
# Runtime identifiers look like "com.apple.CoreSimulator.SimRuntime.iOS-26-2", so a user-supplied
# "26.2" has to be normalised before it can match.
normalised = runtime_filter.replace(".", "-")
data = json.loads(subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                                 capture_output=True, text=True).stdout)
for runtime, devices in sorted(data["devices"].items()):
    if normalised and normalised not in runtime:
        continue
    for device in devices:
        if device["name"] == name:
            print(device["udid"]); print(runtime, file=sys.stderr); sys.exit(0)
sys.exit(f"no available simulator named {name!r} (runtime filter {runtime_filter!r})")
PY
)
RUNTIME=$(xcrun simctl list devices available | grep -B0 "$UDID" >/dev/null 2>&1 || true)
echo "run-id      : $RUN_ID"
echo "simulator   : $DEVICE_NAME ($UDID)"

# --- Build ------------------------------------------------------------------

echo "building…"
xcodebuild build -project "$HARNESS/CaptureMatrix.xcodeproj" -scheme CaptureMatrix \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" \
    > "$OUT/build.log" 2>&1 || { echo "build failed; see $OUT/build.log"; tail -30 "$OUT/build.log"; exit 1; }
grep -E "BUILD (SUCCEEDED|FAILED)" "$OUT/build.log" | tail -1

APP="$DD/Build/Products/Debug-iphonesimulator/CaptureMatrix.app"
xcodebuild -version > "$OUT/toolchain.txt"
swift --version >> "$OUT/toolchain.txt" 2>&1 || true
xcrun simctl list devices available | grep -F "$UDID" >> "$OUT/toolchain.txt" || true

# --- Run --------------------------------------------------------------------

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

echo "launching (mode=$MODE)…"
xcrun simctl launch "$UDID" "$BUNDLE_ID" -Mode "$MODE" -RunID "$RUN_ID" > "$OUT/launch.txt"

if [[ "$MODE" == "renderSanity" ]]; then
    # The host screenshot is the only ground truth for what the *display* is showing, which is what
    # separates "the layer never painted" from "the layer painted but was excluded from the capture".
    sleep 6
    xcrun simctl io "$UDID" screenshot "$OUT/DISPLAY-ground-truth.png" 2>&1 | grep -v "^Note:" || true
    sleep 18
elif [[ "$MODE" == "replayKit" ]]; then
    # 30s startCapture bound + 15s recording bound + slack.
    sleep 60
elif [[ "$MODE" == "feasibility" ]]; then
    # The probe holds 12s so the display screenshot below lands while the layers are up; then it
    # runs two 60-frame throughput passes.
    sleep 8
    xcrun simctl io "$UDID" screenshot "$OUT/DISPLAY-ground-truth.png" 2>&1 | grep -v "^Note:" || true
    sleep 25
else
    sleep 25
fi

# Unified-log copy, for cross-checking the file-based log.
xcrun simctl spawn "$UDID" log show --last 3m --predicate \
    'subsystem == "com.screenguard.capturematrix"' --style compact \
    > "$OUT/unified-log.txt" 2>&1 || true

# --- Contrast measurement (NOT evidence) ------------------------------------

if [[ "$KEEP_CONTRAST" == "1" && "$MODE" != "renderSanity" && "$MODE" != "feasibility" ]]; then
    # xcrun simctl io screenshot reads the simulator's display surface from the host and therefore
    # bypasses the render server's capture protection. It is recorded ONLY as a contrast: it shows
    # what the protection is not, never what it is.
    xcrun simctl io "$UDID" screenshot "$OUT/CONTRAST-host-screenshot.png" 2>&1 | grep -v "^Note:" || true
fi

# --- Pull artifacts out of the app container --------------------------------

CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
echo "container   : $CONTAINER"
mkdir -p "$OUT/app-documents"
cp -f "$CONTAINER/Documents/"* "$OUT/app-documents/" 2>/dev/null || true
ls -la "$OUT/app-documents/"

# --- Report -----------------------------------------------------------------

echo
echo "=== matrix log ==="
cat "$OUT/app-documents/matrix-$RUN_ID.log" 2>/dev/null || echo "(no matrix log produced)"
if [[ "$MODE" == "feasibility" ]]; then
    echo
    echo "=== feasibility log ==="
    cat "$OUT/app-documents/feasibility-$RUN_ID.log" 2>/dev/null || echo "(no feasibility log produced)"
fi

echo
echo "artifacts in $OUT"
