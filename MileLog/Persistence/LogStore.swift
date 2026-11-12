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
    private let context: ModelContext
    @ObservationIgnored private let fileDirectory: URL?
    @ObservationIgnored private var rowsByID: [UUID: StoredRecord] = [:]
    var error: String?
    var report = ReportSelection()

    init(inMemory: Bool = false, existingContainer: ModelContainer? = nil, fileDirectory: URL? = nil) throws {
        self.fileDirectory = fileDirectory ?? (inMemory ? FileManager.default.temporaryDirectory.appendingPathComponent("MileLog-test-\(UUID().uuidString)") : nil)
        if let directory = self.fileDirectory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        container = try existingContainer ?? ModelContainer(for: StoredRecord.self, configurations: config)
        context = ModelContext(container)
        context.autosaveEnabled = false
        let rows = try context.fetch(FetchDescriptor<StoredRecord>())
        rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let decoder = JSONDecoder()
        for row in rows {
            switch row.kind {
            case "trip": data.trips.append(try decoder.decode(Trip.self, from: row.payload))
            case "vehicle": data.vehicles.append(try decoder.decode(Vehicle.self, from: row.payload))
            case "rate": data.rates.append(try decoder.decode(MileageRate.self, from: row.payload))
            case "purpose": data.purposes.append(try decoder.decode(SavedPurpose.self, from: row.payload))
            case "frequent": data.frequentTrips.append(try decoder.decode(FrequentTrip.self, from: row.payload))
            case "feedback": data.feedback.append(try decoder.decode(FeedbackNote.self, from: row.payload))
            case "draft": data.drafts.append(try decoder.decode(RecordingDraft.self, from: row.payload))
            case "tombstone": data.tombstones = (data.tombstones ?? []) + [try decoder.decode(RecordTombstone.self, from: row.payload)]
            case "preferences": data.preferences = try decoder.decode(LogPreferences.self, from: row.payload)
            default: throw LogError("Unknown stored record. Open this data with a newer version of MileLog.")
            }
        }
        let needsMigration = !rows.isEmpty && (data.preferences?.schemaVersion ?? 2) < 3
        if needsMigration { _ = try backupFile() }
        var upgraded = Recordkeeping.migrate(data)
        if upgraded.preferences == nil {
            var preferences = LogPreferences()
            preferences.hasCompletedWelcome = !upgraded.vehicles.isEmpty || !upgraded.trips.isEmpty
            preferences.defaultVehicleID = upgraded.vehicles.first?.id
            // These were shipped by version 1. Remember deleted seeds rather than bringing them back.
            if !rows.isEmpty { preferences.installedRateIDs = Self.legacyRateIDs }
            upgraded.preferences = preferences
        }
        if rows.isEmpty {
            upgraded.purposes = ["Client meeting", "Supply pickup", "Delivery"].map { SavedPurpose(text: $0) }
        }
        try applyBundledRates(to: &upgraded)
        upgraded.version = 3
        try commit(upgraded)
    }

    private static let legacyRateIDs = [
        "0091b273-bf8a-539e-b5b2-e9278bbd43d5", "0f850d8a-121f-50f6-b2e4-ec05ef5c3e67",
        "18d3b03c-d080-5dac-97e4-acde6ce116d0", "8a470214-4e23-5fa6-8493-4597458149b8",
        "6dbcc59d-434a-5741-9132-531b806fefd5", "6e127686-80e1-5eba-8fba-8fc73b6e0a95",
        "8981f0b2-5425-5a7d-90e0-f2e7a519e2b6", "b330952e-bfd1-5e03-8def-be511873d8d8",
        "c066669e-3524-57eb-b3b4-5cd7188eb43f", "7574513a-cbc2-5f02-bdc4-1490d19b56ba",
        "387f941c-1133-5779-84ea-22b15cff60bb", "c1c42f2c-a7ed-5f37-b9c2-e145acbb8f50"
    ].compactMap(UUID.init(uuidString:))

    private func applyBundledRates(to b: inout Backup) throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "SeedRates", withExtension: "json") else {
            throw LogError("The bundled rate table could not be opened.")
        }
        let seeds = try JSONDecoder().decode([MileageRate].self, from: Data(contentsOf: url))
        var preferences = b.preferences ?? LogPreferences()
        let seen = Set(preferences.installedRateIDs)
        let deleted = Set((b.tombstones ?? []).filter { $0.kind == "rate" }.map(\.recordID))
        for seed in seeds where !deleted.contains(seed.id) {
            if b.rates.contains(where: { $0.id == seed.id }) {
                // Existing rate records are historical data; never replace them automatically.
            } else if !seen.contains(seed.id), (try? Validation.rate(seed, others: b.rates)) != nil {
                b.rates.append(seed)
            }
        }
        preferences.installedRateIDs = Array(seen.union(seeds.map(\.id)))
        b.preferences = preferences
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
        try BackupService.validate(candidate)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var encoded: [(UUID, String, Data)] = []
        func add<T: Record>(_ records: [T], _ kind: String) throws {
            for record in records { encoded.append((record.id, kind, try encoder.encode(record))) }
        }
        try add(candidate.trips, "trip"); try add(candidate.vehicles, "vehicle")
        try add(candidate.rates, "rate"); try add(candidate.purposes, "purpose")
        try add(candidate.frequentTrips, "frequent"); try add(candidate.feedback, "feedback")
        try add(candidate.drafts, "draft"); try add(candidate.tombstones ?? [], "tombstone")
        if let preferences = candidate.preferences { try add([preferences], "preferences") }
        var nextRows = rowsByID
        do {
            let ids = Set(encoded.map { $0.0 })
            for (id, kind, payload) in encoded {
                if let row = nextRows[id] {
                    if row.payload != payload { row.payload = payload }
                    if row.kind != kind { row.kind = kind }
                } else {
                    let row = StoredRecord(id: id, kind: kind, payload: payload)
                    context.insert(row); nextRows[id] = row
                }
            }
            for (id, row) in rowsByID where !ids.contains(id) { context.delete(row); nextRows.removeValue(forKey: id) }
            try context.save()
            rowsByID = nextRows
            data = candidate
        } catch { context.rollback(); throw error }
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
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(draft)
        let existing = rowsByID[draft.id]
        guard existing == nil || existing?.kind == "draft" else { throw LogError("This trip has already been saved.") }
        let row = existing ?? StoredRecord(id: draft.id, kind: "draft", payload: payload)
        do {
            if existing == nil { context.insert(row) } else { row.payload = payload }
            try context.save()
            rowsByID[draft.id] = row
            if let index = data.drafts.firstIndex(where: { $0.id == draft.id }) { data.drafts[index] = draft }
            else { data.drafts.append(draft) }
        } catch { context.rollback(); throw error }
    }
    func backupFile() throws -> URL {
        var b = data; b.exportedAt = Date()
        return try writeFile(BackupService.encode(b), name: "MileLog-backup-\(Day.string(Date()))-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json", permanent: true)
    }
    func writeFile(_ bytes: Data, name: String, permanent: Bool = false) throws -> URL {
        let base = fileDirectory ?? (permanent ? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] : FileManager.default.temporaryDirectory)
        let url = base.appendingPathComponent(name)
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
    func restore(_ incoming: Backup) throws {
        var merged = try BackupService.merge(data, incoming)
        try applyBundledRates(to: &merged)
        _ = try backupFile()
        try commit(merged)
    }
    func eraseLog() throws {
        var fresh = Backup(); fresh.preferences = LogPreferences()
        try applyBundledRates(to: &fresh)
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
