# Eave

Eave is a native macOS notch companion for media controls, system information,
clipboard and file shelf tools, notes, terminal sessions, and LLM usage dashboards.

This independent application is based on [k1ngr4m/Atoll](https://github.com/k1ngr4m/Atoll),
branch `codex/dev`, commit `d3ed6303f44fcd380c258dbc4f0c8679607dbc64`,
and the upstream [Atoll project](https://github.com/Ebullioscopic/Atoll) by Ebullioscopic
and its contributors.

## Build

Open `DynamicIsland.xcodeproj` in Xcode and select the `DynamicIsland` scheme.
The source directory and scheme retain their original names; the app and Swift
module are named `Eave` and the build produces `Eave.app`.
Use your own signing team for distribution.

```sh
xcodebuild build -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
python3 tests/test_eave_identity.py
```

Debug uses `com.eave.app.dev`; Release uses `com.eave.app`.
Eave uses its own preferences, Application Support directories, caches, and
keychain service names. Existing Atoll settings and credentials are not migrated.

## Updates and compatibility

Automatic and manual application updates are disabled. Eave has no published
update feed or download URL. Inherited release, mirror, and nightly merge recipes
are saved as `.yml.disabled` files; CI build checks remain active.

`AtollExtensionKit`, its RPC/XPC contracts, and the Spotify OAuth callback remain
compatible with upstream. Do not run both apps' extension services simultaneously:
they retain the same connection endpoints. Pricing data and the extension
marketplace continue to use their upstream providers.

The original icon assets are retained. Links to Atoll identify upstream sources
or services, not an Eave release destination.

## License

Eave retains the GPL v3 license and original copyright notices.
See [LICENSE](LICENSE), [NOTICE](NOTICE), [COPYRIGHT_ASSETS](COPYRIGHT_ASSETS),
and [TRADEMARKS](TRADEMARKS).

## Acknowledgments

Atoll builds upon the work of several open-source projects and draws inspiration from innovative macOS applications:

- [**Boring.Notch**](https://github.com/TheBoredTeam/boring.notch) - foundational codebase that provided the initial media player integration, AirDrop surface implementation, file dock functionality, and calendar event display. Major architectural patterns and notch interaction models were adapted from this project.

- [**Alcove**](https://tryalcove.com) - primary inspiration for the Minimalistic Mode interface design and the conceptual framework for lock screen widget integration that informed Atoll's compact layout strategy.

- [**Stats**](https://github.com/exelban/stats) - source implementation for CPU temperature monitoring via SMC (System Management Controller) access, frequency sampling through IOReport bindings, and per-core CPU utilisation tracking. The system metrics collection architecture derives from Stats project readers.

- [**Open Meteo**](https://open-meteo.com) - weather apis for the lock screen widgets

- [**SkyLightWindow**](https://github.com/Lakr233/SkyLightWindow) - window rendering for Lock Screen Widgets

- [**rtaudio**](https://github.com/ZephyrCodesStuff/rtaudio) - Live music visualizer using C++ was adapted from this project

- [**SwiftTerm**](https://github.com/migueldeicaza/SwiftTerm) - Terminal tab implementation in the standard mode was adapted from this project

- [**DynamicNotch**](https://github.com/jackson-storm/DynamicNotch) - thanks DynamicNotch for letting us use their battery huds

- Wick - Thanks Nate for allowing us to replicate the iOS like Timer design for the Lock Screen Widget

- [**OpenUsage**](https://github.com/robinebers/openusage) - LLM Usage Tracking features

- [**OpenRouter**](https://openrouter.ai) - API for getting automated model pricing

