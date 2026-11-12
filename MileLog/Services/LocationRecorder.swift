import CoreLocation
import Observation
import UIKit

@MainActor @Observable final class LocationRecorder: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let store: LogStore
    private var accumulator = DistanceAccumulator()
    private var pendingStart = false
    private var checkpointAt = Date.distantPast
    private(set) var draft: RecordingDraft?
    private(set) var recording = false
    var status = "Ready when you are"
    var error: String?

    init(store: LogStore) {
        self.store = store
        draft = store.data.drafts.sorted { $0.createdAt < $1.createdAt }.first
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        if var recovered = draft {
            if !recovered.ended {
                recovered.interrupted = true; recovered.updatedAt = Date()
                _ = persist(recovered)
            }
            status = "Saved recording recovered — review before continuing"
        }
    }

    func start() {
        guard !recording, draft?.ended != true else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            pendingStart = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: begin()
        default: error = "Enable location in iPhone Settings → MileLog → Location to record a trip. You can always add trips manually."
        }
    }
    private func begin() {
        guard UIApplication.shared.applicationState == .active else { return }
        pendingStart = false
        guard manager.accuracyAuthorization == .fullAccuracy else {
            error = "GPS mileage needs Precise Location. Enable it in iPhone Settings → MileLog → Location, or add your trip manually."
            return
        }
        var value = draft ?? RecordingDraft()
        if value.vehicleID == nil { value.vehicleID = store.defaultVehicleID }
        value.updatedAt = Date()
        guard persist(value) else { return }
        accumulator.reset()
        recording = true
        status = "Waiting for an accurate location…"
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }
    private func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        recording = false
        accumulator.reset()
    }
    @discardableResult private func persist(_ value: RecordingDraft) -> Bool {
        do {
            try store.saveDraft(value)
            draft = value; checkpointAt = Date(); self.error = nil
            return true
        } catch {
            var unsaved = value
            unsaved.interrupted = true
            unsaved.updatedAt = Date()
            draft = unsaved
            stopUpdates()
            status = "Paused — recording could not be saved"
            self.error = "Your latest distance is still on this screen, but could not be saved. Free storage and retry before closing MileLog. \(error.localizedDescription)"
            return false
        }
    }
    @discardableResult func checkpoint() -> Bool {
        guard let draft else { return true }
        return persist(draft)
    }
    func pause() {
        guard recording else { return }
        pendingStart = false
        stopUpdates()
        if var value = draft {
            value.interrupted = true; value.updatedAt = Date()
            if persist(value) { status = "Paused — movement during this pause is not recorded" }
        }
    }
    func becameActive() {
        if pendingStart && (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways) { begin() }
    }
    @discardableResult func end() -> Bool {
        pendingStart = false
        stopUpdates()
        if var value = draft {
            if value.last == nil || Date().timeIntervalSince(value.last!.timestamp) > 30 { value.interrupted = true }
            value.ended = true; value.updatedAt = Date()
            if persist(value) { status = "Ready to review and save"; return true }
        }
        return false
    }
    func refresh() {
        guard !recording else { return }
        draft = store.data.drafts.sorted { $0.createdAt < $1.createdAt }.first
        accumulator.reset()
        status = draft == nil ? "Ready when you are" : "Saved recording — review before saving"
    }
    func discard() {
        guard !recording, let draft else { return }
        do { try store.removeRecord(id: draft.id, kind: "draft"); refresh() }
        catch { self.error = error.localizedDescription }
    }
    func details() -> TripDetails {
        var details = TripDetails()
        guard let draft else { return details }
        details.day = Day.string(draft.createdAt); details.method = .gps
        details.miles = draft.meters / DistanceCalculator.metersPerMile
        details.start = draft.first?.place ?? Place(); details.end = draft.last?.place ?? Place()
        details.vehicleID = draft.vehicleID ?? store.defaultVehicleID
        if draft.interrupted { details.notes = "Recording includes a pause, signal gap, or recovery. Verify the distance and correct any missing miles." }
        return details
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if pendingStart && (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways) { begin() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            pendingStart = false
            if recording { pause(); error = "Location permission changed. Recording is paused; manual trip entry remains available." }
        } else if recording && manager.accuracyAuthorization == .reducedAccuracy {
            pause(); error = "Precise Location was turned off. Enable it to resume, or enter the remaining distance manually."
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard recording, var value = draft else { return }
        for location in locations {
            let fix = GPSFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy, timestamp: location.timestamp)
            guard DistanceCalculator.usable(fix, now: Date()) else {
                status = "Weak location signal — waiting for accuracy"
                continue
            }
            let segment = accumulator.add(fix)
            value.meters += segment.meters
            if segment.gap { value.interrupted = true }
            if value.first == nil {
                if fix.timestamp.timeIntervalSince(value.createdAt) > 30 { value.interrupted = true }
                value.first = fix
            }
            value.last = fix
            status = value.interrupted ? "Recording · earlier gap needs review" : "Recording · location connected"
        }
        value.updatedAt = Date()
        draft = value
        // At most five seconds of delivered fixes can be uncheckpointed on termination.
        if Date().timeIntervalSince(checkpointAt) >= 5 { _ = persist(value) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError, error.code == .locationUnknown {
            status = "Location unavailable — waiting for signal"
            return
        }
        pause(); self.error = error.localizedDescription
    }
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) { pause() }
}
