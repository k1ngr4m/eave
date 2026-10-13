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

Release builds use Sparkle to check for Eave updates automatically (opt out in
Settings → About) or with **Check for Updates**. Clicking **Update & Relaunch**
downloads, verifies, installs and relaunches the app. Development builds only
link to the official download. The first update-enabled release must be installed
manually. Until it is published, checking the feed will report a network error.
The feed is the `appcast.xml` asset on the latest non-prerelease GitHub Release.
Only Eave's Ed25519 key can sign its update archives; old Atoll feeds are removed.

`AtollExtensionKit`, its RPC/XPC contracts, and the Spotify OAuth callback remain
compatible with upstream. Do not run both apps' extension services simultaneously:
they retain the same connection endpoints. Pricing data and the extension
marketplace continue to use their upstream providers.

The original icon assets are retained. Links to Atoll identify upstream sources
or services, not an Eave release destination.

## Versions and builds

`VERSION` is the only source of the app version, starting at `0.1.0`. Ordinary
builds never change it. There are two distribution channels: `dev` and `release`.
Both Debug and Release configurations default to `dev`; compiler optimization
does not make a build an official release. The settings badge shows the channel;
click the version row to show its build number.

Every app build in Xcode or `xcodebuild` stamps the final Info.plist before signing,
with the version in both `CFBundleShortVersionString` and `CFBundleVersion`.
The per-channel local counter is stored separately in `EaveBuildNumber`, so a
new version from another machine upgrades correctly even if its counter is lower.
Rebuilding the same version does not trigger an update. Counters start at 1 and persist in
`~/Library/Application Support/Eave/BuildNumbers/`, outside Git and DerivedData.
They are independent per channel and machine, survive clean builds and version
changes, and may have gaps after failed builds. CI runners have their own local
counters; these numbers are not globally unique. `EAVE_BUILD_COUNTER_DIR` can
override the directory for isolated tests.

To prepare an official release, choose its version explicitly:

```sh
python3 scripts/eave_version.py archive 0.1.0
```

This updates `VERSION`, archives with Release optimization and
`EAVE_CHANNEL=release`, and checks the version/channel in the resulting
`build/Eave-0.1.0.xcarchive`. Configure your signing team/certificate in Xcode
before archiving. Downgrades, existing local version tags and existing archives
are rejected. A failed archive leaves the requested version in place so it can
be retried; move any partial archive before retrying.

### Signed local releases

Use Python 3.9+, Xcode, `gh auth login`, your **Developer ID Application**
certificate/private key in Keychain, and notarization credentials stored with
`xcrun notarytool store-credentials Eave-notary` (interactive; never commit secrets).
The Sparkle tools are in Xcode DerivedData under
`SourcePackages/artifacts/sparkle/Sparkle/bin` after package resolution.

The Eave Ed25519 key uses Keychain account `com.eave.app`. Its public key is
committed as `SUPublicEDKey`; the private key must be kept/backed up securely.
On another machine import the existing private key using Sparkle `generate_keys`
following its help; do not generate a replacement for an already published app.

For each release, update `VERSION` and release notes, commit and push the source,
then prepare (this archives for you; do not run `archive` first):

```sh
python3 scripts/eave_release.py prepare 0.1.0 \
  --identity 'Developer ID Application: YOUR NAME (TEAMID)' \
  --team YOURTEAMID \
  --notary-profile Eave-notary \
  --sparkle-bin /absolute/path/to/Sparkle/bin
```

These four options also accept `EAVE_IDENTITY`, `EAVE_TEAM`,
`EAVE_NOTARY_PROFILE`, and `EAVE_SPARKLE_BIN` environment variables.
Preparation requires a clean working tree, verifies credentials and the public key,
archives/exports, notarizes, staples, checks Gatekeeper acceptance, and signs the
final ZIP. Review the app and artifacts in `build/release-0.1.0/`, then:

```sh
python3 scripts/eave_release.py publish 0.1.0 --notes /path/to/release-notes.md
```

Publishing verifies hashes and the source commit on GitHub, creates a draft,
downloads and compares its assets, and only then marks it public/latest. Duplicate
versions (including drafts/tags) and rollback versions are rejected. Failed uploads
leave a draft for inspection; inspect/delete that draft before retrying. Failed
preparation leaves build artifacts for diagnostics; move both the version's archive
and release directory before retrying. No signing credentials are stored in GitHub.

Subsequent fixes can use `0.1.1`, and feature releases `0.2.0`. Development builds
keep the last chosen version until the next official release is prepared.

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

