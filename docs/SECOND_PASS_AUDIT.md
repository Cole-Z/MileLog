# Startup and quality-of-life audit — November 12, 2026

Baseline: `8680aeb`, clean working tree. Inspection covered app lifecycle, SwiftData storage, all core models/calculations, recorder, editor, trip/report/settings views, CSV/PDF, restore/erase, tests, project and launch configuration.

Already implemented: three native tabs; dark/mint styling; compact returning-user recording card; readable destination titles and purpose search; singular/plural helper; saved incomplete trips with blank report estimates; immutable original GPS evidence and correction history; date-specific rate snapshots; independent employer reimbursement; dated annual odometers with provenance; conservative GPS filtering; pause/end and callback/lifecycle checkpoints; explicit recovered-draft review; opt-in Apple endpoint lookup; native CSV/PDF; validated version 1–3 backup imports, conflict handling and destructive confirmations. These will be reused.

Gaps: empty `UILaunchScreen`; synchronous main-actor database opening/decoding/migration; spinner without stage feedback; expanded GPS/rate diagnostics; no Needs review filter or report repair link; no explicit saved-trip confirmation; stale location feedback misses the initial no-fix case; share completion errors are ignored; CSV lacks annual-record warnings; PDF omits raw coordinate evidence. Existing tests do not exercise async startup or rendered PDF output. Real lock-screen/call/force-quit/battery behavior remains unverified.

Ordered plan, recorded before implementation:

1. Baseline build/tests and simulator process-cold launch measurements. Static launch storyboard, background startup storage work, genuine stage reporting, delayed *presentation* of loading feedback (never delayed readiness), retryable errors and local timing instrumentation.
2. Collapse advanced editing; consistent Needs review wording/filter; direct report repair; preserve current filters, completeness rules, categories and compact card.
3. Improve recording/save feedback and share failures; fill export evidence/warning gaps without changing rates, rounding, distance or original records.
4. Regression tests for startup persistence/migration/corruption, evidence and exports; iOS builds and simulator inspection; documented device matrix and limitations.

No schema or backup-version change is planned. SwiftData stays `StoredRecord`; existing version-3 upgrade and pre-upgrade backup remain. Startup contexts must stay on their own executor; only Sendable value snapshots and the ModelContainer may cross to the UI. Errors must never reset storage. Current-version rollback remains compatible; pre-version-3 builds still cannot import version-3 backups. Separate commits will cover audit, startup, UI, export/feedback and validation.

Official sources rechecked: [IRS rate table](https://www.irs.gov/tax-professionals/standard-mileage-rates), [Announcement 2026-11](https://www.irs.gov/irb/2026-29_irb), [Notice 2026-10](https://www.irs.gov/pub/irs-drop/n-26-10.pdf), [Apple launch-screen requirements](https://developer.apple.com/documentation/technotes/tn3208-preparing-your-apps-launch-screen-to-meet-app-store-requirements), [background location](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background). The bundled 2025/2026 rates, including the 2026 July change, already match; no automatic replacement of historical rates is needed. Eligibility remains user-specific, not IRS certification.
