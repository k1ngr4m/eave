# Desktop Ping

Adapted from lolPing at commit `6d67ee19207afe3f00e341097481a3e64be148a3`.
Source: https://github.com/darrenprx/lolPing

The macOS C++ helper and its pure state-machine tests are vendored here. Eave starts
its event tap disabled until native configuration arrives, and changes the permission
error to name Eave. Emote input is opt-in and uses its own trigger; a conflicting ping trigger disables it.

`web/overlay/{wheel,pingFx,geometry,pings}.js` are readable JavaScript adaptations of
the matching upstream TypeScript modules. Imports are local ES modules; room tags
and toast styles are removed. Eave owns `main.js`, its WebKit message bridge,
native settings and NSSound playback. Node/Electron are not build or runtime dependencies.

`web/editor` adapts the upstream settings WheelEditor geometry and drag/click
assignment interactions, hosted in Eave’s native settings via WKWebView.

The 44 emotes listed in upstream `src/shared/emoteCatalog.ts` are included as PNG
icons and animated WebP. Their Ogg audio was converted to PCM WAV for NSSound:
`ffmpeg -i <slug>.ogg -c:a pcm_s16le <slug>.wav`. No conversion tool is needed to build
or run Eave. `web/overlay/emoteFx.js` adapts the local animation lifecycle; imported
images use native ImageIO thumbnails and stay in Application Support, with no network
or room code. Imports are capped at 24, 8 MB per input, and for animations 5 MB,
1024 px per side and 300 frames. Thumbnails are PNG rather than upstream's WebP
because there is no room transfer size constraint.
Code is MIT; Riot assets are excluded (see LICENSE). The app bundles that notice.

Xcode invokes `scripts/build-desktop-ping.sh` to build for its requested architectures,
embed the web resources, and sign the helper. Run `python3 tests/test_desktop_ping.py`
for helper, host configuration and coordinate regression checks. Real input and
screen sharing must also be checked in the app; simulation does not exercise TCC,
Spaces or the window server.
