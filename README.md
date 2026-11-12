# MileLog

Native iPhone mileage tracking for independent workers and small businesses. SwiftUI, SwiftData, Core Location, iOS 17+. No account, backend, analytics SDK, or external package is required.

Open **MileLog.xcodeproj**, select the **MileLog** scheme and your connected **physical iPhone**, and Run. Keep the SwiftUI preview canvas closed. See [iPhone setup](docs/IPHONE_SETUP.md) and the [manual checklist](docs/TEST_PERIOD.md).

**Current status:** focused quality improvements are ready for physical-iPhone review. The latest request authorized native macOS unit tests and an unsigned iPhone build; no iOS simulators were used. See [quality audit](docs/QUALITY_AUDIT.md) and [implementation/validation notes](docs/QUALITY_DELIVERY.md). Real-device GPS, accessibility, sharing, and update retention still require the owner's checks.

## Included

- Welcome flow with optional vehicle setup, a default vehicle, and visible privacy information.
- Trips dashboard with business mileage and estimated mileage deduction for the current month.
- User-started GPS recording configured to continue through screen lock and navigation use; explicit pause/end controls, signal warnings, checkpoints, and recovered drafts.
- Manual trip entry, recent places and purposes, round trips, odometer-derived distance, expenses, notes, and reusable routes.
- Searchable trip log grouped by day, with date, category, and vehicle filters.
- Reports for a month, year, custom range, or all dates. CSV and native printable PDF share selected trip rows, rates, and amounts. Business is the default report category.
- Multiple vehicles, dated annual odometer records with correction history, optional business-service readings, editable IRS/employer rates, separate parking/tolls, and missing-rate warnings.
- Original GPS evidence alongside corrections, trip timestamps/time zones, incomplete-record indicators, and explicit rate refresh with saved snapshots.
- Optional native endpoint address lookup, requested by the user, with an editor-session cache and manual/offline fallback.
- Trip history, backup/merge restore, local recovery files, shortcut management, and confirmed local data erasure.
- Original app icon, light/dark accent colors, in-app help/privacy, and support at **contact@collectoratlas.app**.

## Recording and data

Allow **While Using the App** with **Precise Location** for GPS recording. Start and stop while parked. Background recording is enabled only for a trip the user starts. There is no automatic drive detection or Always permission request. Force quit, system termination, poor reception, and explicit pauses can leave gaps; review recovered recordings and correct miles as needed. Physical-iPhone measurement and battery checks remain required.

The recorder retains distance and endpoints, not a full route. A distance anchor accumulates small movements before counting a segment. GPS checkpoints save only the draft row, on callbacks at least five seconds after the prior checkpoint, plus explicit pause/end/background transitions. A sudden termination can lose the last uncheckpointed fixes. Save failures stop recording and retain the current distance in memory for retry.

Records use Codable payloads in stable SwiftData rows. New fields are optional; no SwiftData schema reset is needed. Preferences version 3 tracks this upgrade. Existing rates are never overwritten by bundled rates; new nonconflicting periods can be added. Read failures are surfaced without resetting the database. An automatic local recovery backup precedes upgrading a populated older store; keep an external backup too.

Backup format 3 preserves timestamp precision using seconds since Apple's reference date (2001-01-01 UTC). Versions 1 and 2 remain readable, including ISO-8601 timestamps. Older app versions cannot read format-3 backups. New recordings use a stable trip/draft identity and deletion markers to prevent saved/discarded drafts from returning. Old backups without this identity cannot prove whether a trip was already saved: recovered drafts require an explicit duplicate check before saving. Conflicting original evidence blocks import without changing the log; compatible histories are combined by stable event ID.

Deleted trips remain in edit history/backups. Deleted shortcuts/rates carry markers so older backups do not silently restore them. Restore validates before merging and creates a recovery copy. Local backups and temporary CSV/PDF files are removed by **Erase all local data**; copies exported elsewhere must be managed separately. Backups should be stored outside the app before updates or deletion.

Dates are Gregorian civil dates. Full stored distance is converted to Decimal for estimates; each trip's currency amount is rounded half-up to cents, and summaries sum those same amounts. Changing the rate table does not recalculate saved trips: explicitly refresh a trip's rates or change its date/category. Legacy snapshots preserve the table at upgrade/import, not an unknowable original historic rate. CSV retains Double distance precision, separates expenses, escapes formulas in text, and leaves incomplete/missing-rate amounts blank. Complete personal trips have zero mileage amounts. Annual summaries use full-year business trips and confirmed dated odometers, independently of narrower report filters.

## Release preparation

Use [release materials](docs/RELEASE_MATERIALS.md), [privacy-policy copy](docs/PRIVACY_POLICY.md), and [support-page copy](docs/SUPPORT.md). Public hosting, developer enrollment, signing/archive validation, real iPhone screenshots, and the owner's manual checks remain launch tasks. No website has been published or App Store submission made.

The privacy manifest declares no tracking or developer-collected in-app data and no directly used required-reason APIs. Preferences are stored in SwiftData, not UserDefaults. Optional Apple Maps search, user-requested endpoint geocoding, and user-directed sharing are explained in the policy; recheck disclosures if data flows change.

The original road/M icon can be regenerated with `python3 scripts/render_app_icon.py` using only Python's standard library. Build version is 3; the bundle identifier and signing team are unchanged to preserve an installed log.
