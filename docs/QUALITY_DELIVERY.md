# Focused quality delivery — November 12, 2026

The existing SwiftUI/SwiftData architecture, Trips/Reports/Settings navigation, dark/mint visual identity, and explicit Start/Pause/Resume/End workflow are retained. No external dependency, account, analytics, backend, paid service, or automatic drive detection was added. The [audit and proposed sequence](QUALITY_AUDIT.md) preceded implementation.

## Changes by concern

| Files | Result |
| --- | --- |
| `Core/Models.swift`, `Recordkeeping.swift`, `Calculations.swift` | Optional evidence/time-zone/completeness fields, saved effective-dated IRS/employer rate snapshots, precise mileage calculations, full-year odometer summaries and common report rows. |
| `Core/BackupService.swift`, `Persistence/LogStore.swift` | Additive version-3 upgrade, pre-upgrade recovery backup, old backup imports, immutable evidence and merged edit history, reasoned corrections, and retired draft protection. |
| `Services/LocationRecorder.swift` | Start/end times and zones, sampling boundary at each Start/Resume, rejection counters/reasons, preserved endpoints, and explicit signal/recovery warnings. |
| `Features/TripEditor.swift`, `VehiclesView.swift` | Incomplete trip saves, retained original GPS evidence, correction reasons/history, optional expenses/evidence reference, annual reading dates/confirmation/provenance, business-service fields. |
| `Features/TripsView.swift`, `SharedViews.swift` | Compact populated-trip card, meaningful row labels, functional place/purpose search, singular/plural fixes, user-requested cached native endpoint geocoding with offline fallback. |
| `Core/CSVExporter.swift`, `Services/PDFReportExporter.swift` | Shared report calculation, precise CSV with original GPS/corrections/status/expense descriptions/rate periods, native paginated printable PDF with annual vehicle summaries and detailed trips. |
| `Features/RatesView.swift`, `ExperienceViews.swift`, `SettingsView.swift`, release/help/privacy docs | Explicit recalculation semantics, substantiation/eligibility language, commuting and employee reimbursement guidance, updated sharing/privacy disclosure. |
| `Package.swift`, tests, Xcode project | Native macOS SwiftData tests, bundled rate resource for tests, registered native iOS sources, build number 3. |

## Data and calculation semantics

- SwiftData still uses the same `StoredRecord` schema and stable UUIDs. New payload fields are optional. No database reset or destructive transformation is used.
- Backup format 3 reads formats 1–3; numeric timestamps preserve subsecond ordering, and version-1 ISO timestamps remain accepted. Older builds cannot read new format-3 exports. An automatic local recovery file is written before migrating a populated older store; export a separate backup before updating because local copies disappear with app deletion.
- Existing mileage and raw values are retained. New GPS records preserve measured meters, original endpoints, original trip details, timestamps/zones and interruption metadata separately from current edits. Legacy missing evidence remains explicitly unavailable; a full route trace was never stored and is not reconstructed.
- Trip edits use the persisted original evidence. GPS distance/coordinate/date/time changes require a reason and keep source GPS. Backup conflicts in original evidence abort without changing the log. Compatible restores retain history from both copies by stable event ID; repeating a restore does not duplicate trips or retirements.
- Each saved trip captures independent IRS and employer rate selections, including a known missing rate. Rate-table edits/deletions do not change existing snapshots. Refreshing a trip's saved rates or changing date/category/jurisdiction explicitly recalculates it, with edit history. The upgrade captures the existing local table, because prior versions did not store the actual originally applied rate; it cannot recover a rate that was changed before this upgrade.
- Estimates multiply full stored mileage (including round-trip semantics) by the applicable rate using Decimal. Currency is rounded **half-up to cents per trip at the report-row boundary**; displayed totals sum these same amounts. Distance is never rounded for the calculation. CSV uses the round-trippable Double representation; visible row miles may use fewer decimals. Parking/tolls stay separate from mileage estimates.
- The 1.7 mi / $1.31 example is possible with 1.729 stored miles at $0.76; the actual phone data was not inspected, so this is an illustration, not a diagnosis.
- Business records lacking a destination name, purpose, origin, or positive mileage remain saved and visible as incomplete with blank estimates. This also makes previously accepted coordinate-only business destinations visibly incomplete. Completing them restores estimates using their saved rates. This is a visible reporting-completeness change, not an alteration to stored historic distance or evidence.
- Annual totals require confirmed beginning readings, January 1/December 31 dates, an ending reading, and a finished year. Other differences are labeled period mileage. These are user-entered readings, never independently verified totals. Annual business miles use all saved business trips for the full year and selected vehicle, independently of narrower trip filters. Missing readings, incomplete records, unassigned trips, or business mileage exceeding annual mileage are flagged.
- Jurisdiction participates in matching and defaults legacy records to US. Bundled rates and the editing workflow are US-focused; no non-US tax/currency support is claimed. Imports remain GPS/Manual as originally recorded, with merge history; no new inferred capture method is fabricated.

## GPS filtering policy

Only an explicitly active recording receives live location updates. Pause/End stop updates; relaunch offers review/resume and never silently starts tracking. Each Start/Resume resets the accumulator and rejects fixes predating that recording segment, including recent cached fixes from a paused interval.

Accepted fixes require valid coordinates, horizontal accuracy from 0 to 50 m, timestamps no older than 15 seconds and no more than 1 second in the future. Duplicate/out-of-order samples and movement over 70 m/s are rejected without advancing the anchor. A gap over 30 seconds restarts the anchor without bridging distance. Small displacement accumulates until at least max(5 m, 0.75 × the larger anchor/current accuracy). This conservative GPS estimate may omit real distance during weak reception; it neither snaps to roads nor invents travel during missing intervals. Walking, turns, stationary drift, and battery behavior still need field measurements.

Drafts checkpoint only their SwiftData row on delivered callbacks at least 5 seconds after the last checkpoint, plus lifecycle/pause/end actions. A sudden termination can lose the latest uncheckpointed fixes; iOS delivery and termination prevent a guaranteed wall-clock checkpoint interval. Save failures stop recording and keep the newest in-memory draft for retry. GPS points are not written to diagnostic logs.

## Validation and remaining review

Baseline: unsigned iPhone Debug build passed; **10 of 11 tests passed**. `backupRoundtripAndSafeMerge` already failed because encoding silently rewrote unsupported backup versions. This is fixed; unknown versions are rejected before migration.

Final results: **24 tests in 6 suites passed**, and the **unsigned iPhone Debug build passed**. The only build warning is skipped App Intents metadata extraction because the app has no App Intents dependency. Logs are `.build-logs/quality-core-tests.log` and `.build-logs/quality-build.log`. Tests use Xcode's toolchain; an initial invocation through the separate Command Line Tools toolchain was stopped during slow compilation and replaced with the explicit Xcode invocation below. No iOS simulator was used. Commands use one build worker:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path MileLog --jobs 1
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project MileLog.xcodeproj -scheme MileLog -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath DerivedData -jobs 1 CODE_SIGNING_ALLOWED=NO build
```

Coverage includes midyear/prior-year rate boundaries, tiny trips, full precision and row rounding, stable rate snapshots, missing employer/jurisdiction rates, incomplete records, annual completeness, synthetic walking/driving/stationary/bad-time/bad-accuracy/outlier tracks, backup versions/round-trip/merge conflicts, repeated restores, evidence retention, native SwiftData reopen/legacy upgrade, odometer provenance, and CSV escaping/reconciliation. SwiftData tests use isolated in-memory containers and temporary backup directories; they do not modify the owner's installed iPhone log.

Still needed on the physical iPhone: installation/update with a real existing log; permission denial/revocation, Precise Location off, lock-screen/other-app driving, real pause/resume and termination recovery, battery and distance comparison, native geocoding online/offline, VoiceOver/Dynamic Type/layout, CSV opening/share sheet, and PDF pagination/print preview. PDF uses a native renderer and compiles, but its rendered pages have not been visually inspected. Signed archive/App Store validation is not part of these checks. See the [manual checklist](TEST_PERIOD.md).

Destination-entry follow-up: owner screenshots showed coordinate text hiding the Start/Destination placeholders and making it unclear how to complete a trip. `Features/TripEditor.swift` now retains visible field labels, separates coordinate details from editable names, gives location fields distinct keyboard focus, and scopes the inline search button to its own tap target. A **Name destination** popup is directly available in the incomplete banner and updates only the label. No schema, mileage calculation, stored coordinates, or GPS evidence change is involved. The owner clarified that the banner remained; a specific lookup or keyboard failure was not established. Explicit manual entry works independently of lookup. Physical-device popup/keyboard checks are added above. This UI-only follow-up passed its unsigned iPhone build (`.build-logs/destination-editor-build.log`); the core suite was not rerun because its code did not change. No simulator was used.

## Official references

The existing bundled 2026 business rates already contain 72.5¢ through June 30 and 76¢ from July 1. Sources checked: [IRS rate table](https://www.irs.gov/tax-professionals/standard-mileage-rates), [Notice 2026-10](https://www.irs.gov/pub/irs-drop/n-26-10.pdf), and [July adjustment bulletin](https://www.irs.gov/irb/2026-29_irb). No rate data was replaced just because it was not visible in screenshots.

[Publication 463](https://www.irs.gov/publications/p463) informs date/destination/purpose/per-use and annual-mileage recordkeeping, and commuting guidance. Its currently published edition is for 2025; the 2026 notice supplies current mileage/employee treatment. App copy supports records without claiming IRS approval, guaranteed deductibility/accuracy, or personalized tax advice. Employer reimbursement is distinct from a federal deduction.
