# Second-pass delivery

The audit and ordered plan were committed before implementation in [SECOND_PASS_AUDIT.md](SECOND_PASS_AUDIT.md). Existing three-tab navigation, colors, categories, evidence, saved rates, rounding, odometers, backups, and GPS distance rules remain intact.

## Changes

- Static native launch storyboard with the MileLog wordmark, car and mint route. Background database opening, decoding, existing migration and recovery checks. Loading animation/status appears only when work lasts beyond 250 ms; readiness never waits for branding. Retry retains original storage. Reduce Motion and inactive scenes stop animation; VoiceOver receives genuine stage announcements. Foreground resumes do not reopen the log or request location.
- Advanced GPS evidence, corrections, rates, times, odometers, expenses and notes are collapsible. A missing correction reason still prevents changing original GPS measurements. New recordings show their original evidence before the first save.
- Needs review filter preserves existing search/date/category/vehicle filters. Reports link directly to editable incomplete trips. Saved-trip confirmation, destination-first titles and pluralization remain native and accessible.
- Initial and subsequent GPS silence show recovery feedback. Late errors after Pause/End are ignored. Existing callback checkpoints, conservative distance accumulation, parked-use controls and explicit recovery remain.
- CSV appends annual readings/dates/completeness and original recorded miles; earlier column positions are preserved. PDF adds annual odometers and precise original/current endpoint coordinates. Share cancellation is normal; failures surface a retry message and retain the file.

## Files and compatibility

Startup: `App/MileLogApp.swift`, `Persistence/LogStore.swift`, new `LogLoader.swift` and `StartupController.swift`, `Resources/Info.plist`, new `LaunchScreen.storyboard`. UI/feedback: `Features/TripEditor.swift`, `TripsView.swift`, `SharedViews.swift`, `SettingsView.swift`, `Services/LocationRecorder.swift`. Reports: `Core/Recordkeeping.swift`, `CSVExporter.swift`, `Services/PDFReportExporter.swift`. Validation: `Package.swift`, Xcode project/scheme, `Tests/MileLogCoreTests/QualityTests.swift`, new `StartupTests.swift`, native iOS and UI test files.

No new schema or backup version. SwiftData contexts are executor-confined; only the container and Sendable value snapshot cross from background loading to the UI. Version-3 migration still writes a recovery backup first. Unknown future settings and corrupt payloads fail safely before migration; no reset is used. Rollback to the previous version-3 app remains compatible. Pre-version-3 builds still cannot import version-3 backups. Local backups disappear if the app is deleted; retain an external copy.

## Validation

Baseline: 24 core tests passed and simulator build passed. Final core suite: 32 tests passed, including 1,000-trip reopen, background context handoff and subsequent writes, migration, corruption/future-version rejection, evidence retention, backup round trips, published bundled rate boundaries, and CSV totals/annual warnings.

Native tests cover rendered multi-page PDF completeness/totals/coordinates, precise editor saves, share cancellation/error/file integrity, no startup permission request, reduced accuracy, and Pause/End checkpoint safety. All 5 native iOS tests passed; the unsigned iPhone Debug build passed. UI automation verified incomplete save, Needs review filtering and opening the editor from Reports. Its mileage-field query failed because the accessible label was duplicated by LabeledContent. The label was corrected and a stable field identifier added. The final UI rerun was stopped at the owner’s request; report repair completion, UI share-sheet cancellation and relaunch are not claimed as passing end-to-end checks. See `.build-logs/second-pass-final-native-tests.log` and `.build-logs/second-pass-ui-final.log`. PDF first/last pages were visually inspected; all 30 record IDs and the long note's final marker are present. PDFKit separates underscore glyphs during text extraction; the test normalizes those separators rather than changing the report. The UI query and redundant mileage accessibility label were corrected. No missing records were found.

Commands:

```sh
xcrun swift test --package-path MileLog --jobs 1
xcodebuild -project MileLog.xcodeproj -scheme MileLog -destination 'platform=iOS Simulator,id=11F85DFC-B5EE-476C-AB4F-53910FE30370' -jobs 1 -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
xcodebuild -project MileLog.xcodeproj -scheme MileLog -destination 'generic/platform=iOS' -jobs 1 CODE_SIGNING_ALLOWED=NO build
```

## Physical iPhone acceptance checklist

1. Export a backup, then update an existing installation. Compare trip counts, GPS originals, timestamps/zones, correction histories, vehicle odometers and saved rates. Also test a fresh installation and a large restored log.
2. Cold launch in airplane mode, then background/foreground repeatedly. Confirm immediate availability when ready, no repeated splash or permission prompt, and a usable retry state if protected storage is unavailable.
3. While parked, Start with denied permission and Precise Location off; verify the explanation and manual entry. With permission, record through lock screen, navigation, a phone call and transient signal loss. Compare against an odometer; verify gaps are marked and never bridged with invented mileage.
4. Pause, move, Resume and End. Force-quit/relaunch a separate test recording and review the checkpoint. iOS cannot guarantee continued tracking after termination or the last uncheckpointed fixes; delivery is not a guaranteed five-second wall-clock schedule.
5. Save an incomplete trip, repair it from both Trips and Reports, and correct a GPS measurement with a reason. Confirm original evidence/history are unchanged.
6. Open shared CSV in Numbers and PDF in Files/Print; inspect all pages, totals, Unicode/long notes, missing purpose/annual warnings, and cancellation. Test an unavailable share destination and retry.
7. Restore old/current backups twice; verify no duplicates or changed originals. Import corrupt JSON and confirm no data changes. Confirm destructive prompts without erasing the production log.
8. Check VoiceOver, largest Dynamic Type, Increase Contrast, Reduce Motion, light/dark mode, keyboard and 44-point controls. Real assistive-technology and physical GPS/battery checks remain required.

## Limits and deferred work

No real driving, phone-call/lock-screen GPS, battery comparison, signed archive, or App Store validation was performed. No indefinite background tracking or IRS certification is claimed. No new analytics, network services, automatic geocoding, account, subscription, route reconstruction or schema expansion was introduced. Eligibility and employer policies remain individual questions. The existing 2025/2026 rates match the [IRS rate table](https://www.irs.gov/tax-professionals/standard-mileage-rates) and [July 2026 announcement](https://www.irs.gov/irb/2026-29_irb); historical snapshots were not replaced.

## Startup measurements and stopping point

Instrumented baseline simulator launches recorded database loads of 32–136 ms and app-initialization-to-root-appearance times of 233–2,024 ms. An observed post-change launch recorded 178 ms loading and 925 ms to root appearance. These are Debug simulator observations with different cache/load conditions, not a controlled speedup claim or physical-device cold-start result. The planned matched comparison was deferred when the owner requested an end to testing. The shipped local Startup logger supports a later comparison without logging trip data. Background loading is covered by passing tests; pre-main OS launch time is outside these measurements.

Development is complete. Testing was stopped explicitly at the owner’s request to conserve remaining usage. Remaining manual/device checks and the incomplete UI rerun are listed above; no further tests or benchmarks were started after that request.
