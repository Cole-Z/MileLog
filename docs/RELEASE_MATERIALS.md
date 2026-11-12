# MileLog release materials

Prepared for version 1.0, build 2. Draft copy must be reconciled with the owner's iPhone results before submission. Support email: **contact@collectoratlas.app**. No submission, public hosting, distribution signing, or new-build verification has been performed.

## Proposed App Store listing

**Name:** MileLog – Mileage Tracker (subject to App Store Connect availability)

**Subtitle:** Work miles, clearly recorded

**Promotional text:** Keep your work mileage organized. Record a drive, add its purpose, and export the trips you need for your accountant or employer.

**Description:**

MileLog helps independent workers and small-business owners keep a clear record of their driving.

Start a GPS trip while parked and keep recording while your phone is locked or you use navigation. At your destination, review the distance, add a purpose, and save. You can also enter trips manually, reuse a frequent route, or calculate distance from odometer readings.

• Keep business, personal, and other mileage categories organized.
• Manage multiple vehicles and a default vehicle for new trips.
• Review business mileage and estimated mileage deductions.
• Track parking and tolls separately.
• Filter reports by dates, category, and vehicle, then export a CSV.
• Use editable IRS or employer mileage rates.
• Save backups and review the history of trip edits.

No account is required. Your log is stored on your device, with no advertising or analytics SDKs. Optional address lookup uses Apple Maps. You choose when and where to share exports and backups.

MileLog records trips you start; it does not automatically detect drives. GPS reception, pauses, force quit, and system interruptions can leave gaps. Review your mileage and keep external backups. Estimates support recordkeeping and do not determine tax eligibility or actual tax savings.

Support: contact@collectoratlas.app

**Suggested keywords:** mileage,business,1099,contractor,vehicle,trip,logbook,expenses,reimbursement

**Suggested category:** Business (confirm in App Store Connect).

## App Review notes

No sign-in, subscription, or purchase is required. To exercise the main flow without driving: complete Welcome, select Add manually, enter a valid route, positive miles, and a business purpose, and save. Open Reports to choose dates/category/vehicle and export the selected CSV.

Location permission is requested only after Start trip. While Using permission with Precise Location is sufficient. The location background mode supports a user-started trip through screen lock and navigation use; recording stops when paused/ended. There is no automatic drive detection and no Always-location request. Without location access, manual entry remains available.

Privacy policy and Help & support are available in Settings. The app stores its log locally. Optional Apple Maps search sends entered text to Apple; user-requested endpoint address lookup sends recorded endpoint coordinates to Apple's geocoding service. It does not run automatically. CSV/PDF reports and backups use the system share sheet.

## Screenshot capture on the owner's iPhone

Use fictional locations and records. Capture the actual app after checking layout and behavior. Do not use simulator images or mockups as evidence of runtime validation.

1. Trips dashboard with several business trips: “Your work miles, in one place.”
2. Active trip while parked: “Start a trip. Keep your day moving.”
3. Manual trip form with purpose and mileage: “Keep the details that matter.”
4. Filtered report and totals: “Share the right record.”
5. Vehicles/settings: “Your vehicles. Your private log.”

Verify the required screenshot dimensions in App Store Connect for the device classes offered before uploading.

## Remaining launch tasks

- [ ] Complete the manual iPhone checklist and fix any failures. Validate a signed distribution archive; prior prototype build results do not cover build 2.
- [ ] Finish developer enrollment/business setup under the desired seller identity. Confirm the app record, name, bundle identifier, signing, and agreement status.
- [ ] Confirm that the support mailbox is active and monitored.
- [ ] Publish the supplied privacy/support copy at real HTTPS URLs you control. Enter these in App Store Connect; an email address does not replace the required public URLs. No URL has been invented in this project.
- [ ] Reconcile the privacy policy/manifest and App Store privacy answers with the final app, especially any future SDKs, telemetry, or backend. The current source has no tracking SDK, UserDefaults usage, or direct required-reason API calls identified; optional Maps and exports are disclosed.
- [ ] Complete age rating, content rights, pricing/availability, export compliance, and reviewer contact information in App Store Connect.
- [ ] Capture real iPhone screenshots and confirm listing claims match observed behavior.
- [ ] Use TestFlight while still evaluating the POC. Submit a complete release candidate when ready. Approval/public availability is a separate milestone.

Apple's [review guidelines](https://developer.apple.com/app-store/review/guidelines/) cover completeness, privacy-policy links, and TestFlight for beta builds. Check [current submission requirements](https://developer.apple.com/news/upcoming-requirements/) when preparing the actual archive.
