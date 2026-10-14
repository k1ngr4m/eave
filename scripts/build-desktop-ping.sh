#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/Support/DesktopPing/helper"
WORK="${PING_BUILD_DIR:-$ROOT/.build/desktop-ping}"
mkdir -p "$WORK"
read -r -a PING_ARCHES <<< "${ARCHS:-$(uname -m)}"
PING_FLAGS=(-std=c++20 -mmacosx-version-min=14.6 -Wall -Wextra)
for arch in "${PING_ARCHES[@]}"; do
    PING_FLAGS+=(-arch "$arch")
done
xcrun clang++ "${PING_FLAGS[@]}" -O2 \
    "$SOURCE/src/main_posix.cpp" "$SOURCE/src/hooks_mac.cpp" "$SOURCE/src/macinput.cpp" \
    "$SOURCE/src/simulate.cpp" "$SOURCE/src/commands.cpp" "$SOURCE/src/output.cpp" \
    "$SOURCE/src/json.cpp" "$SOURCE/src/decision.cpp" \
    -framework ApplicationServices -framework CoreFoundation -o "$WORK/EavePingHelper"
if [[ "${1:-}" == "--test" ]]; then
    xcrun clang++ -std=c++20 -O0 "$SOURCE/tests/helper_tests.cpp" \
        "$SOURCE/src/decision.cpp" "$SOURCE/src/commands.cpp" "$SOURCE/src/macinput.cpp" \
        "$SOURCE/src/json.cpp" "$SOURCE/src/output.cpp" -o "$WORK/helper-tests"
    "$WORK/helper-tests"
elif [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
    CONTENTS="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
    mkdir -p "$CONTENTS/Helpers" "$CONTENTS/Resources/DesktopPing"
    cp "$WORK/EavePingHelper" "$CONTENTS/Helpers/EavePingHelper"
    ditto "$ROOT/Support/DesktopPing/web" "$CONTENTS/Resources/DesktopPing"
    cp "$ROOT/Support/DesktopPing/LICENSE" "$CONTENTS/Resources/DesktopPing/LICENSE"
    SIGNING_ARGS=(--force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime)
    if [[ "${EXPANDED_CODE_SIGN_IDENTITY:--}" != "-" ]]; then SIGNING_ARGS+=(--timestamp); fi
    codesign "${SIGNING_ARGS[@]}" "$CONTENTS/Helpers/EavePingHelper"
fi
