# Install on your iPhone

1. Open Xcode once, accept its license and complete any requested component installation. This project requires Xcode 16 or later and an iPhone on iOS 17 or later. Your Xcode version must support the iPhone's installed iOS version.
2. Open `MileLog.xcodeproj` from this folder. Close any older window showing the **MileLogCore** scheme. The project opens the iPhone app; the separate package in `MileLog/Package.swift` is only for Mac unit tests.
3. In **Xcode → Settings → Accounts**, add your Apple Account. A free Personal Team is sufficient for local iPhone testing.
4. Select the blue **MileLog** project in the navigator, then **TARGETS → MileLog → Signing & Capabilities**. Enable **Automatically manage signing** and select your **Personal Team**.
5. The initial bundle identifier is `com.colezill.MileLog`. If Xcode says it is unavailable, choose a unique identifier such as `com.yourname.MileLog`. Once the app contains real data, keep this identifier and signing team unchanged.
6. Connect the unlocked iPhone by cable. Tap **Trust This Computer** on the iPhone and enter its passcode. In Xcode, use **Window → Devices and Simulators → Devices** to check that pairing/device preparation is complete. No simulator installation or testing is needed.
7. Enable **Settings → Privacy & Security → Developer Mode** on the iPhone if requested. Restart the iPhone and confirm Developer Mode after restart. The option may appear only after pairing with Xcode. See [Apple's Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
8. In Xcode's top toolbar select the **MileLog** scheme and your named **iPhone** as the run destination. Click **Run (▶)** or press **⌘R**. Resolve any Apple signing/account prompts in Xcode.
9. If iOS asks you to trust the developer, open **Settings → General → VPN & Device Management**, select your developer entry and trust it, then open MileLog again.
10. Add a vehicle in **Settings → Vehicles**, then log one manual trip. Start GPS while parked and grant **Allow While Using App**. Enable Precise Location for useful distance measurements.

Apple documents [device execution](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) and [signing configuration](https://help.apple.com/xcode/mac/current/en.lproj/dev60b6fbbc7.html).

## Update a build without losing the log

1. In MileLog, choose **Settings → Create JSON backup** and save it outside MileLog's own folder, for example to iCloud Drive or your Mac. Choosing a cloud destination is an explicit export, not app sync. Keep backups private because they include locations and notes.
2. Leave MileLog installed on the iPhone. Keep the same bundle identifier and signing team in Xcode.
3. Open the updated project, select the same iPhone and press **⌘R**. Xcode normally replaces the executable while keeping its data container. A clean build or deleting Mac DerivedData does not delete the iPhone's log.
4. Confirm your previous trips are visible, then create another backup after using the new build.

**Do not delete the app to update it.** Deleting the app removes its SwiftData store and local recovery copies. If an uninstall is unavoidable, save the JSON outside the app first, reinstall, then use **Settings → Restore JSON backup**.

Free Personal Team provisioning profiles expire seven days after issuance. For the two-week test, reconnect and Run again with the same identity to refresh the signed installation. If the app stops opening because signing expired, do not delete it. See [Apple's account limits](https://developer.apple.com/help/account/basics/about-your-developer-account).

## Capabilities and Info.plist

Signing is the only project-specific setup you must do by hand. The project already includes:

- `NSLocationWhenInUseUsageDescription`: explains user-started recording through screen lock and navigation.
- iOS 17 deployment target, Swift 6 and iPhone target family.
- File sharing so local recovery copies are accessible in Files/Finder.
- A single app scene with local SwiftData storage.
- Background Modes → Location updates for an explicitly started trip.
- App icon resources, privacy manifest, version 1.0/build 2.

No Always location key, iCloud sync, push notification, or automatic drive detection is enabled. Keep the location background mode enabled for user-started recording. CoreLocation and MapKit link automatically through Swift imports.

If startup reports a store error, keep the app installed and send the error text. Do not reset or delete its container. If necessary, Xcode's Devices window can download the app container for recovery; it contains private data.

## Refinement testing constraint

Use only your physical iPhone. Keep the SwiftUI preview canvas closed; do not boot simulators or run automated tests unless explicitly requested. The owner will perform the manual checks in TEST_PERIOD.md. Build 2 has not been built or tested by the assistant.
