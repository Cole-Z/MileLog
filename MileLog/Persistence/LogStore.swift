import SwiftData
import Foundation
import Observation

@Model final class StoredRecord {
    @Attribute(.unique) var id: UUID
    var kind: String
    var payload: Data
    init(id: UUID, kind: String, payload: Data) { self.id = id; self.kind = kind; self.payload = payload }
}

@MainActor @Observable final class LogStore {
    private(set) var data = Backup()
    let container: ModelContainer
    private let storage: RecordStorage
    @ObservationIgnored private let fileDirectory: URL?
    var error: String?
    var report = ReportSelection()

    convenience init(inMemory: Bool = false, existingContainer: ModelContainer? = nil, fileDirectory: URL? = nil) throws {
        try self.init(prepared: LogLoader.prepare(inMemory: inMemory, existingContainer: existingContainer, fileDirectory: fileDirectory))
    }

    init(prepared: PreparedLog) {
        container = prepared.container
        storage = RecordStorage(container: prepared.container)
        fileDirectory = prepared.fileDirectory
        data = prepared.data
    }

    var preferences: LogPreferences { data.preferences ?? LogPreferences() }
    var defaultVehicleID: UUID? {
        if let id = preferences.defaultVehicleID, data.vehicles.contains(where: { $0.id == id }) { return id }
        return data.vehicles.first?.id
    }
    var trips: [Trip] {
        data.trips.filter { $0.deletedAt == nil }.sorted {
            $0.details.day == $1.details.day ? $0.createdAt > $1.createdAt : $0.details.day > $1.details.day
        }
    }
    var reportTrips: [Trip] { trips.filter(report.includes) }

    func commit(_ candidate: Backup) throws {
        try storage.commit(candidate)
        data = candidate
    }

    func savePreferences(_ preferences: LogPreferences) throws {
        var updated = preferences; updated.updatedAt = Date()
        var b = data; b.preferences = updated; try commit(b)
    }
    func saveVehicle(_ vehicle: Vehicle, makeDefault: Bool = false) throws {
        try Validation.vehicle(vehicle)
        var vehicle = vehicle; vehicle.updatedAt = Date()
        let previous = data.vehicles.first { $0.id == vehicle.id }
        var history = previous?.odometerHistory ?? []
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let readingsChanged = try previous.map { try encoder.encode($0.years) != encoder.encode(vehicle.years) } ?? true
        let serviceChanged = previous?.businessServiceDay != vehicle.businessServiceDay || previous?.businessServiceOdometer != vehicle.businessServiceOdometer
        if readingsChanged || serviceChanged {
            let reason = vehicle.odometerCorrectionReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let previous, !previous.years.isEmpty || previous.businessServiceDay != nil || previous.businessServiceOdometer != nil {
                guard !reason.isEmpty else { throw LogError("Add a reason for changing the odometer record.") }
                if history.isEmpty { history.append(OdometerEdit(years: previous.years, serviceDay: previous.businessServiceDay, serviceOdometer: previous.businessServiceOdometer, reason: "Previous readings preserved before first tracked correction")) }
            }
            history.append(OdometerEdit(years: vehicle.years, serviceDay: vehicle.businessServiceDay, serviceOdometer: vehicle.businessServiceOdometer, reason: reason.isEmpty ? "Initial readings" : reason))
        }
        vehicle.odometerHistory = history
        var b = data; b.vehicles.removeAll { $0.id == vehicle.id }; b.vehicles.append(vehicle)
        var preferences = self.preferences
        if makeDefault || preferences.defaultVehicleID == nil { preferences.defaultVehicleID = vehicle.id }
        preferences.updatedAt = Date(); b.preferences = preferences
        try commit(b)
    }
    func saveTrip(_ original: Trip?, details: TripDetails, draftID: UUID? = nil, favorite: String = "", savePurpose: Bool = false, refreshRates: Bool = false) throws {
        try Validation.trip(details)
        var b = data
        let saved = original.flatMap { original in data.trips.first { $0.id == original.id } }
        if original != nil && saved == nil { throw LogError("This trip is no longer in the log. Reopen it before editing.") }
        var trip = saved ?? Trip()
        if let draftID, original == nil {
            guard !b.trips.contains(where: { $0.sourceDraftID == draftID || $0.id == draftID }),
                  !(b.tombstones ?? []).contains(where: { $0.kind == "draft" && $0.recordID == draftID }) else {
                throw LogError("This recording has already been saved or discarded. Check your trip log.")
            }
            trip.id = draftID; trip.sourceDraftID = draftID
        }
        let sourceDraft = draftID.flatMap { id in data.drafts.first { $0.id == id } }
        if draftID != nil && original == nil && sourceDraft == nil { throw LogError("The original recording is unavailable. Reopen the trip log before saving.") }
        if original == nil {
            trip.gpsEvidence = sourceDraft.map(GPSRecordingEvidence.init)
            trip.originalDetails = sourceDraft?.recordedDetails ?? details
        }
        let before = saved?.details ?? sourceDraft?.recordedDetails
        if trip.gpsEvidence != nil, let before,
           (before.totalMiles != details.totalMiles || before.start.latitude != details.start.latitude || before.start.longitude != details.start.longitude || before.end.latitude != details.end.latitude || before.end.longitude != details.end.longitude || before.startedAt != details.startedAt || before.endedAt != details.endedAt || before.day != details.day || before.startTimeZoneID != details.startTimeZoneID || before.endTimeZoneID != details.endTimeZoneID) {
            guard !(details.correctionReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LogError("Add a reason for correcting the recorded distance, coordinates, or times.") }
        }
        if trip.gpsEvidence != nil && details.method != .gps { throw LogError("A GPS recording must retain its original source.") }
        trip.details = details; trip.updatedAt = Date()
        if trip.ratesCapturedAt == nil || refreshRates || saved?.details.day != details.day || saved?.details.category != details.category || saved?.details.effectiveJurisdiction != details.effectiveJurisdiction {
            Recordkeeping.snapshotRates(&trip, rates: data.rates, note: original == nil ? "Captured when saved" : "Explicit refresh or changed trip date/category/jurisdiction")
        }
        trip.history.append(TripEditEvent(action: original == nil ? "Created" : (refreshRates ? "Edited and rates refreshed" : "Edited"), details: details, irsRate: trip.irsRate, employerRate: trip.employerRate))
        b.trips.removeAll { $0.id == trip.id }; b.trips.append(trip)
        if let draftID {
            b.drafts.removeAll { $0.id == draftID }
            b.tombstones = (b.tombstones ?? []) + [RecordTombstone(recordID: draftID, kind: "draft")]
        }
        let name = favorite.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { b.frequentTrips.append(FrequentTrip(name: name, details: details)) }
        if savePurpose && !details.purpose.isEmpty && !b.purposes.contains(where: { $0.text == details.purpose }) {
            b.purposes.append(SavedPurpose(text: details.purpose))
        }
        try commit(b)
    }
    func delete(_ trip: Trip) throws {
        var b = data
        guard let i = b.trips.firstIndex(where: { $0.id == trip.id }) else { return }
        b.trips[i].deletedAt = Date(); b.trips[i].updatedAt = Date()
        b.trips[i].history.append(TripEditEvent(action: "Deleted", details: trip.details))
        try commit(b)
    }
    func removeRecord(id: UUID, kind: String) throws {
        var b = data
        switch kind {
        case "draft": b.drafts.removeAll { $0.id == id }
        case "rate": b.rates.removeAll { $0.id == id }
        case "frequent": b.frequentTrips.removeAll { $0.id == id }
        case "purpose": b.purposes.removeAll { $0.id == id }
        default: throw LogError("Unsupported record removal.")
        }
        b.tombstones = (b.tombstones ?? []) + [RecordTombstone(recordID: id, kind: kind)]
        try commit(b)
    }
    // The frequent GPS checkpoint touches only its one SwiftData row.
    func saveDraft(_ draft: RecordingDraft) throws {
        guard !(data.tombstones ?? []).contains(where: { $0.kind == "draft" && $0.recordID == draft.id }) else { throw LogError("This recording has already been saved or discarded.") }
        try storage.saveDraft(draft)
        if let index = data.drafts.firstIndex(where: { $0.id == draft.id }) { data.drafts[index] = draft }
        else { data.drafts.append(draft) }
    }
    func backupFile() throws -> URL {
        var b = data; b.exportedAt = Date()
        return try writeFile(BackupService.encode(b), name: "MileLog-backup-\(Day.string(Date()))-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json", permanent: true)
    }
    func writeFile(_ bytes: Data, name: String, permanent: Bool = false) throws -> URL {
        try LogFiles.write(bytes, name: name, permanent: permanent, directory: fileDirectory)
    }
    func restore(_ incoming: Backup) throws {
        var merged = try BackupService.merge(data, incoming)
        try LogLoader.applyBundledRates(to: &merged)
        _ = try backupFile()
        try commit(merged)
    }
    func eraseLog() throws {
        var fresh = Backup(); fresh.preferences = LogPreferences()
        try LogLoader.applyBundledRates(to: &fresh)
        try commit(fresh)
        report = ReportSelection()
        let directories = fileDirectory.map { [$0] } ?? [FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0], FileManager.default.temporaryDirectory]
        do {
            for directory in directories {
                for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    where url.lastPathComponent.hasPrefix("MileLog-") && ["json", "csv", "pdf"].contains(url.pathExtension) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        } catch { throw LogError("The log was cleared, but some local export files could not be removed. Open Recovery copies to remove them: \(error.localizedDescription)") }
    }
    func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
}
