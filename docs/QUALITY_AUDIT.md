# Focused quality audit — November 12, 2026

Baseline: f9a0449. Clean working tree. Native SwiftUI/Swift 6, iOS 17 minimum, SwiftData rows with Codable payloads; no backend or external package. Explicit user-started Core Location background updates, 5-second callback checkpoints, Haversine segments with an accumulation anchor. Reports filter trips and export CSV; annual vehicle odometers already exist.

Baseline unsigned iPhone Debug build passed (single build worker). Existing core tests: 10 passed, 1 failed. `backupRoundtripAndSafeMerge` exposes the encoder rewriting an unsupported version to version 2. Evidence is in `.build-logs/quality-baseline-{build,tests}.log`. No iOS simulator was used.

Existing: correct 2025/2026 effective-dated rates, independent employer rates, trip history, validation, annual odometers, search, filtered CSV, backups, recovery markers, privacy/help, three tabs and mint/dark design.

Gaps: three-decimal form parsing can discard stored precision; original GPS evidence is not separately immutable; trip start/end time zones and timestamps are incomplete; coordinates alone can pass business destination validation; incomplete entries cannot be saved intentionally; rate edits recalculate historical amounts; annual readings lack dates/confirmation/edit provenance; CSV lacks recording evidence and completeness; no PDF or reverse geocoding; GPS outliers/out-of-order samples can reset the reference point.

The reported 1.7 mi / $1.31 screenshot is not evidence of a rate error. For example, 1.729 × $0.76 = $1.31404, displayed as 1.7 mi and $1.31. The actual phone record was not available in this audit.

Implementation sequence:
1. Core/Models.swift, Calculations.swift, BackupService.swift, Persistence/LogStore.swift: additive evidence/completeness/rate snapshots, precision, version-3 backup migration and regression coverage.
2. Services/LocationRecorder.swift: timestamps/zones, original evidence, conservative sequence validation and recovery metadata.
3. Features/TripEditor.swift and VehiclesView.swift: correction reasons, incomplete drafts, annual reading dates/completeness and provenance.
4. Features/TripsView.swift and SharedViews.swift: existing visual identity, compact populated-state card, readable labels, singular/plural, opt-in cached endpoint geocoding.
5. Core report/export helpers and native PDF service: shared snapshot, CSV/PDF reconciliation, annual totals, rate periods and missing-data notes.
6. Focused core tests, device build, documentation and physical-iPhone checklist.

Migration is additive inside existing SwiftData rows: old data remains readable, absent evidence stays unknown, no GPS history is invented. Freeze existing trip rate selections using the local pre-upgrade table, identify these as migration snapshots, and make future recalculation explicit. Write a recovery backup before upgrading a populated store. New exports use backup version 3; earlier app versions cannot read version 3. Versions 1 and 2 remain importable.

IRS sources checked: [2026 initial notice](https://www.irs.gov/pub/irs-drop/n-26-10.pdf), [July adjustment](https://www.irs.gov/irb/2026-29_irb), [rates](https://www.irs.gov/tax-professionals/standard-mileage-rates), [Publication 463](https://www.irs.gov/publications/p463). App copy will distinguish expense estimates from eligibility, ordinary commuting, and employer reimbursement.
