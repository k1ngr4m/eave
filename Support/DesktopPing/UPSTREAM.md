# Desktop Ping

Adapted from lolPing at commit `6d67ee19207afe3f00e341097481a3e64be148a3`.
Source: https://github.com/darrenprx/lolPing

The macOS C++ helper and its pure state-machine tests are vendored here. Eave starts
its event tap disabled until native configuration arrives, and changes the permission
error to name Eave. Emote input is always disabled by the host configuration.

`web/overlay/{wheel,pingFx,geometry,pings}.js` are readable JavaScript adaptations of
the matching upstream TypeScript modules. Imports are local ES modules; room tags
and emote/toast styles are removed. Eave owns `main.js`, its WebKit message bridge,
native settings and NSSound playback. Node/Electron are not build or runtime dependencies.

`web/editor` adapts the upstream settings WheelEditor geometry and drag/click
assignment interactions, hosted in Eave’s native settings via WKWebView.

Only the referenced signal textures and WAV sounds are included, without emotes.
Code is MIT; Riot assets are excluded (see LICENSE). The app bundles that notice.

Xcode invokes `scripts/build-desktop-ping.sh` to build for its requested architectures,
embed the web resources, and sign the helper. Run `python3 tests/test_desktop_ping.py`
for helper, host configuration and coordinate regression checks. Real input and
screen sharing must also be checked in the app; simulation does not exercise TCC,
Spaces or the window server.
