# MileLog review and refinement plan

Reviewed November 12, 2026. This is a proposed implementation scope for a solo builder. The goal is a polished, dependable POC followed by a submission-ready first release; business setup and developer enrollment can proceed separately. Application code has not been changed during this review.

**Testing constraint:** use the owner's physical iPhone for all app runtime and UI testing. Do not boot or use iOS simulators; the development computer cannot handle their resource use. Mac core unit tests and iPhone-targeted build checks remain appropriate. The simulator activity recorded below predates this instruction and has been stopped.

**Recommendation:** retain the native SwiftUI app and local storage. Focus the first release on US mileage recordkeeping: fast manual entry, trips the user explicitly starts and stops, business/personal classification, and useful exports. Improve reliability before adding more features.

**What is already useful**

The project has manual trips, multiple vehicles, reusable purposes and routes, round trips, date-dependent rates, parking/tolls, CSV export, JSON backup/merge, and trip edit history. Calculation code is separate from UI, currency calculations use Decimal, exports escape spreadsheet formulas, and saves use rollback on failure. There are no third-party packages or account/backend dependencies. These are good foundations for a solo-maintained app.

**Findings, in priority order**

| Priority | Finding and evidence | Impact and proposed change |
| --- | --- | --- |
| High — recording | [MileLogApp.swift](../MileLog/App/MileLogApp.swift), lines 35–36, pauses recording whenever the scene is not active. [LocationRecorder.swift](../MileLog/Services/LocationRecorder.swift), line 23, disables background location. | Locking the phone or switching to navigation stops mileage capture. This is documented current behavior, but a poor fit for the target users. Support continuous recording for explicitly started trips, with visible state, recovery, and appropriate location permission explanations. |
| High — accuracy | [Calculations.swift](../MileLog/Core/Calculations.swift), lines 14–19, drops each segment smaller than half the reported accuracy; [LocationRecorder.swift](../MileLog/Services/LocationRecorder.swift), lines 107–111, advances the reference point even for discarded movement. | Repeated small movements can be lost indefinitely. Revise filtering to distinguish accumulated movement from stationary drift, and test stop-and-go routes as well as stationary noise. Synthetic checks are not a substitute for road measurements. |
| High — restore correctness | [LogStore.swift](../MileLog/Persistence/LogStore.swift), line 69, removes a saved draft; [BackupService.swift](../MileLog/Core/BackupService.swift), line 49, merges drafts without a record that they were consumed. | Restoring a backup made before a GPS draft was saved can bring that draft back alongside its completed trip. Saving it again creates a duplicate. Preserve a stable draft-to-trip relationship or a consumed/discarded marker and test repeat restores. The README already acknowledges this limitation. |
| High — submission | [project.pbxproj](../MileLog.xcodeproj/project.pbxproj) contains no app icon resource. [SettingsView.swift](../MileLog/Features/SettingsView.swift), lines 33–37, has privacy explanatory text but no privacy-policy link. | Prepare the app icon and an accessible policy/support destination before submission. Apple's guideline 5.1.1 requires a policy link both inside the app and in App Store Connect. A plain privacy paragraph is insufficient. |
| Medium — scale and battery | [LogStore.swift](../MileLog/Persistence/LogStore.swift), lines 44–59 and 81–82, encodes all records and fetches all stored rows for each draft save. GPS invokes this on the main actor. | Work grows with the entire log on each location callback. Save only changed records and checkpoint recording at a deliberate cadence with an explicit recovery-loss bound. Measure with a representative large log before claiming a performance problem is resolved. |
| Medium — everyday usability | [TripsView.swift](../MileLog/Features/TripsView.swift) exposes a GPS card and a flat trip list. Vehicle setup is under Settings; [TripEditor.swift](../MileLog/Features/TripEditor.swift) shows a long form. | Add lightweight onboarding, an obvious manual-entry action, a default vehicle, useful trip summaries, search/filtering, and optional-detail sections that stay collapsed until needed. |
| Medium — reporting | [TripsView.swift](../MileLog/Features/TripsView.swift), lines 79–94, only summarizes this month/year. [SettingsView.swift](../MileLog/Features/SettingsView.swift), lines 22–26, exports all saved trips, including personal trips. Employer-rate switches are independent in the two screens. | Use a shared report selection for date range, vehicle, category, and rate basis. Preview the exact scope and totals before exporting. Default business reports to business trips, with an explicit option to include other categories. |
| Medium — updates | [LogStore.swift](../MileLog/Persistence/LogStore.swift), lines 36–40, seeds rates only when the store is empty. Stored models use Codable without an explicit upgrade pipeline. | Future bundled rate changes will not reach existing installations automatically. Introduce versioned, non-destructive upgrades that preserve user edits and read old stores/backups. Test upgrading a populated installation. |
| Medium — verification | [CoreTests.swift](../MileLog/Tests/MileLogCoreTests/CoreTests.swift) tests Foundation-only logic. The app scheme contains no explicit app/UI test target. | Add focused tests for recording transitions, SwiftData persistence/reopen, restore, and the main create/edit/export flow. Complete physical-iPhone checks before calling tracking ready. |
| Medium — development recovery | The workspace contains a `.gitignore` but is not a Git repository. | Establish a local baseline and small reviewable commits at the start of implementation. A private remote backup can be chosen separately. |

**Proposed first-release experience**

Keep three tabs and make each useful:

- **Trips:** month-to-date business miles and estimated mileage deduction, prominent Start trip and Add manually actions, an active-trip card, and trips grouped by day. Filter by date, vehicle, and business/personal category; search destinations and purposes.
- **Reports:** select a month, year, or custom range; choose vehicles/categories and IRS versus employer rates; review the totals and missing-rate warnings; export the selected CSV. Display mileage amounts separately from parking and tolls. Use “estimated deduction,” not “tax savings.”
- **Settings:** vehicles/defaults, rates, backups and restore, privacy, support, app version, and clearly explained data management. Make feedback discoverable instead of hiding it behind a long press.

First use should explain local storage, help add a vehicle, and lead directly to the first trip. Ask for location when Start trip is selected. Manual entry remains available when location is denied. A trip form should prioritize date, route, miles, purpose, and vehicle, with odometers, expenses, notes, and shortcut creation tucked into optional sections.

**Implementation sequence**

1. **Make the mileage record trustworthy.** Establish version control; fix recording lifecycle, movement filtering, draft duplication on restore, and per-update persistence cost. Add versioned data/rate upgrades before introducing new required model fields. Preserve existing trips and backup compatibility. Deliver an installable build with explicit waiting, recording, paused/interrupted, and ready-to-review states.
2. **Refine the main workflow.** Add onboarding/default vehicle, improve the Trips screen and trip form, and turn Totals into Reports with shared filtering/export behavior. Keep native controls, accessible text sizes, clear empty states, and consistent spacing/colors. Deliver a complete first-trip-to-export walkthrough.
3. **Prepare the release materials.** Add icon assets, visible support/privacy access, accurate location descriptions, release versioning, screenshots, store copy, and reviewer instructions. Audit actual required-reason API usage and include a privacy manifest where required. Prepare privacy answers from the final data flows, including optional Apple Maps lookup and user-directed exports. Owner identity, support contact, and final hosted URLs need the owner's input before publication.
4. **Validate the release candidate.** Run core and app integration checks; test on a physical iPhone; archive and validate distribution when developer enrollment is available. Use TestFlight for unfinished/beta builds. Treat submission and public availability as separate milestones.

The recommended tracking scope is user-started recording that continues while locked or using Maps. Automatic drive detection, cloud sync, accounts, subscriptions, receipt OCR, and integrations should follow evidence from real use. A PDF report can follow the first reliable filtered CSV report. No backend is needed for this proposed POC.

**Acceptance checks**

- A new user can add a vehicle and save a valid business trip without instructions; validation explains what is missing without losing input.
- Recording survives screen lock and navigation use during a started trip. Denied/reduced location permission and weak signal produce clear guidance. Force termination leaves a recoverable draft and an explicit gap indication; uninterrupted capture after force quit is not promised.
- Known urban, highway, and stop-and-go routes are compared against an independent distance reference. Set an agreed accuracy tolerance and measure stationary drift and battery use before release.
- A saved trip survives relaunch and an app update. Canceling an edit leaves the original intact. No database reset is used as migration recovery.
- Restoring old or repeated backups does not duplicate completed trips or resurrect consumed drafts. Malformed imports fail without changing the log, and a recovery copy remains available.
- Report filters and CSV rows agree exactly; personal trips are excluded from a business-only export; year boundaries and missing rates behave correctly.
- Small-screen layouts, light/dark appearance, Dynamic Type, VoiceOver labels, keyboard dismissal, and sharing to Files are checked.
- A distribution archive has the correct icon/version, valid signing, complete store metadata, and functioning policy/support destinations before submission.

**Validation from this review**

- Passed: all 11 Swift Testing tests in three suites using Xcode 26.3.
- Passed: `plutil` validation of Info.plist and the Xcode project.
- Passed: a fresh unsigned Release build for generic iOS and a fresh Debug build for generic iOS Simulator. The only reported build warning was skipped App Intents metadata extraction because the app has no App Intents dependency. Compilation does not establish distribution signing or App Store acceptance.
- Reproduced: ten consecutive approximately 5.56-meter segments, five seconds apart with reported accuracy of 20 meters, total 55.60 meters of synthetic movement but count as zero. This exercises the same per-segment calculation used by the recorder; actual driving accuracy still requires device measurements.
- Reproduced: merging a backup containing an ended GPS draft into a current log containing its completed trip leaves both one trip and one restored draft. The current model cannot identify that the draft has already been consumed.
- Evidence: `.build-logs/review-release-build.log`, `.build-logs/review-simulator-build.log`, and `.build-logs/review-probes.txt`. The temporary probe uses the existing core sources without modifying them.
- Incomplete: simulator installation/launch was stopped without establishing a UI smoke-test result; the simulator was shut down successfully. This occurred before the owner specified iPhone-only runtime testing. Do not retry it. The successful earlier simulator compilation should not be read as a successful interactive test.
- Physical-device GPS, battery, full UI interaction, distribution signing, and App Store Connect validation have not been verified in this review.

**Official references checked**

The bundled July–December 2026 rates match [IRS Announcement 2026-11](https://www.irs.gov/irb/2026-29_irb): 76 cents for business, 23.5 cents for medical/moving, and 14 cents for charitable mileage. This verifies the rate data, not an individual trip's eligibility.

Apple documents the required configuration for [background location updates](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates). Apple's [review guidelines](https://developer.apple.com/app-store/review/guidelines/) cover app completeness, TestFlight for betas, and in-app/store privacy-policy links. [App icon setup](https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon) belongs in the Xcode release resources. Current [submission requirements](https://developer.apple.com/news/upcoming-requirements/) require Xcode 26 or later with the iOS 26 SDK or later; the installed Xcode 26.3 meets that toolchain minimum.
