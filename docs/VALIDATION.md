# MVP validation — November 11, 2026

- **Passed:** unsigned iPhone device build, Xcode 26.3, iPhoneOS 26.2 SDK, deployment target iOS 17.0, Swift 6 language mode.
- **Passed:** 11 Swift Testing tests in three suites on macOS. Coverage includes known distance, stale/poor fixes, impossible motion, stationary drift, inclusive midyear rates, missing rates, employer rates, Decimal rounding, round trips, totals exclusions, yearly odometer denominator, trip validation, CSV escaping/formula protection, JSON round-trip and merge, malformed data and conflicting rates.
- **Passed:** project and Info.plist syntax validation.
- **Not run:** simulator sessions, iPhone installation, UI interaction, GPS field measurements, share-sheet behavior and SwiftData runtime/update retention. Those are covered by the supplied iPhone checklist.

Local evidence is in `.build-logs/device-build.log` and `.build-logs/core-tests-xcode.log` (ignored build artifacts).

The restricted development environment required command-line `-Xfrontend -disable-sandbox` for Swift compiler macro subprocesses, and local SwiftPM cache paths. These are invocation-only options; they are not set in the app project and are not needed for ordinary Xcode use. No signing identity was selected, and no device was modified.

The only final build warning was skipped App Intents metadata extraction, because the MVP has no App Intents dependency.
