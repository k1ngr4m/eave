#!/usr/bin/env bash
# Build, relocate and sign the helper before Xcode signs Eave's outer bundle.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTENTS="${1:-${TARGET_BUILD_DIR:-}/${CONTENTS_FOLDER_PATH:-}}"
if [[ "$CONTENTS" != */Contents ]]; then
    echo "Usage: $0 <Eave.app/Contents> (or run as an Xcode build phase)" >&2
    exit 2
fi

bash "$ROOT/scripts/build-mobile-battery-helper.sh"
PACKAGE="$ROOT/.build/mobile-battery/package"
mkdir -p "$CONTENTS/Helpers" "$CONTENTS/Frameworks" "$CONTENTS/Resources"
# Replace our own directory so architecture changes cannot leave stale dylibs.
rm -rf "$CONTENTS/Frameworks/MobileBattery" "$CONTENTS/Resources/MobileBatteryLicenses"
ditto "$PACKAGE/Helpers/EaveMobileBatteryHelper" "$CONTENTS/Helpers/EaveMobileBatteryHelper"
ditto "$PACKAGE/Frameworks/MobileBattery" "$CONTENTS/Frameworks/MobileBattery"
ditto "$PACKAGE/Resources/MobileBatteryLicenses" "$CONTENTS/Resources/MobileBatteryLicenses"

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
SIGNING_ARGS=(--force --sign "$IDENTITY" --options runtime)
if [[ "$IDENTITY" != "-" ]]; then SIGNING_ARGS+=(--timestamp); fi

rewrite_and_sign() {
    local binary="$1"
    if [[ "$binary" == *.dylib* ]]; then
        install_name_tool -id "@rpath/$(basename "$binary")" "$binary"
    fi
    while IFS= read -r dependency; do
        case "$dependency" in
            "$ROOT"/.build/mobile-battery/*)
                install_name_tool -change "$dependency" "@rpath/$(basename "$dependency")" "$binary"
                ;;
        esac
    done < <(otool -L "$binary" | python3 "$ROOT/scripts/otool-dependencies.py" | sort -u)
    codesign "${SIGNING_ARGS[@]}" "$binary"
}

while IFS= read -r -d '' library; do
    rewrite_and_sign "$library"
done < <(find "$CONTENTS/Frameworks/MobileBattery" -maxdepth 1 -type f -name '*.dylib*' -print0)
rewrite_and_sign "$CONTENTS/Helpers/EaveMobileBatteryHelper"
MOBILE_BATTERY_VERIFY_APP=0 bash "$ROOT/scripts/verify-mobile-battery-bundle.sh" "${CONTENTS%/Contents}"
