#!/usr/bin/env bash
# Bundle the on-demand power daemon before Xcode signs Eave.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTENTS="${1:-${TARGET_BUILD_DIR:-}/${CONTENTS_FOLDER_PATH:-}}"
[[ "$CONTENTS" == */Contents ]] || { echo "Expected Eave.app/Contents" >&2; exit 2; }

BINARIES=()
for architecture in ${ARCHS:-arm64 x86_64}; do
    scratch="$ROOT/.build/power-helper/$architecture"
    swift build --package-path "$ROOT/Packages/EaveStatus" --scratch-path "$scratch" \
        --arch "$architecture" -c release --product EavePowerHelper
    binary_directory="$(swift build --package-path "$ROOT/Packages/EaveStatus" --scratch-path "$scratch" \
        --arch "$architecture" -c release --show-bin-path)"
    BINARIES+=("$binary_directory/EavePowerHelper")
done
mkdir -p "$CONTENTS/Helpers" "$CONTENTS/Library/LaunchDaemons"
if [[ ${#BINARIES[@]} -eq 1 ]]; then
    cp "${BINARIES[0]}" "$CONTENTS/Helpers/EavePowerHelper"
else
    lipo -create "${BINARIES[@]}" -output "$CONTENTS/Helpers/EavePowerHelper"
fi
cp "$ROOT/Support/PowerHelper/com.eave.app.PowerHelper.plist" "$CONTENTS/Library/LaunchDaemons/"
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
ARGS=(--force --sign "$IDENTITY" --identifier com.eave.app.PowerHelper --options runtime)
if [[ "$IDENTITY" != "-" ]]; then ARGS+=(--timestamp); fi
codesign "${ARGS[@]}" "$CONTENTS/Helpers/EavePowerHelper"
codesign --verify --strict "$CONTENTS/Helpers/EavePowerHelper"
