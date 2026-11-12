# Manual iPhone checklist

Owner-run checks for the refined build. Use your physical iPhone; no simulators or automated test runs. Create an external backup before installing over an existing log. The new implementation has not been built or runtime-tested by the assistant.

## First pass

- [ ] Open `MileLog.xcodeproj`, select **MileLog** and your connected iPhone, and Run. Keep the preview canvas closed. If Xcode reports an error, share the first error's text and file/line.
- [ ] Confirm existing trips, vehicles, and rates survived the update. On a fresh install, complete Welcome and add a vehicle (or skip it).
- [ ] Add a business trip: **Office → Client**, **10 miles**, purpose **Client meeting**, date **July 1, 2026**. With the bundled rate unchanged, its mileage estimate is **$7.60**. Blank purpose must prevent saving without losing the form.
- [ ] Enter **5 one-way miles** with Round trip enabled. Total distance should be **10 miles**. Try odometers **1,000 → 1,012** and “Use odometer difference”: miles should become **12**, and round-trip doubling should turn off.
- [ ] Add another vehicle and make it default. New manual/GPS trips should use it. Edit a trip, cancel, then reopen and confirm the original remains. Save an edit and inspect its history.
- [ ] Save a quick-add route and purpose. Reuse it; check today's date and cleared expenses/odometers. Remove the shortcut in Settings without removing its saved trips.

## GPS, while safely parked or with a passenger

- [ ] Start a trip; allow While Using and Precise Location. Wait for a fix before moving. Compare a known route against an independent distance reference.
- [ ] Include slow traffic and a brief stationary period. Record reference distance, app distance, and idle drift; repeat on a longer route.
- [ ] Lock the phone during a started trip and use navigation for part of the drive. End while parked and confirm mileage continued. Note battery use on a representative longer drive.
- [ ] Pause while parked, then resume later. The app should warn about the gap and never connect points across the pause.
- [ ] End, add the business purpose, review endpoints/miles, and save. The draft should disappear. Manually correct GPS miles and verify the saved source changes to Manual with the original distance in notes.
- [ ] Deny location or turn off Precise Location: manual entry should work, and GPS should explain the needed setting.
- [ ] Force-close during a disposable recording, then reopen. Expect a recovered draft with a gap warning, not uninterrupted force-quit tracking. Save or discard it. An ended draft must still be reviewable after relaunch.

## Reports and backup

- [ ] Add a Personal trip and a trip in another month. Reports initially include Business only. Change month/year/custom range, category, and vehicle; compare the list of included trips and totals.
- [ ] Export to Files and inspect CSV. Only selected trips should appear; round trips must double once, personal mileage amounts must be zero when included, and parking/tolls must be separate. Try commas/quotes in a location or note.
- [ ] Choose employer rates with no matching table. Expect a missing-rate warning and blank CSV amounts. Add an employer rate and confirm the report and CSV use it.
- [ ] Back up an ended GPS draft **before saving it**, then save it as a trip. Restore that backup twice: the saved recording must not return as another draft or duplicate trip.
- [ ] Back up a draft, discard it, then restore: it must remain discarded. Delete a rate/shortcut and restore an older backup: it must stay deleted unless a newer edit exists.
- [ ] Restore an original version-1 backup. Older drafts may need manual duplicate review; saving should require acknowledgement. Malformed JSON must leave the current log intact.
- [ ] Make a newer trip edit, then restore an older backup. The newer edit should remain. Confirm a local recovery copy exists and can be shared/deleted.

## Final checks

- [ ] Try larger text, VoiceOver, light/dark appearance, search, filters, numeric keyboards, and sharing. Verify actions fit your screen and are easy to identify.
- [ ] Open Help, Privacy, and the support email link. It should address `contact@collectoratlas.app`; nothing should be sent automatically.
- [ ] With disposable records and an external backup, try **Erase all local data**. Confirm the local log and recovery files are gone and Welcome returns. External backup copies should remain where you saved them.
- [ ] Install a later build over the same bundle identifier without deleting the app, then confirm records survive again.

For issues, record steps, expected/actual behavior, iPhone/iOS version, and app version. Redact private destinations. Include reference/app distance and whether the phone was locked or navigation was open for GPS issues.
