import SwiftData
import Foundation
import Observation

// A versioned Codable payload per entity keeps the SwiftData schema stable.
// IDs and kinds are queryable; portable value models also drive backup and tests.
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
    var error: String?
    init(inMemory: Bool = false) throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        container = try ModelContainer(for: StoredRecord.self, configurations: config)
        context = ModelContext(container); context.autosaveEnabled = false
        let rows = try context.fetch(FetchDescriptor<StoredRecord>())
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
            default: throw LogError("Unknown stored record. Open this data with a newer version of MileLog.")
            }
        }
        if rows.isEmpty {
            guard let url = Bundle.main.url(forResource: "SeedRates", withExtension: "json") else { throw LogError("Seed rates resource is missing.") }
            data.rates = try decoder.decode([MileageRate].self, from: Data(contentsOf: url))
            data.purposes = ["Client meeting", "Supply pickup", "Delivery"].map { SavedPurpose(text: $0) }
            try commit(data)
        }
    }
    var trips: [Trip] { data.trips.filter { $0.deletedAt == nil }.sorted { $0.details.day == $1.details.day ? $0.createdAt > $1.createdAt : $0.details.day > $1.details.day } }
    func commit(_ candidate: Backup) throws {
        let encoder = JSONEncoder()
        var encoded: [(UUID, String, Data)] = []
        func add<T: Record>(_ records: [T], _ kind: String) throws { for r in records { encoded.append((r.id, kind, try encoder.encode(r))) } }
        try add(candidate.trips, "trip"); try add(candidate.vehicles, "vehicle"); try add(candidate.rates, "rate"); try add(candidate.purposes, "purpose"); try add(candidate.frequentTrips, "frequent"); try add(candidate.feedback, "feedback"); try add(candidate.drafts, "draft")
        do {
            let existing = try context.fetch(FetchDescriptor<StoredRecord>())
            let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            let ids = Set(encoded.map { $0.0 })
            for (id, kind, payload) in encoded {
                if let row = byID[id] { if row.payload != payload { row.payload = payload } }
                else { context.insert(StoredRecord(id: id, kind: kind, payload: payload)) }
            }
            for row in existing where !ids.contains(row.id) { context.delete(row) }
            try context.save()
            data = candidate
        } catch { context.rollback(); throw error }
    }
    func saveTrip(_ original: Trip?, details: TripDetails, draftID: UUID? = nil, favorite: String = "", savePurpose: Bool = false) throws {
        try Validation.trip(details)
        var b = data
        var trip = original ?? Trip()
        trip.details = details; trip.updatedAt = Date()
        trip.history.append(TripEditEvent(action: original == nil ? "Created" : "Edited", details: details))
        b.trips.removeAll { $0.id == trip.id }; b.trips.append(trip)
        if let draftID { b.drafts.removeAll { $0.id == draftID } }
        if !favorite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { b.frequentTrips.append(FrequentTrip(name: favorite, details: details)) }
        if savePurpose && !details.purpose.isEmpty && !b.purposes.contains(where: { $0.text == details.purpose }) { b.purposes.append(SavedPurpose(text: details.purpose)) }
        try commit(b)
    }
    func delete(_ trip: Trip) throws {
        var b = data
        guard let i = b.trips.firstIndex(where: { $0.id == trip.id }) else { return }
        b.trips[i].deletedAt = Date(); b.trips[i].updatedAt = Date()
        b.trips[i].history.append(TripEditEvent(action: "Deleted", details: trip.details))
        try commit(b)
    }
    func saveDraft(_ draft: RecordingDraft) throws {
        var b = data; b.drafts.removeAll { $0.id == draft.id }; b.drafts.append(draft); try commit(b)
    }
    func backupFile() throws -> URL {
        var b = data; b.exportedAt = Date()
        return try writeFile(BackupService.encode(b), name: "MileLog-backup-\(Int(Date().timeIntervalSince1970)).json", permanent: true)
    }
    func writeFile(_ bytes: Data, name: String, permanent: Bool = false) throws -> URL {
        let base = permanent ? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] : FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent(name)
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
    func restore(_ incoming: Backup) throws {
        let merged = try BackupService.merge(data, incoming)
        _ = try backupFile() // Keep a recovery copy before applying a restore.
        try commit(merged)
    }
    func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
}
