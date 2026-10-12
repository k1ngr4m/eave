#!/usr/bin/env bash
# Explicit local preview shortcut. Only a signed bundle with the exact pinned
# dependency manifest is accepted; release builds keep using source builds.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
BUNDLE="${MOBILE_BATTERY_LIBRARY_BUNDLE:?set the signed dependency bundle path}"
MANIFEST="$ROOT/Support/mobile-battery-dependencies.json"
LIBRARIES="$BUNDLE/Contents/Frameworks/MobileBattery"
NOTICES="$BUNDLE/Contents/Resources/MobileBatteryLicenses"
PACKAGE="$ROOT/.build/mobile-battery/package"
codesign --verify --deep --strict "$BUNDLE"
python3 - "$MANIFEST" "$NOTICES/dependencies.json" <<'PY'
import json, sys
if json.load(open(sys.argv[1])) != json.load(open(sys.argv[2])):
    raise SystemExit("Dependency bundle does not match the pinned source manifest")
PY
if [[ "${UNIVERSAL_BUILD:-0}" == "1" ]]; then
    ARCHES=(arm64 x86_64)
elif [[ -n "${ARCHS:-}" ]]; then
    read -r -a ARCHES <<< "$ARCHS"
else
    ARCHES=("$(uname -m)")
fi
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if (( ${SDK_VERSION%%.*} < 13 )); then
    echo "Error: helper requires macOS SDK 13 or newer." >&2
    exit 2
fi

# Headers are a build input only. Linking below names only the verified bundled
# libraries, never the Homebrew libraries, whose deployment floor may be newer.
HEADER_FLAGS="$(pkg-config --cflags-only-I libimobiledevice-1.0 libusbmuxd-2.0 libplist-2.0)"
rm -rf "$PACKAGE"
mkdir -p "$PACKAGE/Helpers" "$PACKAGE/Frameworks/MobileBattery" "$PACKAGE/Resources/MobileBatteryLicenses"
while IFS= read -r -d '' library; do
    bash "$ROOT/scripts/verify-platform-version.sh" "$library" 13.0 13
    codesign --verify --strict "$library"
    for arch in "${ARCHES[@]}"; do lipo "$library" -verify_arch "$arch"; done
    if [[ "${#ARCHES[@]}" -eq 1 && "$(lipo -archs "$library")" != "${ARCHES[0]}" ]]; then
        lipo "$library" -thin "${ARCHES[0]}" -output "$PACKAGE/Frameworks/MobileBattery/$(basename "$library")"
    else
        cp "$library" "$PACKAGE/Frameworks/MobileBattery/"
    fi
done < <(find "$LIBRARIES" -maxdepth 1 -type f -name '*.dylib*' -print0)
while IFS= read -r -d '' link; do cp -P "$link" "$PACKAGE/Frameworks/MobileBattery/"; done < <(find "$LIBRARIES" -maxdepth 1 -type l -name '*.dylib*' -print0)
ditto "$NOTICES" "$PACKAGE/Resources/MobileBatteryLicenses"
# Keep Eave's relinking instructions alongside the unchanged upstream licenses.
cp "$ROOT/Support/MobileBatteryHelper/ThirdPartyNotices/NOTICE.md" "$PACKAGE/Resources/MobileBatteryLicenses/NOTICE.md"

ARCH_FLAGS=()
for arch in "${ARCHES[@]}"; do ARCH_FLAGS+=(-arch "$arch"); done
xcrun --sdk macosx clang "${ARCH_FLAGS[@]}" -isysroot "$SDK_PATH" \
    -mmacosx-version-min=13.0 -fobjc-arc -O2 $HEADER_FLAGS \
    "$ROOT/Support/MobileBatteryHelper/main.m" "$ROOT/Support/MobileBatteryHelper/NativeBatteryClient.m" \
    -L"$PACKAGE/Frameworks/MobileBattery" -limobiledevice-1.0 -lusbmuxd-2.0 -lplist-2.0 \
    -framework Foundation -framework CoreFoundation \
    -Wl,-rpath,@executable_path/../Frameworks/MobileBattery \
    -Wl,-headerpad_max_install_names -o "$PACKAGE/Helpers/EaveMobileBatteryHelper"
echo "Built Eave helper with verified pinned libraries from $BUNDLE"
