# Manual iPhone checklist

Owner-run checks for build 3. Use your physical iPhone; no simulators. Native macOS core/SwiftData tests and an unsigned iPhone build were run at your request; these do not replace the physical-device checks below. Create an external backup before installing over an existing log. See [validation details](QUALITY_DELIVERY.md).

## First pass

- [ ] Open `MileLog.xcodeproj`, select **MileLog** and your connected iPhone, and Run. Keep the preview canvas closed. If Xcode reports an error, share the first error's text and file/line.
- [ ] Confirm existing trips, vehicles, and rates survived the update. On a fresh install, complete Welcome and add a vehicle (or skip it).
- [ ] Add a business trip: **Office → Client**, **10 miles**, purpose **Client meeting**, date **July 1, 2026**. With the bundled rate unchanged, its mileage estimate is **$7.60**. Leave purpose blank: saving should retain an incomplete record with a visible warning and blank estimate, then completing it should restore the estimate.
- [ ] Enter **5 one-way miles** with Round trip enabled. Total distance should be **10 miles**. Try odometers **1,000 → 1,012** and “Use odometer difference”: miles should become **12**, and round-trip doubling should turn off.
- [ ] Add another vehicle and make it default. New manual/GPS trips should use it. Edit a trip, cancel, then reopen and confirm the original remains. Save an edit and inspect its history.
- [ ] Save a quick-add route and purpose. Reuse it; check today's date, Manual source, and cleared expenses/odometers/timestamps/evidence references. Remove the shortcut in Settings without removing its saved trips.
- [ ] Enter 1.729 miles for November 2026: the row may show 1.7 mi while the estimate shows $1.31. Edit only its purpose, then export; stored mileage must still be 1.729. Compare June 30 ($0.725/mi), July 1 ($0.76/mi), and 2025 ($0.70/mi). Change a rate: saved estimates must stay unchanged until explicit trip refresh or a trip-date/category change.
- [ ] In Vehicles → Annual odometers, enter dated readings for a completed year, confirm the beginning reading and full-year coverage, and save the vehicle. A partial/unconfirmed year must have no annual total. Correct a reading with a reason and inspect the previous readings/history. Add an optional business-service date/reading.

## GPS, while safely parked or with a passenger

- [ ] Start a trip; allow While Using and Precise Location. Wait for a fix before moving. Compare a known route against an independent distance reference.
- [ ] Include slow traffic and a brief stationary period. Record reference distance, app distance, and idle drift; repeat on a longer route.
- [ ] Lock the phone during a started trip and use navigation for part of the drive. End while parked and confirm mileage continued. Note battery use on a representative longer drive.
- [ ] Pause while parked, then resume later. The app should warn about the gap and never connect points across the pause.
- [ ] End, name the business destination, add its purpose, and save. The draft should disappear. Correct GPS miles with a reason: source must remain GPS, original meters/endpoints/times must remain unchanged, and the correction must appear in history and exports.
- [ ] Tap endpoint address lookup while online; labels should update without changing coordinates. Try offline and type labels instead. No lookup should occur until tapped.
- [ ] Deny location or turn off Precise Location: manual entry should work, and GPS should explain the needed setting.
- [ ] Force-close during a disposable recording, then reopen. Expect a recovered draft with a gap warning, not uninterrupted force-quit tracking. Save or discard it. An ended draft must still be reviewable after relaunch.

## Reports and backup

- [ ] Add a Personal trip and a trip in another month. Reports initially include Business only. Change month/year/custom range, category, and vehicle; compare the list of included trips and totals.
- [ ] Export to Files and inspect CSV. Only selected trips should appear; round trips must double once, complete personal mileage amounts must be zero when included, and parking/tolls must be separate. Try commas, quotes, and newlines in notes. Confirm incomplete trips remain present, amounts sum to the preview, and original/adjusted GPS distance, time zones, and rate periods are included.
- [ ] Share a PDF with several pages and long notes/addresses. Check text wrapping, page breaks, annual vehicle summaries, missing-data warnings, selected rate periods, and totals against CSV. Review it in Files and the print preview.
- [ ] Choose employer rates with no matching table. Expect a missing-rate warning and blank export amounts. Add an employer rate, explicitly refresh the saved trip's rates, and confirm Reports/CSV/PDF use the employer amount independently of IRS estimates.
- [ ] Back up an ended GPS draft **before saving it**, then save it as a trip. Restore that backup twice: the saved recording must not return as another draft or duplicate trip.
- [ ] Back up a draft, discard it, then restore: it must remain discarded. Delete a rate/shortcut and restore an older backup: it must stay deleted unless a newer edit exists.
- [ ] Restore an original version-1 backup. Older drafts may need manual duplicate review; saving should require acknowledgement. Malformed JSON must leave the current log intact.
- [ ] Make a newer trip edit, then restore an older backup. The newer edit should remain. Confirm a local recovery copy exists and can be shared/deleted.

## Final checks

- [ ] Try the largest Dynamic Type sizes, VoiceOver, appearance settings, search by purpose/place, filters, numeric keyboards, and sharing. Verify safe tap targets and that annual/correction sections remain readable. A single filtered result must say “1 trip” and “Export 1 trip as CSV.”
- [ ] Open Help, Privacy, and the support email link. It should address `contact@collectoratlas.app`; nothing should be sent automatically.
- [ ] With disposable records and an external backup, try **Erase all local data**. Confirm the local log and recovery files are gone and Welcome returns. External backup copies should remain where you saved them.
- [ ] Install a later build over the same bundle identifier without deleting the app, then confirm records survive again.

For issues, record steps, expected/actual behavior, iPhone/iOS version, and app version. Redact private destinations. Include reference/app distance and whether the phone was locked or navigation was open for GPS issues.
