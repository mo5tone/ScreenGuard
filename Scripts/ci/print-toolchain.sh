#!/bin/sh
# =============================================================================================
# Scripts/ci/print-toolchain.sh — record exactly which toolchain this run used.
#
# WHY THIS IS A STEP AND NOT DECORATION
#   The CI runner and a developer machine do NOT run the same Xcode. macos-26 ships Xcode 26.6 and
#   the iOS 26.2 SDK; this project is developed locally on Xcode 27.0 / iPhoneSimulator27.0.sdk.
#   A source that compiles cleanly on one can produce diagnostics on the other, so every CI result
#   has to be attributable to a specific SDK — otherwise "it passed in CI" and "it passed here" are
#   two unlabelled numbers. This step prints the selected Xcode, the Simulator SDK, the Simulator
#   runtimes, the mise version and every pinned tool (with the path of the binary that will actually
#   be executed), and the workflow appends it to the job summary.
#
#   It also FAILS when a pinned tool is missing from PATH, or when the binary that would run comes
#   from a global/Homebrew install rather than from mise: an unpinned tool is not a gate.
#
# Usage: Scripts/ci/print-toolchain.sh
# Exit codes: 0 = every pinned tool is present and mise-managed, 1 = it is not.
# =============================================================================================
set -eu

TOOLS="swiftlint swiftformat xcodegen actionlint shellcheck git-cliff"

fail() {
    printf '\nFAIL: %s\n' "$1" >&2
    shift
    for detail in "$@"; do
        printf '%s\n' "$detail" >&2
    done
    exit 1
}

# One line, bare version number, whatever shape the tool prints it in ("Version: 2.46.0",
# "git-cliff 2.14.2", plain "0.63.0").
tool_version() {
    case $1 in
        swiftlint)  $1 version ;;
        shellcheck) $1 --version | awk '/^version:/ { print $2; exit }' ;;
        *)          $1 --version 2>/dev/null | head -1 | sed -e "s/^$1[[:space:]]*//" -e 's/^Version:[[:space:]]*//' ;;
    esac
}

echo "== toolchain this run used =="
printf 'utc              : %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf 'machine          : %s %s (%s)\n' "$(uname -s)" "$(uname -r)" "$(uname -m)"
printf 'developer dir    : %s\n' "$(xcode-select -p 2>&1)"
printf 'xcodebuild       : %s\n' "$(xcodebuild -version 2>&1 | tr '\n' ' ')"
if sdk=$(xcrun --sdk iphonesimulator --show-sdk-version 2>&1); then
    printf 'iphonesimulator  : SDK %s (%s)\n' "$sdk" "$(xcrun --sdk iphonesimulator --show-sdk-path 2>&1)"
else
    printf 'iphonesimulator  : SDK version unavailable (%s)\n' "$sdk"
fi
printf 'mise             : %s\n' "$(mise --version 2>&1 | head -1)"
printf 'destination      : %s\n' "${DESTINATION:-<unset>}"

echo
echo "-- pinned tools (mise current) --"
mise current 2>&1 | sed 's/^/   /'

echo
echo "-- the binary that will actually run --"
missing=0
for tool in $TOOLS; do
    if ! path=$(command -v "$tool" 2>/dev/null); then
        printf '   %-12s MISSING from PATH\n' "$tool"
        missing=1
        continue
    fi
    version=$(tool_version "$tool" 2>/dev/null || printf 'unknown')
    printf '   %-12s %-28s %s\n' "$tool" "$version" "$path"
    case $path in
        */homebrew/*|/usr/local/bin/*|$HOME/.local/bin/*)
            printf '\nFAIL: %s resolves to %s\n' "$tool" "$path" >&2
            printf '      that is a global install, not the mise-pinned tool. Prepend the mise shims\n' >&2
            printf '      directory to PATH (mise activation, or mise-action in CI), or remove it.\n' >&2
            exit 1
            ;;
    esac
done
if [ "$missing" -ne 0 ]; then
    fail "a tool pinned in .mise.toml is not on PATH" \
        "  run 'mise install' (locally) or check the mise-action step (CI)" \
        "  pins: .mise.toml [tools]"
fi

echo
echo "== every pinned tool resolved =="
