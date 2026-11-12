# MileLog — iPhone MVP

Native SwiftUI app for recording mileage, with Swift 6, iOS 17+, SwiftData, CoreLocation and MapKit. No external packages, accounts, analytics, automatic drive detection or cloud sync.

Open **MileLog.xcodeproj** in Xcode. The toolbar scheme must be **MileLog**. Select your personal signing team and connected iPhone, then Run. Start with [the installation guide](docs/IPHONE_SETUP.md) and [the two-week checklist](docs/TEST_PERIOD.md).

## Included

- Manual trips with validation, recent places/purposes, saved purposes, frequent trips and round trips.
- Foreground GPS recording, persistent drafts, interruption flags and manual correction.
- Editable trip log, timestamps and full snapshots for creation, edits and deletion.
- Multiple vehicles, annual odometer readings and business-use percentage.
- Editable IRS estimate and employer rate tables with inclusive date ranges and overlap validation.
- Month/year totals, separate parking/tolls and explicit missing-rate warnings.
- CSV share export and validated JSON backup/merge restore, including feedback and GPS drafts.
- Hidden feedback: long-press **Settings → MileLog · MVP 1.0** for one second.
- SwiftUI previews for every screen and Swift Testing tests for domain calculations/export/backup.

## Data and architecture

`Core/` contains Foundation-only Codable value models and calculations. `Persistence/LogStore.swift` is the main-actor repository/view model shared by the features. Each entity is a separate SwiftData `StoredRecord` row with a stable UUID, kind and Codable payload. This keeps schema changes explicit and allows the exact domain models to be exercised in a standalone Swift package. Trip form state lives in `TripEditorModel`; CoreLocation state lives in `LocationRecorder`.

Explicit saves and rollback ensure the UI only reports a committed change after SwiftData saves it. GPS fixes checkpoint the draft. An unreadable store produces an error screen; the app never deletes or silently replaces it. JSON format version 1 is checked before restore. Backups include soft-deleted trips and their history. This history is a record of edits, not cryptographic proof against tampering.

Restore merges by stable record ID, retaining the newest `updatedAt`. It does not roll back newer edits or resurrect a more recently deleted trip. Unknown formats, invalid records, duplicate IDs, missing vehicle references and overlapping merged rates reject the entire restore. A JSON recovery copy is created in Documents before a successful merge; share it out through Settings → Local recovery copies. Deleted rates/shortcuts do not have tombstones, so importing an older backup can bring those settings back. A restored completed GPS draft may reappear for review; discard it if its trip is already logged.

Dates are stored as Gregorian civil dates; timestamps retain UTC instants. Currency uses Decimal for calculations with per-trip rounding to cents. CSV Rate is dollars/mile, Amount is mileage reimbursement/estimate only; parking/tolls remain separate. Personal trips are included in CSV with Amount 0, and excluded from totals. A missing rate produces blank CSV rate/amount fields and a warning in Totals. Text cells beginning with spreadsheet formula characters receive a leading apostrophe.

## GPS behavior

Grant **While Using the App**, ideally with Precise Location enabled. Record with MileLog open. Recording keeps the display awake; switching apps, locking the phone or receiving an interruption pauses recording. Resume explicitly after returning. The recorder does not connect points across a pause or implausible jump; gaps require review. Accuracy filtering may undercount under poor reception, on curves, or at low speed. Confirm the distance against your vehicle while evaluating the MVP. Accepted fixes are saved locally; the complete route is not retained, only distance and endpoints. You can label the coordinates or use Apple Maps lookup to choose endpoint addresses.

## Rates and recordkeeping

Seeds cover 2025 and 2026, including the July 2026 change. They are data in `Resources/SeedRates.json`, not constants in the calculation logic. No future-year rate is guessed. Verify the table before relying on estimates:

- [IRS standard mileage rates](https://www.irs.gov/tax-professionals/standard-mileage-rates)
- [IRS Notice 2026-10](https://www.irs.gov/pub/irs-drop/n-26-10.pdf)
- [IRS Announcement 2026-11, July adjustment](https://www.irs.gov/irb/2026-29_irb)
- [IRS Publication 463, recordkeeping](https://www.irs.gov/publications/p463)

The app supports keeping records; it does not certify IRS compliance or determine tax eligibility. Employer rules, commuting, substantiation and category eligibility remain circumstances to review. Annual odometer totals must include all driving to make the business-use percentage meaningful.

## Development checks

The standalone package runs the calculation, validation, CSV and backup tests on the Mac without a simulator:

```sh
swift test --package-path MileLog
```

Use Xcode 16+ for Swift 6/Swift Testing (the local build uses Xcode 26.3). If command-line tools are selected instead of Xcode, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Unsigned device compilation:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project MileLog.xcodeproj -scheme MileLog \
  -destination 'generic/platform=iOS' -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

A signed install and real-device GPS, permission, sharing and persistence checks must be completed on the iPhone. Future phases wait for feedback from this MVP.
