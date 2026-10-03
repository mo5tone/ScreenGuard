#!/usr/bin/env bash
#
# verify_capture.sh — one command that builds the example app, runs it on a Simulator, and prints an
# explicit PASS / FAIL verdict per ScreenGuard capability.
#
#     Scripts/verify_capture.sh
#     Scripts/verify_capture.sh --device "iPhone 17 Pro" --runtime 26.2
#     Scripts/verify_capture.sh --print-device-command     # what a physical-device run would need
#
# EXIT CODES
#   0  every Simulator-checkable assertion passed
#   1  at least one Simulator-checkable assertion FAILED
#   2  the run could not be completed (build failure, missing driver, missing artifacts)
#
# ============================================================================================
#  THE HONESTY RULES THIS SCRIPT IS BUILT AROUND — read before changing a verdict
# ============================================================================================
#
#  1. HOST-SIDE CAPTURE IS NEVER EVIDENCE.
#     `xcrun simctl io screenshot` (and sim-use `screenshot` / `record-video`) read the simulator's
#     display surface from the HOST and bypass render-server capture protection by construction
#     (docs/TOOLING.md §2). This script does take one, and uses it ONLY as a *discriminator* between
#     two very different readings of the same region:
#
#         app-side render reads BLANK  +  display reads the CONTENT  -> genuine capture exclusion
#         app-side render reads BLANK  +  display reads BLANK        -> the region never painted
#
#     That distinction is exactly what docs/TOOLING.md §7.1 requires, because on Simulator
#     `preventsCapture = true` makes the layer paint NOTHING AT ALL. The host screenshot is therefore
#     labelled CONTRAST(host-side-bypass) everywhere and is never allowed to produce a no-leak PASS.
#
#  2. THE NO-LEAK READ COMES FROM IN-APP `drawHierarchy` ONLY.
#     The demo writes the read it took with
#     `window.drawHierarchy(in:afterScreenUpdates:false)` — the app-side, screenshot-like path that
#     reproduced the documented secure-field behaviour (docs/evidence/capability-matrix.md §5).
#     `afterScreenUpdates` must stay `false`; `true` is a SIGABRT (docs/TOOLING.md §5).
#
#  3. A BLANK REGION IS AMBIGUOUS, SO EVERY REGION SITS ON A SENTINEL.
#     The demo paints magenta (200,0,160) behind every protected region. A blanked region reading
#     magenta means its pixels were excluded from the read; reading black means an opaque black
#     backing was captured instead. Reading the *content colour* means it leaked.
#
#  4. WHAT THE SIMULATOR CANNOT ANSWER IS PRINTED AS DEVICE-REQUIRED, NEVER AS A PASS.
#     See the "NOT CHECKABLE ON SIMULATOR" block at the end of the output.
#
#  5. THE CONTROL REGION IS MANDATORY.
#     An unshielded region carrying the same content must read the content colour. Without it, "the
#     protected regions are blank" could just mean "this read path cannot image anything"
#     (docs/evidence/capability-matrix.md §3 row 7).
#
# ============================================================================================

set -euo pipefail

# ---------------------------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------------------------

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Examples/ScreenGuardDemo/ScreenGuardDemo.xcodeproj"
SCHEME="ScreenGuardDemo"
BUNDLE_ID="com.screenguard.demo"
DERIVED_DATA="$ROOT/.build/demo-dd"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
RUNTIME_FILTER="${RUNTIME_FILTER:-26.2}"
RUN_ID="$(date +%Y%m%d-%H%M%S)-verify"
SKIP_BUILD=0
PRINT_DEVICE_COMMAND=0
# Every run keeps its artifacts; the path is printed at the end. There is no cleanup step.
ARTIFACTS=""

# The private-API opt-in. The private secure-layer path is a PRIVATE API: non-contract, fragile
# across iOS releases, App Review risk, and never a security guarantee (docs/api-contract.md §9).
# The script grants it for the private-path check because that path is opt-in by design and cannot be
# exercised otherwise. The check itself is labelled PRIVATE-API so the reader cannot mistake it for
# the package's default posture.
PRIVATE_OPT_IN=1

usage() {
    sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

Options:
  --device NAME        Simulator device name          (default: iPhone 17 Pro)
  --runtime VERSION    iOS runtime, e.g. 26.2         (default: 26.2)
  --run-id ID          Override the artifact directory name
  --skip-build         Reuse the last build in .build/demo-dd
  --no-private-opt-in  Do not exercise the opt-in private path (its check becomes SKIPPED)
  --print-device-command
                       Print the physical-device command and exit
  -h, --help           This text
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)   DEVICE_NAME="$2"; shift 2 ;;
        --runtime)  RUNTIME_FILTER="$2"; shift 2 ;;
        --run-id)   RUN_ID="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --no-private-opt-in) PRIVATE_OPT_IN=0; shift ;;
        --print-device-command) PRINT_DEVICE_COMMAND=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------------------------
# The physical-device command — printed, never faked
# ---------------------------------------------------------------------------------------------

print_device_command() {
    cat <<'EOF'
Physical-device run — REQUIRED for the checks the Simulator cannot answer.

  A real iOS screenshot cannot be triggered on the Simulator: it is side button + volume-up
  together, and sim-use exposes no volume button (docs/TOOLING.md §2). Screen recording delivers
  ZERO callbacks on the Simulator (docs/TOOLING.md §7.3). App-switcher snapshot pixels are written
  in a proprietary KTX variant neither ImageMagick nor ffmpeg can decode (docs/TOOLING.md §4).

  Build the demo for a device (this needs a signing team; the project sets CODE_SIGNING_ALLOWED: NO
  for Simulator builds and the command line overrides it here):

    xcodebuild build -project Examples/ScreenGuardDemo/ScreenGuardDemo.xcodeproj \\
      -scheme ScreenGuardDemo \\
      -destination 'generic/platform=iOS' \\
      -derivedDataPath .build/demo-dd-device \\
      CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic \\
      DEVELOPMENT_TEAM=<TEAMID> CODE_SIGN_IDENTITY="Apple Development"

  Then, with the device connected, unlocked and in Developer Mode:

    xcrun devicectl device install app --device <UDID-or-name> \\
      .build/demo-dd-device/Build/Products/Debug-iphoneos/ScreenGuardDemo.app
    xcrun devicectl device process launch --device <UDID-or-name> com.screenguard.demo \\
      -- -ProbeMode noLeak -RunID device-noleak -PrivateOptIn 1

  On the device, press side + volume-up while the demo is showing, then read the artifacts with:

    xcrun devicectl device copy from --device <UDID-or-name> \\
      --domain-type appDataContainer --domain-identifier com.screenguard.demo \\
      --source Documents --destination ./device-artifacts

  Every device result must be recorded with the device model, the iOS build and the date.
  See docs/evidence/device-run-procedure.md for the measurement harness's equivalent procedure.
EOF
}

if [[ "$PRINT_DEVICE_COMMAND" == "1" ]]; then
    print_device_command
    exit 0
fi

# ---------------------------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------------------------

ARTIFACTS="$ROOT/.build/verify-capture/$RUN_ID"
mkdir -p "$ARTIFACTS"

# Verdict counters. `FAIL` is what drives the exit code; `SKIP` and `DEVICE` do not.
FAIL_COUNT=0
PASS_COUNT=0
DEVICE_COUNT=0
SKIP_COUNT=0
FINDING_COUNT=0

# Column width for the verdict table.
COL=58

rule() { printf '%*s\n' 96 '' | tr ' ' '-'; }

# Prints one graded assertion.
#
#   record PASS|FAIL|DEVICE|SKIP|FINDING  "check name"  "what was observed"
record() {
    local kind="$1" name="$2" detail="${3:-}"
    printf '  [%-7s] %-*s %s\n' "$kind" "$COL" "$name" "$detail"
    case "$kind" in
        PASS)    PASS_COUNT=$((PASS_COUNT + 1)) ;;
        FAIL)    FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        DEVICE)  DEVICE_COUNT=$((DEVICE_COUNT + 1)) ;;
        SKIP)    SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
        FINDING) FINDING_COUNT=$((FINDING_COUNT + 1)) ;;
    esac
}

section() {
    echo
    rule
    echo "  $1"
    rule
}

die() {
    echo >&2
    echo "FATAL: $1" >&2
    exit 2
}

# ---------------------------------------------------------------------------------------------
# Sampling helpers — shared by every pixel section
# ---------------------------------------------------------------------------------------------

# The region sampler's path. Set once, here, so every pixel section grades the same file.
SAMPLER="$ARTIFACTS/sample_regions.py"

# Writes the region sampler to $ARTIFACTS/sample_regions.py.
#
# A function rather than an inline block because TWO sections need it: section 3 (the no-leak
# page) and section 3b (the SwiftUI-route page). It used to live inside section 3's success
# branch, so a missing no-leak artifact left every later pixel check with no sampler at all.
# Idempotent: it overwrites the same file with the same bytes.
write_sampler() {
    cat > "$SAMPLER" <<'PYTHON'
"""Sample ScreenGuard's probe regions out of PNGs using only the standard library.

Decoding is done by hand (zlib + the five PNG filter types) so the verification needs no Python
packages at all — a fresh clone on a clean machine runs it.

Usage: sample_regions.py <app-side.png|-> <host-contrast.png|-> <regions.json>

Prints one line per (image, region):
    <image>|<region>|<mean r,g,b>|<median r,g,b>|<maxChannel>|<samples>
"""
import json
import struct
import sys
import zlib


def read_png(path):
    """Decode an 8-bit non-interlaced PNG into (width, height, channels, bytes)."""
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    offset = 8
    header = None
    idat = bytearray()
    palette = None
    while offset < len(data):
        (length,) = struct.unpack(">I", data[offset:offset + 4])
        kind = data[offset + 4:offset + 8]
        body = data[offset + 8:offset + 8 + length]
        offset += 12 + length
        if kind == b"IHDR":
            width, height, depth, colour, compression, filter_method, interlace = \
                struct.unpack(">IIBBBBB", body)
            if depth != 8:
                raise ValueError(f"{path}: expected 8 bits per channel, got {depth}")
            if interlace != 0:
                raise ValueError(f"{path}: interlaced PNGs are not supported")
            channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
            header = (width, height, channels)
        elif kind == b"PLTE":
            palette = body
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    if header is None:
        raise ValueError(f"{path}: no IHDR")
    width, height, channels = header
    if palette is not None:
        raise ValueError(f"{path}: palette PNGs are not supported")

    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    out = bytearray(height * stride)
    previous = bytearray(stride)
    position = 0
    for row in range(height):
        filter_type = raw[position]
        position += 1
        line = bytearray(raw[position:position + stride])
        position += stride
        if filter_type == 1:      # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif filter_type == 2:    # Up
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif filter_type == 3:    # Average
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif filter_type == 4:    # Paeth
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                up = previous[i]
                upleft = previous[i - channels] if i >= channels else 0
                estimate = left + up - upleft
                da, db, dc = abs(estimate - left), abs(estimate - up), abs(estimate - upleft)
                if da <= db and da <= dc:
                    predictor = left
                elif db <= dc:
                    predictor = up
                else:
                    predictor = upleft
                line[i] = (line[i] + predictor) & 0xFF
        elif filter_type != 0:
            raise ValueError(f"{path}: unknown filter type {filter_type}")
        out[row * stride:(row + 1) * stride] = line
        previous = line
    return width, height, channels, bytes(out)


def sample(png, rect, columns=32, rows=32):
    """Mean / median / maxChannel over a normalised rect, sampled on a fixed grid."""
    width, height, channels, pixels = png
    collected = []
    for row in range(rows):
        fy = rect[1] + rect[3] * (row + 0.5) / rows
        y = min(height - 1, max(0, int(fy * height)))
        for column in range(columns):
            fx = rect[0] + rect[2] * (column + 0.5) / columns
            x = min(width - 1, max(0, int(fx * width)))
            offset = (y * width + x) * channels
            collected.append((pixels[offset], pixels[offset + 1], pixels[offset + 2]))
    if not collected:
        return None
    count = len(collected)
    mean = tuple(round(sum(p[i] for p in collected) / count) for i in range(3))
    median = tuple(sorted(p[i] for p in collected)[count // 2] for i in range(3))
    max_channel = max(max(p) for p in collected)
    return mean, median, max_channel, count


def main():
    app_side, contrast, regions_path = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(regions_path) as handle:
        regions = json.load(handle)

    # ONE IMAGE AT A TIME, AND A BAD IMAGE ONLY EVER COSTS ITS OWN ROWS.
#
    # This used to decode both images first and then sample. A single unreadable file (a missing
    # contrast capture, a truncated PNG, an unexpected bit depth) therefore raised before the first
    # print, and the samples file came out EMPTY — so every region on BOTH images read as
    # UNREADABLE. That collapsed two independent readings into one silent failure and made a
    # downstream check pass vacuously. Each image is now handled independently and a failure emits
    # an explicit `UNREADABLE` row per region, which every caller already knows how to grade.
    sources = [("app-side", app_side), ("host-contrast", contrast)]

    for label, path in sources:
        png = None
        if path != "-":
            try:
                png = read_png(path)
            except Exception as error:  # missing file, bad magic, unsupported depth, bad zlib...
                sys.stderr.write(f"{label}: unreadable image {path}: {error}\n")
        for region in regions:
            if png is None:
                print(f"{label}|{region['name']}|UNREADABLE")
                continue
            result = sample(png, region["bodyRect"])
            if result is None:
                print(f"{label}|{region['name']}|UNREADABLE")
                continue
            mean, median, max_channel, count = result
            print(
                f"{label}|{region['name']}|{mean[0]},{mean[1]},{mean[2]}|"
                f"{median[0]},{median[1]},{median[2]}|{max_channel}|{count}"
            )


if __name__ == "__main__":
    main()
PYTHON
}

# Look up one reading.
#
#   reading_from <samples-file> <image-label> <region> <field>
#     field: mean | median | max
#
# Prints `UNREADABLE` when there is no matching row. That matters: with the old `awk` a missing
# row printed an empty string, `classify ""` printed `UNREADABLE`, and any caller that tested
# only for `== SENSITIVE` (rather than for `!= UNREADABLE`) turned "we could not read the
# pixels" into a pass.
reading_from() {
        awk -F'|' -v image="$2" -v region="$3" -v field="$4" '
            $1 == image && $2 == region {
                found = 1
                if (field == "mean")   { print $3 }
                else if (field == "median") { print $4 }
                else { print $5 }
            }
            END { if (!found) print "UNREADABLE" }
        ' "$1"
}

# Classify a reading against the demo's reference colours. The tolerance is generous (40) because
# the capture path re-encodes through a different colour pipeline; the reference colours (blue,
# magenta, black) are far enough apart that 40 cannot confuse two of them.
classify() {
        local rgb="$1"
        [[ -z "$rgb" || "$rgb" == "UNREADABLE" ]] && { echo UNREADABLE; return; }
        python3 - "$rgb" <<'PY'
import sys
r, g, b = (float(v) for v in sys.argv[1].split(","))
SENSITIVE = (38.0, 102.0, 242.0)
SENTINEL = (200.0, 0.0, 160.0)

def distance(colour, reference):
    return max(abs(colour[i] - reference[i]) for i in range(3))

if distance((r, g, b), SENSITIVE) <= 40:
    print("SENSITIVE")
elif distance((r, g, b), SENTINEL) <= 40:
    print("SENTINEL")
elif max(r, g, b) < 32:
    print("BLACK")
else:
    print("OTHER")
PY
}

# ---------------------------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------------------------

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found. Install Xcode."
command -v python3    >/dev/null 2>&1 || die "python3 not found."
command -v xcrun      >/dev/null 2>&1 || die "xcrun not found. Install Xcode command line tools."

# sim-use is a DRIVER, never evidence (docs/TOOLING.md §2). It is the only reliable way to
# background an app headlessly, which is what the app-switcher synchrony check needs.
HAVE_SIM_USE=0
if command -v sim-use >/dev/null 2>&1; then
    HAVE_SIM_USE=1
fi

# ---------------------------------------------------------------------------------------------
# Resolve the Simulator
# ---------------------------------------------------------------------------------------------

resolve_udid() {
    python3 - "$DEVICE_NAME" "$RUNTIME_FILTER" <<'PY'
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
            print(device["udid"])
            sys.exit(0)
sys.exit(f"no available simulator named {name!r} (runtime filter {runtime_filter!r})")
PY
}

section "ScreenGuard — capture verification"
echo "  run id      : $RUN_ID"
echo "  artifacts   : $ARTIFACTS"
echo "  project     : Examples/ScreenGuardDemo/ScreenGuardDemo.xcodeproj"
echo "  package     : consumed as a LOCAL package dependency at ../.. (relative path)"

UDID="$(resolve_udid)" || die "could not resolve a simulator for '$DEVICE_NAME' / '$RUNTIME_FILTER'"
echo "  simulator   : $DEVICE_NAME ($UDID)"
echo "  driver      : sim-use $( [[ "$HAVE_SIM_USE" == "1" ]] && echo available || echo MISSING )"
echo "  private API : opt-in $( [[ "$PRIVATE_OPT_IN" == "1" ]] && echo GRANTED || echo NOT-granted )"

# ---------------------------------------------------------------------------------------------
# 1. Build — the drop-in-consumption proof
# ---------------------------------------------------------------------------------------------

section "1. Build — the example consumes ScreenGuard as a local package dependency"

# The generated Xcode project is not guaranteed to be present after a clone: this repository's root
# `.gitignore` carries a `*.xcodeproj` rule, so a fresh checkout gets
# `Examples/ScreenGuardDemo/project.yml` and nothing else. Regenerating it here keeps the
# "clone, run one command" promise honest instead of failing with "project not found". XcodeGen is
# needed only in this case, and only for the example app.
if [[ ! -d "$PROJECT" ]]; then
    if command -v xcodegen >/dev/null 2>&1; then
        echo "  $PROJECT is missing (it is gitignored) — generating it from project.yml..."
        if ( cd "$(dirname "$PROJECT")" && xcodegen generate ) > "$ARTIFACTS/xcodegen.log" 2>&1; then
            record PASS "generated the missing Xcode project from project.yml" "xcodegen"
        else
            record FAIL "generated the missing Xcode project from project.yml" "see $ARTIFACTS/xcodegen.log"
            echo
            echo "  RESULT: FAILED (project generation)"
            exit 1
        fi
    else
        die "$PROJECT is missing and xcodegen is not installed. Install XcodeGen (brew install xcodegen) and run 'xcodegen generate' inside Examples/ScreenGuardDemo."
    fi
fi

BUILD_LOG="$ARTIFACTS/build.log"
if [[ "$SKIP_BUILD" == "1" ]]; then
    record SKIP "demo builds against the local package" "--skip-build was passed"
else
    echo "  building (this is the drop-in proof: the app target has no package sources of its own)..."
    if xcodebuild build \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,id=$UDID" \
        -derivedDataPath "$DERIVED_DATA" \
        > "$BUILD_LOG" 2>&1
    then
        record PASS "demo builds against the local package" "$(grep -c 'BUILD SUCCEEDED' "$BUILD_LOG" >/dev/null && echo 'BUILD SUCCEEDED')"
    else
        record FAIL "demo builds against the local package" "see $BUILD_LOG"
        tail -25 "$BUILD_LOG" >&2
        echo
        echo "  RESULT: FAILED (build)"
        exit 1
    fi
fi

APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/$SCHEME.app"
[[ -d "$APP" ]] || die "built app not found at $APP"

# ---------------------------------------------------------------------------------------------
# Simulator plumbing
# ---------------------------------------------------------------------------------------------

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true

# Pull the app's Documents directory into the artifact folder.
collect() {
    local dest="$1"
    local container
    container="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)"
    [[ -n "$container" ]] || return 1
    mkdir -p "$dest"
    cp -f "$container/Documents/"* "$dest/" 2>/dev/null || true
}

# Launch a probe and wait for it to write its artifacts.
#
#   run_probe <ProbeMode> <extra args...>
run_probe() {
    local mode="$1"; shift
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 1
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -ProbeMode "$mode" -RunID "$RUN_ID" "$@" >/dev/null
}

install_app() {
    xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl install "$UDID" "$APP" || die "could not install $APP"
}

install_app
echo
echo "  installed $BUNDLE_ID on $UDID"

# ---------------------------------------------------------------------------------------------
# 2. Capability honesty — the demo must not imply prevention
# ---------------------------------------------------------------------------------------------

section "2. Capability registry — the demo must not imply prevention"

CAP_DIR="$ARTIFACTS/capability"
run_probe capability
sleep 4
collect "$CAP_DIR" || true

CAP_JSON="$CAP_DIR/capability-$RUN_ID.json"
if [[ ! -f "$CAP_JSON" ]]; then
    record FAIL "capability registry artifact was written" "expected $CAP_JSON"
else
    # Read the registry out of the app's own artifact, so the verdict reflects what the demo actually
    # rendered rather than what this script believes.
    eval "$(python3 - "$CAP_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
by_name = {c["capability"]: c["status"] for c in data["capabilities"]}
count = len(data["capabilities"])

def shell(name, value):
    print(f'{name}={json.dumps(str(value))}')

shell("CAP_COUNT", count)
shell("CAP_SCREENSHOT", by_name.get("screenshotDetection", "MISSING"))
shell("CAP_PREVENT_SCREENSHOT", by_name.get("preventUserScreenshot", "MISSING"))
shell("CAP_PREVENT_RECORDING", by_name.get("preventUserRecording", "MISSING"))
shell("CAP_RECORDING_PATH", by_name.get("noLeakRecordingPath", "MISSING"))
shell("CAP_PUBLIC_NLEAK", by_name.get("noLeakPublicPreventsCapture", "MISSING"))
shell("CAP_SECURE_FIELD", by_name.get("noLeakSecureTextEntry", "MISSING"))
shell("CAP_WATERMARK", by_name.get("watermark", "MISSING"))
shell("CAP_APP_SWITCHER", by_name.get("appSwitcherSnapshotProtection", "MISSING"))
PY
)"

    # §4 has exactly 10 rows, one enum case each (docs/api-contract.md §5).
    if [[ "$CAP_COUNT" == "10" ]]; then
        record PASS "registry has the 10 rows of docs/api-contract.md §4" "count=$CAP_COUNT"
    else
        record FAIL "registry has the 10 rows of docs/api-contract.md §4" "count=$CAP_COUNT"
    fi

    # The two refusals. This is the check that stops the demo implying prevention.
    if [[ "$CAP_PREVENT_SCREENSHOT" == "notPossible" && "$CAP_PREVENT_RECORDING" == "notPossible" ]]; then
        record PASS "preventing a screenshot / recording reports notPossible" \
            "screenshot=$CAP_PREVENT_SCREENSHOT recording=$CAP_PREVENT_RECORDING"
    else
        record FAIL "preventing a screenshot / recording reports notPossible" \
            "screenshot=$CAP_PREVENT_SCREENSHOT recording=$CAP_PREVENT_RECORDING"
    fi

    # No recording-path claim may be made from Simulator data (docs/TOOLING.md §7.3).
    if [[ "$CAP_RECORDING_PATH" == "notMeasured" ]]; then
        record PASS "no-leak on the recording path reports notMeasured" "$CAP_RECORDING_PATH"
    else
        record FAIL "no-leak on the recording path reports notMeasured" "$CAP_RECORDING_PATH"
    fi

    echo "        registry: secureTextEntry=$CAP_SECURE_FIELD publicPath=$CAP_PUBLIC_NLEAK " \
         "watermark=$CAP_WATERMARK appSwitcher=$CAP_APP_SWITCHER screenshotDetection=$CAP_SCREENSHOT"
fi

# ---------------------------------------------------------------------------------------------
# 3. No-leak — the app-side render path
# ---------------------------------------------------------------------------------------------

section "3. No-leak — app-side render path (window.drawHierarchy)"

NLEAK_DIR="$ARTIFACTS/noleak"

# ⚠️ ORDERING BUG THAT USED TO LIVE HERE — do not remove this `mkdir`.
#
# `xcrun simctl io screenshot <path>` writes the file itself and DOES NOT create the destination
# directory. This directory used to be created later, by `collect`, so the contrast capture failed
# with:
#
#     An error was encountered processing the command (domain=NSCocoaErrorDomain, code=4):
#     The folder "CONTRAST-host-side-display.png" doesn't exist.
#
# and exited 4. The failure was invisible because stderr was discarded and the exit status was
# swallowed by `|| true`. The consequence was not local: `sample_regions.py` then raised
# FileNotFoundError on the very first image it tried to read, printed ZERO sample lines, and every
# region — on BOTH images — was reported UNREADABLE. That single swallowed error is what produced
# the false "control region cannot be imaged" and "excluded region is not visible" failures.
mkdir -p "$NLEAK_DIR"

NLEAK_JSON="$NLEAK_DIR/noleak-$RUN_ID-final.json"
NLEAK_PNG="$NLEAK_DIR/capture-app-render-final.png"
CONTRAST_PNG="$NLEAK_DIR/CONTRAST-host-side-display.png"
CONTRAST_LOG="$ARTIFACTS/contrast-capture.log"
CONTRAST_OK=0

PRIVATE_ARGS=()
[[ "$PRIVATE_OPT_IN" == "1" ]] && PRIVATE_ARGS=(-PrivateOptIn 1)
run_probe noLeak "${PRIVATE_ARGS[@]}"
# The probe reads twice; the second pass is the one graded, because the private canvas can take a
# layout pass to appear.
sleep 9

# CONTRAST ONLY. See rule 1 in this file's header: this reads the display from the host and bypasses
# capture protection by construction. It is collected here purely so "excluded from the capture" can
# be told apart from "never painted" — never to produce a no-leak verdict.
#
# The exit status and the stderr are KEPT. A contrast capture that silently did not happen is worse
# than one that loudly did not happen: it turns every discriminator below into an UNREADABLE.
if xcrun simctl io "$UDID" screenshot "$CONTRAST_PNG" > "$CONTRAST_LOG" 2>&1; then
    CONTRAST_OK=1
fi

sleep 1
collect "$NLEAK_DIR" || true

# The discriminating capture is a Simulator-checkable assertion in its own right: without it the
# private-path verdict below is unearned, so its absence is graded rather than ignored.
if [[ "$CONTRAST_OK" == "1" && -f "$CONTRAST_PNG" ]]; then
    record PASS "host-side contrast capture taken (CONTRAST ONLY, never evidence)" \
        "$(basename "$CONTRAST_PNG") $(wc -c < "$CONTRAST_PNG" | tr -d ' ') bytes"
else
    record FAIL "host-side contrast capture taken (CONTRAST ONLY, never evidence)" \
        "simctl io screenshot failed (exit != 0) — see $CONTRAST_LOG"
fi

if [[ ! -f "$NLEAK_JSON" ]]; then
    record FAIL "the no-leak probe wrote its artifact" "expected $NLEAK_JSON"
else
    # Sample the app-side render (the real no-leak read) and the host-side contrast, and compare.
    # Pure stdlib PNG decoding: no Pillow, no ImageMagick, nothing to install.
    write_sampler

    # The region rectangles come from the app's own artifact, so the two sides cannot drift: if the
    # demo moved a region, this comparison fails rather than silently grading the wrong pixels.
    REGIONS_JSON="$ARTIFACTS/regions.json"
    GEOMETRY_RESULT="$(python3 - "$NLEAK_JSON" "$REGIONS_JSON" <<'PY'
import json, sys

def parse_rect(text):
    return [float(value) for value in text.split(",")]

data = json.load(open(sys.argv[1]))
regions = [
    {"name": r["name"], "normalizedRect": parse_rect(r["normalizedRect"]),
     "bodyRect": parse_rect(r["bodyRect"])}
    for r in data["regions"]
]
json.dump(regions, open(sys.argv[2], "w"), indent=1)

# The scripts own copy of the geometry. If these disagree, the demo and the verification have
# drifted and neither result can be trusted — so this is graded, not merely printed.
EXPECTED = {
    "control":       (0.10, 0.20, 0.80, 0.08),
    "publicShield":  (0.10, 0.46, 0.80, 0.08),
    "privateShield": (0.10, 0.72, 0.80, 0.08),
}
ok = True
for region in regions:
    expected = EXPECTED.get(region["name"])
    if expected is None:
        print(f"unexpected region {region['name']}")
        ok = False
        continue
    if max(abs(a - b) for a, b in zip(region["bodyRect"], expected)) > 1e-6:
        print(f"{region['name']}: {region['bodyRect']} != {list(expected)}")
        ok = False
print("OK" if ok else "MISMATCH")
PY
)"
    GEOMETRY_VERDICT="$(printf '%s\n' "$GEOMETRY_RESULT" | tail -1)"
    if [[ "$GEOMETRY_VERDICT" == "OK" ]]; then
        record PASS "demo and script agree on the sampled region geometry" "3 regions matched"
    else
        record FAIL "demo and script agree on the sampled region geometry" \
            "$(printf '%s' "$GEOMETRY_RESULT" | tr '\n' ' ')"
    fi

    SAMPLES="$ARTIFACTS/samples.txt"
    SAMPLE_ERRORS="$ARTIFACTS/sample-errors.txt"
    SAMPLER_STATUS=0
    python3 "$SAMPLER" "$NLEAK_PNG" "$CONTRAST_PNG" "$REGIONS_JSON" > "$SAMPLES" 2>"$SAMPLE_ERRORS" \
        || SAMPLER_STATUS=$?

    # The sampler is the only thing standing between a PNG and a verdict. If it died, or produced
    # fewer rows than there are (image, region) pairs, every reading below is UNREADABLE — and an
    # UNREADABLE reading must never be allowed to look like a PASS (see the private-path check).
    # Grading the sampler itself makes that failure legible instead of mysterious.
    EXPECTED_ROWS=$(( $(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$REGIONS_JSON") * 2 ))
    ACTUAL_ROWS="$(grep -c '|' "$SAMPLES" 2>/dev/null)" || ACTUAL_ROWS=0
    [[ -n "$ACTUAL_ROWS" ]] || ACTUAL_ROWS=0
    if [[ "$SAMPLER_STATUS" == "0" && "$ACTUAL_ROWS" == "$EXPECTED_ROWS" && "$EXPECTED_ROWS" -gt 0 ]]; then
        record PASS "the region sampler read both PNGs" \
            "$ACTUAL_ROWS rows ($(( ACTUAL_ROWS / 2 )) regions x 2 images)"
    else
        record FAIL "the region sampler read both PNGs" \
            "exit=$SAMPLER_STATUS rows=$ACTUAL_ROWS expected=$EXPECTED_ROWS — $(head -1 "$SAMPLE_ERRORS" 2>/dev/null || echo 'no error output')"
    fi



    echo "  app-side read  : $(basename "$NLEAK_PNG") (window.drawHierarchy — the no-leak read)"
    echo "  host contrast  : CONTRAST(host-side-bypass) — NOT evidence, discriminator only"
    echo

    # --- The control. Mandatory: without it a blank region proves nothing. ---
    CONTROL_APP="$(classify "$(reading_from "$SAMPLES" app-side control mean)")"
    if [[ "$CONTROL_APP" == "SENSITIVE" ]]; then
        record PASS "control region reads the sensitive colour (calibration)" \
            "app-side=$(reading_from "$SAMPLES" app-side control mean)"
    else
        record FAIL "control region reads the sensitive colour (calibration)" \
            "app-side=$(reading_from "$SAMPLES" app-side control mean) -> $CONTROL_APP (the read path cannot image content, so every other reading is meaningless)"
    fi

    # --- The public path. DEVICE-REQUIRED, by measurement, not by preference. ---
    PUBLIC_APP="$(classify "$(reading_from "$SAMPLES" app-side publicShield mean)")"
    PUBLIC_HOST="$(classify "$(reading_from "$SAMPLES" host-contrast publicShield mean)")"
    record DEVICE "no-leak on the public preventsCapture path" \
        "app-side=$PUBLIC_APP contrast=$PUBLIC_HOST — requires a device (docs/TOOLING.md §7.1)"
    echo "        On Simulator, preventsCapture=true makes this layer paint NOTHING AT ALL, including"
    echo "        on screen, so a blank app-side reading here is UNEARNED and is not a PASS."

    # --- The private path. This is the Simulator-checkable no-leak assertion. ---
    if [[ "$PRIVATE_OPT_IN" != "1" ]]; then
        record SKIP "no-leak on the opt-in private path" "--no-private-opt-in was passed"
    else
        # The trait. The private secure-layer swap does not exist in the binary unless the CONSUMER
        # enables the `PrivateAPI` trait (docs/api-contract.md §9.4). Read from the app's own
        # artifact, so this reports the built app's property rather than the manifest's intent.
        NLEAK_PRIVATE_COMPILED="$(python3 - "$NLEAK_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(data.get("privateAPICompiledIn"))
PY
)"
        if [[ "$NLEAK_PRIVATE_COMPILED" == "True" ]]; then
            record PASS "the PrivateAPI trait is compiled into the demo" \
                "privateAPICompiledIn=True (Examples/ScreenGuardDemo/project.yml enables the trait)"
        else
            record FAIL "the PrivateAPI trait is compiled into the demo" \
                "privateAPICompiledIn=$NLEAK_PRIVATE_COMPILED — the demo's package dependency does not enable the PrivateAPI trait, so the opt-in private path cannot engage and no Simulator-checkable no-leak reading is available"
        fi

        PRIVATE_APP="$(classify "$(reading_from "$SAMPLES" app-side privateShield mean)")"
        PRIVATE_HOST="$(classify "$(reading_from "$SAMPLES" host-contrast privateShield mean)")"

        # The assertion: the region must be READABLE and must NOT read the sensitive colour in the
        # app-side read.
    #
        # UNREADABLE is its own outcome and it is a FAILURE, never a pass. This check used to be
        # written as `if [[ "$PRIVATE_APP" == "SENSITIVE" ]]; then FAIL else PASS fi`, so an
        # UNREADABLE reading — which is what a broken sampler produces — came out as
        # "PASS ... (not the content colour)". An unreadable reading is not evidence of anything:
        # it cannot distinguish protection from a region that never painted.
        if [[ "$PRIVATE_APP" == "UNREADABLE" ]]; then
            record FAIL "no-leak: private path excludes the region from the capture" \
                "app-side reading is UNREADABLE — no pixels were sampled, so this is not evidence of protection (see samples.txt / sample-errors.txt)"
        elif [[ "$PRIVATE_APP" == "SENSITIVE" ]]; then
            record FAIL "no-leak: private path excludes the region from the capture" \
                "app-side=$(reading_from "$SAMPLES" app-side privateShield mean) -> LEAKED"
        else
            record PASS "no-leak: private path excludes the region from the capture" \
                "app-side=$(reading_from "$SAMPLES" app-side privateShield mean) -> $PRIVATE_APP (readable, and not the content colour)"
        fi

        # The falsification control: a region that never painted would also be blank. The host-side
        # contrast is the only way to tell those apart, and that is the single legitimate use of a
        # host capture in this script.
        if [[ "$PRIVATE_HOST" == "SENSITIVE" ]]; then
            record PASS "the excluded region is still VISIBLE on the display" \
                "contrast=$PRIVATE_HOST — exclusion, not a non-painting layer"
        else
            record FAIL "the excluded region is still VISIBLE on the display" \
                "contrast=$(reading_from "$SAMPLES" host-contrast privateShield mean) -> $PRIVATE_HOST — the region did not paint on the display, so the blank capture is unearned"
        fi

        echo "        NOTE: the private secure-layer swap is a PRIVATE API — non-contract, fragile"
        echo "        across iOS releases, App Review risk, never a security guarantee"
        echo "        (docs/api-contract.md §9). It is opt-in and off by default in the package."

        # --- Does the shield's self-report agree with the pixels? ---
        # This is reported as a FINDING rather than a FAILED assertion on purpose. The property the
        # package promises is "sensitive content does not leak", and that is verified above by the
        # pixel check. A shield that reports "not protecting" while the pixels ARE excluded is
        # FAIL-CLOSED: it cannot cause a leak, it under-reports its own capability, and it fires a
        # spurious protectionDegraded event. That is a real defect for the package, not a failure of
        # this verification, so it is reported loudly and separately.
    #
        # The comparison is only meaningful when BOTH the app-side reading is readable and non-leaky
        # AND the host side shows the content. Without those two, "the shield disagrees with the
        # pixels" is a claim about pixels that were never read — which is the vacuous version of this
        # finding.
        PRIVATE_IS_PROTECTING="$(python3 - "$NLEAK_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(data.get("shields", {}).get("privateShield", {}).get("isProtecting"))
PY
)"
        PRIVATE_FAILURE="$(python3 - "$NLEAK_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
value = data.get("shields", {}).get("privateShield", {}).get("protectionFailure")
print("none" if value in (None, "null") else value)
PY
)"
        if [[ "$PRIVATE_APP" == "UNREADABLE" || "$PRIVATE_HOST" != "SENSITIVE" ]]; then
            record SKIP "shield self-report vs measured pixels" \
                "not comparable: app-side=$PRIVATE_APP contrast=$PRIVATE_HOST"
        elif [[ "$PRIVATE_IS_PROTECTING" != "True" ]]; then
            record FINDING "shield self-report disagrees with the measured pixels" \
                "isProtecting=False protectionFailure=$PRIVATE_FAILURE while the region IS excluded"
            echo "        The swap took effect (app-side=$PRIVATE_APP, display=$PRIVATE_HOST), but the"
            echo "        shield reports failure. This is fail-closed — it cannot leak — but it is a"
            echo "        real defect: the package under-reports its own capability and raises a"
            echo "        spurious protectionDegraded event. Report it against Sources/."
        else
            record PASS "shield self-report agrees with the measured pixels" "isProtecting=True"
        fi
    fi

    # --- The public path's shield state, for the record. ---
    PUBLIC_IS_PROTECTING="$(python3 - "$NLEAK_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(data.get("shields", {}).get("publicShield", {}).get("isProtecting"))
PY
)"
    echo
    echo "        public path shield: isProtecting=$PUBLIC_IS_PROTECTING mode=$(python3 - "$NLEAK_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(data.get("shields", {}).get("publicShield", {}).get("shieldMode"))
PY
)"
fi

# ---------------------------------------------------------------------------------------------
# 3b. No-leak — the package's OWN SwiftUI route on the private strategy
# ---------------------------------------------------------------------------------------------
#
# WHY THIS SECTION EXISTS (review round 2, finding F-R2-1)
#
#   `screenGuardProtected(strategy: .privateSecureLayer)` is the ergonomic entry point, and it is the
#   one most consumers will actually write. It cannot supply a live `UIView` — SwiftUI content is not
#   one — so `ScreenGuardShieldRepresentable` hands the shield a RENDER CLOSURE and nothing else, and
#   for a long time the private strategy never displayed renderer output. Two independent probes
#   measured `isProtecting = true`, `mode = privateSecureLayer`, `failure = nil` and a BLANK shield.
#
#   Section 3 measures `ScreenGuardShieldView.protectedContentView`, which is a DIFFERENT route and
#   was green throughout. That is exactly why the defect survived: the measured route was not the
#   documented one. This section measures the documented one, end to end, through the package's own
#   modifier with no demo-side shield container.
#
#   THE ASSERTIONS THAT MAKE IT NON-VACUOUS. On this route the shield hosts RENDERED content as a live
#   subview, so:
#     * the unshielded SwiftUI control reads the sensitive colour      -> the read path images SwiftUI;
#     * the shielded region is READABLE and is NOT the sensitive colour -> its pixels were excluded;
#     * the host-side contrast still shows the sensitive colour        -> exclusion, not a dead region;
#     * the shield reports mode/isProtecting AND hosts rendered content -> not a claim over nothing.
#   A blank region with nothing hosted would satisfy "not the sensitive colour" and fail the last two,
#   which is precisely the defect this section exists to catch.

section "3b. No-leak — SwiftUI screenGuardProtected(.privateSecureLayer), the documented route"

SWIFTUI_DIR="$ARTIFACTS/swiftui-private"
mkdir -p "$SWIFTUI_DIR"

if [[ "$PRIVATE_OPT_IN" != "1" ]]; then
    record SKIP "no-leak on the SwiftUI private route" "--no-private-opt-in was passed"
else
    SWIFTUI_JSON="$SWIFTUI_DIR/swiftui-private-$RUN_ID-final.json"
    SWIFTUI_PNG="$SWIFTUI_DIR/capture-swiftui-private-final.png"
    SWIFTUI_CONTRAST_PNG="$SWIFTUI_DIR/CONTRAST-swiftui-private-display.png"
    SWIFTUI_CONTRAST_LOG="$ARTIFACTS/contrast-swiftui-private.log"

    run_probe swiftUIPrivate "${PRIVATE_ARGS[@]}"
    # Same two-pass read as the no-leak page: the private canvas can take a layout pass to appear, and
    # the second pass writes the `-final` artifacts graded here.
    sleep 9

    # CONTRAST ONLY — host-side display capture bypasses capture protection by construction
    # (docs/TOOLING.md §2). It is the discriminator between "excluded" and "never painted".
    SWIFTUI_CONTRAST_OK=0
    if xcrun simctl io "$UDID" screenshot "$SWIFTUI_CONTRAST_PNG" > "$SWIFTUI_CONTRAST_LOG" 2>&1; then
        SWIFTUI_CONTRAST_OK=1
    fi
    sleep 1
    collect "$SWIFTUI_DIR" || true

    if [[ "$SWIFTUI_CONTRAST_OK" == "1" && -f "$SWIFTUI_CONTRAST_PNG" ]]; then
        record PASS "host-side contrast capture taken for the SwiftUI route (CONTRAST ONLY)" \
            "$(basename "$SWIFTUI_CONTRAST_PNG") $(wc -c < "$SWIFTUI_CONTRAST_PNG" | tr -d ' ') bytes"
    else
        record FAIL "host-side contrast capture taken for the SwiftUI route (CONTRAST ONLY)" \
            "simctl io screenshot failed (exit != 0) — see $SWIFTUI_CONTRAST_LOG"
    fi

    if [[ ! -f "$SWIFTUI_JSON" ]]; then
        record FAIL "the SwiftUI-route probe wrote its artifact" "expected $SWIFTUI_JSON"
    else
        write_sampler

        SWIFTUI_REGIONS_JSON="$ARTIFACTS/swiftui-regions.json"
        SWIFTUI_GEOMETRY_RESULT="$(python3 - "$SWIFTUI_JSON" "$SWIFTUI_REGIONS_JSON" <<'PY'
import json, sys

def parse_rect(text):
    return [float(value) for value in text.split(",")]

data = json.load(open(sys.argv[1]))
regions = [
    {"name": r["name"], "normalizedRect": parse_rect(r["normalizedRect"]),
     "bodyRect": parse_rect(r["bodyRect"])}
    for r in data["regions"]
]
json.dump(regions, open(sys.argv[2], "w"), indent=1)

# Own copy of the SwiftUI page geometry, kept here. If these disagree with the app values, the demo
# and the verification have drifted and neither result can be trusted — so this is graded.
#
# NOTE: no apostrophes in this heredoc body. It is nested inside a double-quoted command
# substitution, and macOS ships bash 3.2, whose parser mis-reads an odd apostrophe here as an
# unterminated string and then reports a bogus "unexpected EOF" near the end of the file
# (docs/TOOLING.md §10). A local run caught exactly this on 2026-10-03.
EXPECTED = {
    "swiftUIControl":       (0.10, 0.24, 0.80, 0.10),
    "swiftUIPrivateShield": (0.10, 0.56, 0.80, 0.10),
}
ok = True
for region in regions:
    expected = EXPECTED.get(region["name"])
    if expected is None:
        print(f"unexpected region {region['name']}")
        ok = False
        continue
    if max(abs(a - b) for a, b in zip(region["bodyRect"], expected)) > 1e-6:
        print(f"{region['name']}: {region['bodyRect']} != {list(expected)}")
        ok = False
print("OK" if ok else "MISMATCH")
PY
)"
        SWIFTUI_GEOMETRY_VERDICT="$(printf '%s\n' "$SWIFTUI_GEOMETRY_RESULT" | tail -1)"
        if [[ "$SWIFTUI_GEOMETRY_VERDICT" == "OK" ]]; then
            record PASS "demo and script agree on the SwiftUI page's region geometry" "2 regions matched"
        else
            record FAIL "demo and script agree on the SwiftUI page's region geometry" \
                "$(printf '%s' "$SWIFTUI_GEOMETRY_RESULT" | tr '\n' ' ')"
        fi

        SWIFTUI_SAMPLES="$ARTIFACTS/swiftui-samples.txt"
        SWIFTUI_SAMPLE_ERRORS="$ARTIFACTS/swiftui-sample-errors.txt"
        SWIFTUI_SAMPLER_STATUS=0
        python3 "$SAMPLER" "$SWIFTUI_PNG" "$SWIFTUI_CONTRAST_PNG" "$SWIFTUI_REGIONS_JSON" \
            > "$SWIFTUI_SAMPLES" 2>"$SWIFTUI_SAMPLE_ERRORS" || SWIFTUI_SAMPLER_STATUS=$?

        SWIFTUI_EXPECTED_ROWS=$(( $(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$SWIFTUI_REGIONS_JSON") * 2 ))
        SWIFTUI_ACTUAL_ROWS="$(grep -c '|' "$SWIFTUI_SAMPLES" 2>/dev/null)" || SWIFTUI_ACTUAL_ROWS=0
        [[ -n "$SWIFTUI_ACTUAL_ROWS" ]] || SWIFTUI_ACTUAL_ROWS=0
        if [[ "$SWIFTUI_SAMPLER_STATUS" == "0" && "$SWIFTUI_ACTUAL_ROWS" == "$SWIFTUI_EXPECTED_ROWS" && "$SWIFTUI_EXPECTED_ROWS" -gt 0 ]]; then
            record PASS "the region sampler read both SwiftUI-route PNGs" \
                "$SWIFTUI_ACTUAL_ROWS rows ($(( SWIFTUI_ACTUAL_ROWS / 2 )) regions x 2 images)"
        else
            record FAIL "the region sampler read both SwiftUI-route PNGs" \
                "exit=$SWIFTUI_SAMPLER_STATUS rows=$SWIFTUI_ACTUAL_ROWS expected=$SWIFTUI_EXPECTED_ROWS — $(head -1 "$SWIFTUI_SAMPLE_ERRORS" 2>/dev/null || echo 'no error output')"
        fi

        echo "  app-side read  : $(basename "$SWIFTUI_PNG") (window.drawHierarchy — the no-leak read)"
        echo "  host contrast  : CONTRAST(host-side-bypass) — NOT evidence, discriminator only"
        echo

        # --- The calibration. Without it, "the shielded region is blank" proves nothing. ---
        SWIFTUI_CONTROL_APP="$(classify "$(reading_from "$SWIFTUI_SAMPLES" app-side swiftUIControl mean)")"
        if [[ "$SWIFTUI_CONTROL_APP" == "SENSITIVE" ]]; then
            record PASS "SwiftUI control reads the sensitive colour (calibration)" \
                "app-side=$(reading_from "$SWIFTUI_SAMPLES" app-side swiftUIControl mean)"
        else
            record FAIL "SwiftUI control reads the sensitive colour (calibration)" \
                "app-side=$(reading_from "$SWIFTUI_SAMPLES" app-side swiftUIControl mean) -> $SWIFTUI_CONTROL_APP (the read path cannot image SwiftUI content, so the verdict below is meaningless)"
        fi

        # --- The exclusion. UNREADABLE is a FAILURE, never a pass. ---
        SWIFTUI_APP="$(classify "$(reading_from "$SWIFTUI_SAMPLES" app-side swiftUIPrivateShield mean)")"
        SWIFTUI_HOST="$(classify "$(reading_from "$SWIFTUI_SAMPLES" host-contrast swiftUIPrivateShield mean)")"
        if [[ "$SWIFTUI_APP" == "UNREADABLE" ]]; then
            record FAIL "no-leak: the SwiftUI private route excludes the region from the capture" \
                "app-side reading is UNREADABLE — no pixels were sampled, so this is not evidence of protection"
        elif [[ "$SWIFTUI_APP" == "SENSITIVE" ]]; then
            record FAIL "no-leak: the SwiftUI private route excludes the region from the capture" \
                "app-side=$(reading_from "$SWIFTUI_SAMPLES" app-side swiftUIPrivateShield mean) -> LEAKED"
        else
            record PASS "no-leak: the SwiftUI private route excludes the region from the capture" \
                "app-side=$(reading_from "$SWIFTUI_SAMPLES" app-side swiftUIPrivateShield mean) -> $SWIFTUI_APP (readable, and not the content colour)"
        fi

        # --- The falsification control: a region that never painted would also be blank. ---
        if [[ "$SWIFTUI_HOST" == "SENSITIVE" ]]; then
            record PASS "the SwiftUI route's excluded region is still VISIBLE on the display" \
                "contrast=$SWIFTUI_HOST — exclusion, not a non-painting layer"
        else
            record FAIL "the SwiftUI route's excluded region is still VISIBLE on the display" \
                "contrast=$(reading_from "$SWIFTUI_SAMPLES" host-contrast swiftUIPrivateShield mean) -> $SWIFTUI_HOST — the region did not paint, so the blank capture is unearned"
        fi

        # --- THE F-R2-1 SIGNAL ITSELF: does the shield show content while claiming protection? ---
        #
        # `isProtecting = true` with nothing hosted is the defect: a success claim over a region that
        # was never painted. It is graded as a FAILURE rather than as a finding, because the check
        # above cannot tell "protected" from "blank" on its own — this is the other half of it.
        eval "$(python3 - "$SWIFTUI_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
shields = data.get("shields", {})

def shell(name, value):
    print(f'{name}={json.dumps(str(value))}')

shell("SW_SHIELDS", shields.get("shieldCount", 0))
shell("SW_MODE", shields.get("shieldMode", "missing"))
shell("SW_IS_PROTECTING", shields.get("isProtecting", "missing"))
shell("SW_HOSTS_CONTENT", shields.get("hostsRenderedContent", "missing"))
shell("SW_FAILURE", shields.get("protectionFailure", "missing"))
shell("SW_REQUESTED", shields.get("requestedStrategy", "missing"))
PY
)"

        if [[ "$SW_SHIELDS" == "0" ]]; then
            record FAIL "the SwiftUI route builds a shield to inspect" \
                "no ScreenGuardShieldView was found in the page hierarchy"
        elif [[ "$SW_MODE" == "privateSecureLayer" && "$SW_IS_PROTECTING" == "True" && "$SW_HOSTS_CONTENT" == "True" ]]; then
            record PASS "the shield shows rendered content AND reports the private path engaged" \
                "requested=$SW_REQUESTED mode=$SW_MODE isProtecting=$SW_IS_PROTECTING hostsRenderedContent=$SW_HOSTS_CONTENT"
        else
            record FAIL "the shield shows rendered content AND reports the private path engaged" \
                "requested=$SW_REQUESTED mode=$SW_MODE isProtecting=$SW_IS_PROTECTING hostsRenderedContent=$SW_HOSTS_CONTENT failure=$SW_FAILURE — a claim of protection over content that is not there is the F-R2-1 defect (docs/api-contract.md §13 A3)"
        fi

        echo "        NOTE: this route is PRIVATE API on this strategy — non-contract, fragile across iOS"
        echo "        releases, App Review risk, never a security guarantee (docs/api-contract.md §9). It"
        echo "        is opt-in and off by default in the package."
    fi
fi

# ---------------------------------------------------------------------------------------------
# 4. Watermark — it IS in the capture, and it is NOT a protection
# ---------------------------------------------------------------------------------------------

section "4. Forensic watermark — drawn into the capture, and NOT a protection"

# The check is deliberately two-sided, and it is deliberately NOT a no-leak check:
#
#   * the marked band must NOT be flat  -> the mark really is drawn into the app-side capture;
#   * the matched un-marked band MUST be flat -> the measure has discriminating power, so the first
#     result is not merely "this read path shows noise".
#
# "Present in the capture" is the correct expectation for a watermark and the exact opposite of the
# shield's. A watermark removes no pixels from any capture and prevents nothing; it exists so a leak
# is ATTRIBUTABLE (docs/api-contract.md §3.3). Nothing below may be reported as a no-leak PASS.

WATERMARK_DIR="$ARTIFACTS/watermark"
run_probe watermark
sleep 6
collect "$WATERMARK_DIR" || true

WATERMARK_JSON="$WATERMARK_DIR/watermark-$RUN_ID-final.json"
[[ -f "$WATERMARK_JSON" ]] || WATERMARK_JSON="$WATERMARK_DIR/watermark-$RUN_ID.json"

# bash has no float arithmetic, so the comparisons are delegated.
float_lt() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$1" "$2"; }
float_gt() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) > float(sys.argv[2]) else 1)' "$1" "$2"; }

if [[ ! -f "$WATERMARK_JSON" ]]; then
    record FAIL "the watermark probe wrote its artifact" "expected $WATERMARK_JSON"
else
    eval "$(python3 - "$WATERMARK_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
regions = data.get("regions", {})

def shell(name, value):
    print(f'{name}={json.dumps(str(value))}')

shell("WM_MARKED", regions.get("watermarkMarked", {}).get("deviationFraction", "missing"))
shell("WM_CONTROL", regions.get("watermarkControl", {}).get("deviationFraction", "missing"))
shell("WM_MARKED_SAMPLES", regions.get("watermarkMarked", {}).get("samples", 0))
shell("WM_SECURITY_CONTROL", data.get("isASecurityControl"))
shell("WM_REMOVES_PIXELS", data.get("removesPixelsFromCaptures"))
shell("WM_TILES", data.get("tileCount"))
shell("WM_TILE_SIZE", data.get("tileSize"))
shell("WM_BOUNDS", data.get("bounds"))
PY
)"

    # --- The calibration. Without this band, "the marked band is not flat" proves nothing. ---
    if [[ "$WM_CONTROL" == "missing" ]] || ! float_lt "$WM_CONTROL" 0.01; then
        record FAIL "the un-watermarked control band reads a flat colour (calibration)" \
            "deviationFraction=$WM_CONTROL (expected < 0.01) — the mark/background measure has no discriminating power, so the marked-band result is unearned"
    else
        record PASS "the un-watermarked control band reads a flat colour (calibration)" \
            "deviationFraction=$WM_CONTROL"
    fi

    # --- The mark is IN the capture. This is the honest expectation, not a protection claim. ---
    if [[ "$WM_MARKED" == "missing" ]] || ! float_gt "$WM_MARKED" 0.02; then
        record FAIL "the watermark is drawn into the app-side capture" \
            "deviationFraction=$WM_MARKED (expected > 0.02) — the marked band is flat, so the mark did not draw"
    else
        record PASS "the watermark is drawn into the app-side capture" \
            "deviationFraction=$WM_MARKED of $WM_MARKED_SAMPLES sampled pixels — DETERRENT ONLY, it removes no pixels"
    fi

    # --- Geometry: do the emitted tiles actually cover the watermarked view? ---
#
    # Checked from the artifact's own bounds/tile size/origins, WITHOUT re-running the app's code, so
    # this catches a tiling that leaves part of the view bare.
    GEOMETRY_RESULT="$(python3 - "$WATERMARK_JSON" <<'PY'
import json, math, sys

data = json.load(open(sys.argv[1]))
try:
    tile_w, tile_h = (float(v) for v in data["tileSize"].split(","))
    bx, by, bw, bh = (float(v) for v in data["bounds"].split(","))
    origins = [[float(v) for v in origin.split(",")] for origin in data["tileOrigins"]]
    count = int(data["tileCount"])
except (KeyError, ValueError) as error:
    print(f"unreadable geometry: {error}")
    print("MISMATCH")
    sys.exit(0)

problems = []
if bw <= 0 or bh <= 0:
    problems.append("empty bounds")
if not origins:
    problems.append("no tile origins")
else:
    if len(origins) != count:
        problems.append(f"tileCount {count} != {len(origins)} origins")
    expected = math.ceil(bw / tile_w) * math.ceil(bh / tile_h)
    if count != expected:
        problems.append(f"tileCount {count} != ceil(w/tw)*ceil(h/th) = {expected}")
    if min(o[0] for o in origins) > bx + 1e-6:
        problems.append("left edge is not covered")
    if min(o[1] for o in origins) > by + 1e-6:
        problems.append("top edge is not covered")
    if max(o[0] for o in origins) + tile_w < bx + bw - 1e-6:
        problems.append("right edge is not covered")
    if max(o[1] for o in origins) + tile_h < by + bh - 1e-6:
        problems.append("bottom edge is not covered")

print("; ".join(problems) if problems else "covered")
print("MISMATCH" if problems else "OK")
PY
)"
    GEOMETRY_VERDICT="$(printf '%s\n' "$GEOMETRY_RESULT" | tail -1)"
    GEOMETRY_DETAIL="$(printf '%s\n' "$GEOMETRY_RESULT" | head -1)"
    if [[ "$GEOMETRY_VERDICT" == "OK" ]]; then
        record PASS "the watermark tiles cover the whole watermarked view" \
            "$WM_TILES tiles of $WM_TILE_SIZE over $WM_BOUNDS"
    else
        record FAIL "the watermark tiles cover the whole watermarked view" \
            "$WM_TILES tiles of $WM_TILE_SIZE over $WM_BOUNDS — $GEOMETRY_DETAIL"
    fi

    # --- The honesty flag the demo itself reports. ---
    if [[ "$WM_SECURITY_CONTROL" == "False" && "$WM_REMOVES_PIXELS" == "False" ]]; then
        record PASS "the demo reports the watermark as NOT a security control" \
            "isASecurityControl=False removesPixelsFromCaptures=False"
    else
        record FAIL "the demo reports the watermark as NOT a security control" \
            "isASecurityControl=$WM_SECURITY_CONTROL removesPixelsFromCaptures=$WM_REMOVES_PIXELS"
    fi

    echo "        NO NO-LEAK CLAIM IS MADE HERE. A watermark removes no pixels from any capture: it"
    echo "        makes a leak attributable, and it does not survive cropping, blurring or downscaling"
    echo "        (docs/api-contract.md §3.3)."
fi

# ---------------------------------------------------------------------------------------------
# 5. Detection
# ---------------------------------------------------------------------------------------------

section "5. Detection — capture state, and observer wiring"

DETECT_DIR="$ARTIFACTS/detection"
run_probe detection
sleep 7
collect "$DETECT_DIR" || true

DETECT_JSON="$DETECT_DIR/detection-$RUN_ID.json"
if [[ ! -f "$DETECT_JSON" ]]; then
    record FAIL "the detection probe wrote its artifact" "expected $DETECT_JSON"
else
    eval "$(python3 - "$DETECT_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
events = data.get("events", [])
kinds = [e["kind"] for e in events]

def shell(name, value):
    print(f'{name}={json.dumps(str(value))}')

shell("DET_MONITORING", data.get("isMonitoring"))

# The capture-state signal is graded from the INITIAL reading, taken before this probe posts its
# synthetic screenshot notification. The post sets the monitor's `detectionSource` to
# `screenshotNotification`, so reading the final value here would let the wiring check's own side
# effect stand in for "a capture-state signal arrived" — a different claim, and an accidental pass.
initial_state = data.get("initialCaptureState")
initial_source = data.get("initialDetectionSource")
if initial_state in (None, "null"):
    initial_state = data.get("captureState")
if initial_source in (None, "null"):
    initial_source = data.get("detectionSource")
shell("DET_CAPTURE_STATE", initial_state)
shell("DET_SOURCE", initial_source)
shell("DET_FINAL_SOURCE", data.get("detectionSource"))
shell("DET_EVENT_COUNT", len(events))
shell("DET_SCREENSHOT_EVENTS", sum(1 for k in kinds if k == "screenshotTaken"))
shell("DET_LAST_SCREENSHOT_SET", data.get("lastScreenshotAt") not in (None, "null"))
PY
)"

    # The monitor must actually be running.
    if [[ "$DET_MONITORING" == "True" ]]; then
        record PASS "monitor is running" "isMonitoring=$DET_MONITORING"
    else
        record FAIL "monitor is running" "isMonitoring=$DET_MONITORING"
    fi

    # A concrete capture state must have arrived through the real signal, BEFORE the synthetic post.
    # `unspecified`, or no source at all, would mean the trait registration silently did nothing —
    # which is the failure this catches.
    if [[ "$DET_CAPTURE_STATE" != "unspecified" && "$DET_SOURCE" != "None" && -n "$DET_SOURCE" ]]; then
        record PASS "capture state arrived through a real signal (pre-synthetic)" \
            "state=$DET_CAPTURE_STATE source=$DET_SOURCE"
    else
        record FAIL "capture state arrived through a real signal (pre-synthetic)" \
            "state=$DET_CAPTURE_STATE source=$DET_SOURCE (the trait registration delivered nothing)"
    fi

    # The observer chain, exercised by a DELIBERATELY synthetic post. This is labelled WIRING-ONLY
    # everywhere, because it is not a screenshot and cannot validate one.
    if [[ "$DET_SCREENSHOT_EVENTS" -ge 1 && "$DET_LAST_SCREENSHOT_SET" == "True" ]]; then
        record PASS "screenshot observer wiring delivers an event (WIRING-ONLY, synthetic)" \
            "events=$DET_SCREENSHOT_EVENTS lastScreenshotAt=set"
    else
        record FAIL "screenshot observer wiring delivers an event (WIRING-ONLY, synthetic)" \
            "events=$DET_SCREENSHOT_EVENTS lastScreenshotAt=$DET_LAST_SCREENSHOT_SET"
    fi

    record DEVICE "a REAL screenshot event (side + volume-up)" \
        "not triggerable on Simulator — no volume button (docs/TOOLING.md §2)"

    # The detection path must not have invented a capture event. `UIScreen.isCaptured` stayed false
    # in every t1 run, and no recording can be started on Simulator, so a captureBegan here would be
    # a false positive worth knowing about.
    DET_CAPTURE_EVENTS="$(python3 - "$DETECT_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(sum(1 for e in data.get("events", []) if e["kind"] in ("captureBegan", "captureEnded")))
PY
)"
    if [[ "$DET_CAPTURE_EVENTS" == "0" ]]; then
        record PASS "no capture event was invented on Simulator" "captureBegan/Ended count=0"
    else
        record FINDING "capture events were reported on Simulator" \
            "count=$DET_CAPTURE_EVENTS — unexpected; investigate before trusting any detection verdict"
    fi
fi

# ---------------------------------------------------------------------------------------------
# 6. App-switcher snapshot protection
# ---------------------------------------------------------------------------------------------

section "6. App-switcher snapshot protection — cover installation and synchrony"

SWITCHER_DIR="$ARTIFACTS/appswitcher"
run_probe appSwitcher
sleep 4

# `sim-use button home` is the ONLY reliable way to background an app headlessly
# (docs/TOOLING.md §2). Launching another app via `simctl launch` does not background the app.
#
# NOTE ON WHEN THE ARTIFACT IS WRITTEN. The probe persists its artifact from INSIDE each lifecycle
# notification handler. It has to: verified on this Simulator, the app is suspended ~0.7 s after
# `UIScene.willDeactivateNotification` (`didEnterBackground` at t=4.885 s, one second after
# willDeactivate at t=4.210 s), so a timer-driven write never runs after the Home press and the
# collected file is a stale pre-background snapshot. That produced a false
# "no UIScene.willDeactivate was observed" failure even though the cover had engaged synchronously.
BACKGROUNDED=0
if [[ "$HAVE_SIM_USE" == "1" ]]; then
    if sim-use button home --device "$UDID" > "$ARTIFACTS/sim-use-home.txt" 2>&1; then
        BACKGROUNDED=1
    fi
fi
sleep 4
collect "$SWITCHER_DIR" || true

SWITCHER_JSON="$SWITCHER_DIR/appswitcher-$RUN_ID.json"
[[ -f "$SWITCHER_JSON" ]] || SWITCHER_JSON="$SWITCHER_DIR/appswitcher-$RUN_ID-final.json"
if [[ ! -f "$SWITCHER_JSON" ]]; then
    record FAIL "the app-switcher probe wrote its artifact" "expected $SWITCHER_JSON"
else
    eval "$(python3 - "$SWITCHER_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
transitions = data.get("transitions", [])
names = [t["name"] for t in transitions]
deactivations = [t for t in transitions if "willDeactivate" in t["name"]]

def shell(name, value):
    print(f'{name}={json.dumps(str(value))}')

shell("SW_INSTALLED", data.get("isInstalled"))
shell("SW_TRANSITION_COUNT", len(transitions))
shell("SW_DEACTIVATIONS", len(deactivations))
shell("SW_COVERING_AT_DEACTIVATE", data.get("wasCoveringAtDeactivate"))
shell("SW_SNAPSHOT_VERIFIABLE", data.get("snapshotPixelsVerifiableOnSimulator"))
shell("SW_NAMES", ",".join(names) if names else "none")
PY
)"

    if [[ "$SW_INSTALLED" == "True" ]]; then
        record PASS "cover installs on the key window" "isInstalled=$SW_INSTALLED"
    else
        record FAIL "cover installs on the key window" "isInstalled=$SW_INSTALLED"
    fi

    if [[ "$BACKGROUNDED" != "1" ]]; then
        record SKIP "cover engages synchronously on scene deactivation" \
            "sim-use is unavailable, so the app could not be backgrounded headlessly"
    elif [[ "$SW_DEACTIVATIONS" -lt 1 ]]; then
        record FAIL "cover engages synchronously on scene deactivation" \
            "no UIScene.willDeactivate was observed (transitions: $SW_NAMES)"
    elif [[ "$SW_COVERING_AT_DEACTIVATE" == "True" ]]; then
        # The probe's handler is registered AFTER the shield's, on the same queue, so seeing the
        # cover already engaged here means the shield's handler ran first — synchronously.
        record PASS "cover engages synchronously on scene deactivation" \
            "already covering inside the willDeactivate handler"
    else
        record FAIL "cover engages synchronously on scene deactivation" \
            "the cover was NOT engaged when the willDeactivate handler ran — a deferred cover is a defect (docs/api-contract.md §6.7)"
    fi

    # The pixels. Not decodable, so not a verdict.
    record DEVICE "the app-switcher SNAPSHOT does not contain app content" \
        "snapshot pixels are not decodable on Simulator (docs/TOOLING.md §4)"

    echo "        transitions observed: $SW_NAMES"
fi

# ---------------------------------------------------------------------------------------------
# 7. Recording path
# ---------------------------------------------------------------------------------------------

section "7. Recording / mirroring / AirPlay path"

record DEVICE "no-leak on the recording path, by any technique" \
    "RPScreenRecorder delivers ZERO callbacks on Simulator (docs/TOOLING.md §7.3)"
echo "        Measured: isAvailable=true, completion fired with no error, then 0 video / 0 audio"
echo "        callbacks in 30s. No verdict — NO-LEAK or LEAKED — may be claimed from Simulator data."

# ---------------------------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------------------------

section "Summary"

echo "  PASS   $PASS_COUNT   Simulator-checkable assertions that passed"
echo "  FAIL   $FAIL_COUNT   Simulator-checkable assertions that failed"
echo "  FIND   $FINDING_COUNT   findings reported (do not fail this run)"
echo "  SKIP   $SKIP_COUNT   checks skipped for a stated reason"
echo "  DEVICE $DEVICE_COUNT   checks that REQUIRE A PHYSICAL DEVICE"

echo
echo "  NOT CHECKABLE ON SIMULATOR — these need hardware, and this script does not fake them:"
echo "    * a REAL screenshot event (side + volume-up) — no volume button exists in sim-use"
echo "    * no-leak on the recording / mirroring / AirPlay path — the pipeline delivers no frames"
echo "    * the public preventsCapture layer's capture behaviour — the layer paints nothing at all"
echo "    * the app-switcher SNAPSHOT's pixels — proprietary KTX, not decodable"
echo
echo "    Run:  Scripts/verify_capture.sh --print-device-command"

echo
if [[ "$CONTRAST_OK" == "1" && -f "$CONTRAST_PNG" ]]; then
    echo "  CONTRAST ONLY, never evidence:"
    echo "    $CONTRAST_PNG"
    echo "    Host-side display capture bypasses render-server protection by construction"
    echo "    (docs/TOOLING.md §2). It was used only to tell 'excluded from the capture' apart from"
    echo "    'never painted', and it never produced a no-leak PASS."
else
    echo "  CONTRAST CAPTURE FAILED — there is no host-side discriminator for this run, so the"
    echo "  'excluded vs never painted' comparison above is unavailable. See $CONTRAST_LOG"
fi

echo
echo "  artifacts: $ARTIFACTS"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo
    echo "  RESULT: FAILED — $FAIL_COUNT Simulator-checkable assertion(s) failed."
    exit 1
fi

echo
echo "  RESULT: PASSED — every Simulator-checkable assertion passed."
echo "          The device-required checks above are NOT validated by this run."
exit 0
