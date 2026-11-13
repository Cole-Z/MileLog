import Foundation
import SwiftData

// ModelContext and StoredRecord never cross executor boundaries. A separate
// storage session is created on the main actor after background preparation.
struct PreparedLog: Sendable {
    let container: ModelContainer
    let data: Backup
    let fileDirectory: URL?
}

enum StartupStage: Int, Sendable {
    case opening, reading, upgrading, recovering, finishing
    var message: String {
        switch self {
        case .opening: "Opening your mileage log…"
        case .reading: "Loading your saved records…"
        case .upgrading: "Protecting and updating older records…"
        case .recovering: "Checking saved recordings…"
        case .finishing: "Preparing your trips…"
        }
    }
}

enum LogLoader {
    static func prepare(inMemory: Bool = false, existingContainer: ModelContainer? = nil,
                        fileDirectory: URL? = nil, progress: @Sendable (StartupStage) -> Void = { _ in }) throws -> PreparedLog {
        let directory = fileDirectory ?? (inMemory ? FileManager.default.temporaryDirectory.appendingPathComponent("MileLog-test-\(UUID().uuidString)") : nil)
        if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        progress(.opening)
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        let container = try existingContainer ?? ModelContainer(for: StoredRecord.self, configurations: config)
        let storage = RecordStorage(container: container)
        progress(.reading)
        let rows = try storage.rows()
        var data = Backup()
        let decoder = JSONDecoder()
        for row in rows.values {
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
        // Validate before migration can normalize a version from a newer app.
        try BackupService.validate(data)
        let needsMigration = !rows.isEmpty && (data.preferences?.schemaVersion ?? 2) < 3
        if needsMigration {
            progress(.upgrading)
            _ = try LogFiles.write(BackupService.encode(data), name: "MileLog-backup-before-upgrade-\(UUID().uuidString).json", permanent: true, directory: directory)
        }
        var upgraded = Recordkeeping.migrate(data)
        if upgraded.preferences == nil {
            var preferences = LogPreferences()
            preferences.hasCompletedWelcome = !upgraded.vehicles.isEmpty || !upgraded.trips.isEmpty
            preferences.defaultVehicleID = upgraded.vehicles.first?.id
            if !rows.isEmpty { preferences.installedRateIDs = legacyRateIDs }
            upgraded.preferences = preferences
        }
        if rows.isEmpty { upgraded.purposes = ["Client meeting", "Supply pickup", "Delivery"].map { SavedPurpose(text: $0) } }
        try applyBundledRates(to: &upgraded)
        progress(.recovering)
        if let index = upgraded.drafts.indices.min(by: { upgraded.drafts[$0].createdAt < upgraded.drafts[$1].createdAt }), !upgraded.drafts[index].ended {
            upgraded.drafts[index].interrupted = true
            upgraded.drafts[index].updatedAt = Date()
            upgraded.drafts[index].interruptionReasons = Array(Set((upgraded.drafts[index].interruptionReasons ?? []) + ["Recovered after app interruption"]))
        }
        progress(.finishing)
        try storage.commit(upgraded)
        return PreparedLog(container: container, data: upgraded, fileDirectory: directory)
    }

    static let legacyRateIDs = [
        "0091b273-bf8a-539e-b5b2-e9278bbd43d5", "0f850d8a-121f-50f6-b2e4-ec05ef5c3e67",
        "18d3b03c-d080-5dac-97e4-acde6ce116d0", "8a470214-4e23-5fa6-8493-4597458149b8",
        "6dbcc59d-434a-5741-9132-531b806fefd5", "6e127686-80e1-5eba-8fba-8fc73b6e0a95",
        "8981f0b2-5425-5a7d-90e0-f2e7a519e2b6", "b330952e-bfd1-5e03-8def-be511873d8d8",
        "c066669e-3524-57eb-b3b4-5cd7188eb43f", "7574513a-cbc2-5f02-bdc4-1490d19b56ba",
        "387f941c-1133-5779-84ea-22b15cff60bb", "c1c42f2c-a7ed-5f37-b9c2-e145acbb8f50"
    ].compactMap(UUID.init(uuidString:))

    static func applyBundledRates(to b: inout Backup) throws {
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

}

// Synchronous sessions are executor-confined; this type deliberately is not Sendable.
final class RecordStorage {
    private let context: ModelContext
    private var cachedRows: [UUID: StoredRecord]?
    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }
    func rows() throws -> [UUID: StoredRecord] {
        if let cachedRows { return cachedRows }
        let rows = try context.fetch(FetchDescriptor<StoredRecord>())
        var indexed: [UUID: StoredRecord] = [:]
        for row in rows {
            guard indexed.updateValue(row, forKey: row.id) == nil else { throw LogError("The log contains duplicate record IDs. Your data has not been erased.") }
        }
        cachedRows = indexed
        return indexed
    }
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
        let rowsByID = try rows()
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
            cachedRows = nextRows
        } catch { context.rollback(); throw error }
    }

    func saveDraft(_ draft: RecordingDraft) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(draft)
        let id = draft.id
        let existing: StoredRecord?
        if let cachedRows { existing = cachedRows[id] }
        else {
            var request = FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.id == id })
            request.fetchLimit = 1
            existing = try context.fetch(request).first
        }
        guard existing == nil || existing?.kind == "draft" else { throw LogError("This trip has already been saved.") }
        let row = existing ?? StoredRecord(id: draft.id, kind: "draft", payload: payload)
        do {
            if existing == nil { context.insert(row) } else { row.payload = payload }
            try context.save()
            if cachedRows != nil { cachedRows?[draft.id] = row }
        } catch { context.rollback(); throw error }
    }
}

enum LogFiles {
    static func write(_ bytes: Data, name: String, permanent: Bool, directory: URL?) throws -> URL {
        let base = directory ?? (permanent ? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] : FileManager.default.temporaryDirectory)
        let url = base.appendingPathComponent(name)
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }
}
