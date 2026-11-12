import CoreLocation
import Observation
import UIKit

// CLLocationManager is created on the main thread and delivers delegates on that run loop.
@MainActor @Observable final class LocationRecorder: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let store: LogStore
    private var previous: GPSFix?
    private var pendingStart = false
    private(set) var draft: RecordingDraft?
    private(set) var recording = false
    var status = "Ready to record"
    var error: String?
    init(store: LogStore) {
        self.store = store
        draft = store.data.drafts.sorted { $0.createdAt < $1.createdAt }.first
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.allowsBackgroundLocationUpdates = false
        if var recovered = draft {
            if !recovered.ended { recovered.interrupted = true; recovered.updatedAt = Date(); persist(recovered) }
            status = "Recovered trip — review distance before saving"
        }
    }
    func start() {
        guard draft?.ended != true else { return }
        switch manager.authorizationStatus {
        case .notDetermined: pendingStart = true; manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: begin()
        default: error = "Allow location access in iPhone Settings → Apps → MileLog → Location, or enter the trip manually."
        }
    }
    private func begin() {
        guard UIApplication.shared.applicationState == .active else { return }
        pendingStart = false
        var d = draft ?? RecordingDraft()
        d.updatedAt = Date()
        guard persist(d) else { return }
        previous = nil; recording = true
        status = "Waiting for an accurate GPS fix…"
        UIApplication.shared.isIdleTimerDisabled = true
        manager.startUpdatingLocation()
    }
    @discardableResult private func persist(_ value: RecordingDraft) -> Bool {
        do { try store.saveDraft(value); draft = value; return true }
        catch {
            draft = value; recording = false; manager.stopUpdatingLocation(); UIApplication.shared.isIdleTimerDisabled = false
            self.error = "Recording paused because it could not be saved: \(error.localizedDescription). Free space and retry before closing the app."
            return false
        }
    }
    func pause() {
        guard recording else { return }
        pendingStart = false
        manager.stopUpdatingLocation(); recording = false; previous = nil
        UIApplication.shared.isIdleTimerDisabled = false
        if var d = draft { d.interrupted = true; d.updatedAt = Date(); persist(d) }
        status = "Paused — distance during this gap is not recorded"
    }
    func becameActive() {
        if pendingStart && (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways) { begin() }
    }
    func end() {
        pendingStart = false; manager.stopUpdatingLocation(); recording = false; previous = nil
        UIApplication.shared.isIdleTimerDisabled = false
        if var d = draft {
            if d.last == nil || Date().timeIntervalSince(d.last!.timestamp) > 30 { d.interrupted = true }
            d.ended = true; d.updatedAt = Date(); persist(d)
        }
        status = "Ready to review"
    }
    func refresh() {
        draft = store.data.drafts.sorted { $0.createdAt < $1.createdAt }.first
        previous = nil
        status = draft == nil ? "Ready to record" : "Recovered trip — review distance before saving"
    }
    func discard() {
        guard !recording, let draft else { return }
        store.perform { var b = store.data; b.drafts.removeAll { $0.id == draft.id }; try store.commit(b); refresh() }
    }
    func details() -> TripDetails {
        var d = TripDetails()
        guard let draft else { return d }
        d.day = Day.string(draft.createdAt); d.method = .gps
        d.miles = draft.meters / DistanceCalculator.metersPerMile
        d.start = draft.first?.place ?? Place(); d.end = draft.last?.place ?? Place()
        if draft.interrupted { d.notes = "GPS recording was interrupted. Verify distance and manually correct any missing mileage." }
        d.vehicleID = store.trips.first?.details.vehicleID ?? store.data.vehicles.first?.id
        return d
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if pendingStart && (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways) { begin() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            pendingStart = false; pause(); error = "Location access is unavailable. Manual trip entry still works."
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard recording, var d = draft else { return }
        for location in locations {
            let fix = GPSFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy, timestamp: location.timestamp)
            guard DistanceCalculator.usable(fix, now: Date()) else { status = "Weak GPS signal — waiting for accuracy"; continue }
            if let previous {
                if let meters = DistanceCalculator.segment(previous, fix) { d.meters += meters }
                else { d.interrupted = true }
            }
            if d.first == nil { d.first = fix }
            d.last = fix; previous = fix
            status = d.interrupted ? "Recording • earlier gap needs review" : "Recording • GPS connected"
        }
        d.updatedAt = Date(); persist(d)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let cl = error as? CLError, cl.code == .locationUnknown { status = "GPS unavailable — waiting for signal"; return }
        pause(); self.error = error.localizedDescription
    }
}
