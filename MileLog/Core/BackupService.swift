import Foundation

enum BackupService {
    static func encode(_ backup: Backup) throws -> Data {
        var portable = backup
        portable.version = 2
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Preserve subsecond edit ordering; version 1 used whole-second ISO dates.
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(portable)
    }

    static func decode(_ data: Data) throws -> Backup {
        guard data.count < 50_000_000 else { throw LogError("Backup exceeds the 50 MB import limit.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            if let seconds = try? value.decode(Double.self), seconds.isFinite {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let text = try value.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw LogError("Invalid backup timestamp.") }
            return date
        }
        let backup = try decoder.decode(Backup.self, from: data)
        try validate(backup)
        return backup
    }

    static func validate(_ b: Backup) throws {
        guard b.format == "MileLog", (1...2).contains(b.version) else {
            throw LogError("This backup needs a different version of MileLog.")
        }
        var ids = b.trips.map(\.id) + b.vehicles.map(\.id) + b.rates.map(\.id)
        ids += b.purposes.map(\.id) + b.frequentTrips.map(\.id) + b.feedback.map(\.id) + b.drafts.map(\.id)
        ids += (b.tombstones ?? []).map(\.id)
        if let preferences = b.preferences { ids.append(preferences.id) }
        guard Set(ids).count == ids.count else { throw LogError("Backup contains duplicate record IDs.") }
        let vehicles = Set(b.vehicles.map(\.id))
        func checkVehicle(_ id: UUID?) throws {
            if let id, !vehicles.contains(id) { throw LogError("Backup refers to a missing vehicle.") }
        }
        for t in b.trips {
            try Validation.trip(t.details)
            try checkVehicle(t.details.vehicleID)
            guard t.updatedAt >= t.createdAt, !t.history.isEmpty else { throw LogError("Backup has an incomplete trip history.") }
            for event in t.history { try Validation.trip(event.details) }
        }
        let sources = b.trips.compactMap(\.sourceDraftID)
        guard Set(sources).count == sources.count else { throw LogError("Backup contains multiple trips from the same recording.") }
        for v in b.vehicles { try Validation.vehicle(v) }
        for r in b.rates { try Validation.rate(r, others: b.rates) }
        for f in b.frequentTrips { try Validation.trip(f.details); try checkVehicle(f.details.vehicleID) }
        for d in b.drafts {
            try checkVehicle(d.vehicleID)
            guard d.meters.isFinite, d.meters >= 0 else { throw LogError("Invalid GPS draft distance.") }
            for fix in [d.first, d.last].compactMap({ $0 }) {
                guard fix.latitude.isFinite, fix.longitude.isFinite, abs(fix.latitude) <= 90,
                      abs(fix.longitude) <= 180, fix.accuracy >= 0, fix.accuracy <= 50 else {
                    throw LogError("Invalid GPS draft coordinates.")
                }
            }
        }
        for tombstone in b.tombstones ?? [] {
            guard ["draft", "rate", "frequent", "purpose"].contains(tombstone.kind) else { throw LogError("Unknown deleted record type.") }
        }
        if let preferences = b.preferences {
            guard preferences.schemaVersion == 2 else { throw LogError("These settings require a newer app version.") }
            try checkVehicle(preferences.defaultVehicleID)
        }
    }

    static func mergeRecords<T: Record>(_ current: [T], _ imported: [T]) -> [T] {
        var values = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for item in imported where values[item.id] == nil || item.updatedAt > values[item.id]!.updatedAt {
            values[item.id] = item
        }
        return values.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    static func merge(_ current: Backup, _ imported: Backup) throws -> Backup {
        try validate(current)
        try validate(imported)
        var b = current
        b.version = 2
        b.trips = mergeRecords(current.trips, imported.trips)
        b.vehicles = mergeRecords(current.vehicles, imported.vehicles)
        b.rates = mergeRecords(current.rates, imported.rates)
        b.purposes = mergeRecords(current.purposes, imported.purposes)
        b.frequentTrips = mergeRecords(current.frequentTrips, imported.frequentTrips)
        b.feedback = mergeRecords(current.feedback, imported.feedback)
        b.tombstones = mergeRecords(current.tombstones ?? [], imported.tombstones ?? [])
        let retiredDrafts = Set((b.tombstones ?? []).filter { $0.kind == "draft" }.map(\.recordID))
            .union(b.trips.compactMap(\.sourceDraftID))
        b.drafts = mergeRecords(current.drafts, imported.drafts).filter { !retiredDrafts.contains($0.id) }
        for i in b.drafts.indices where !current.drafts.contains(where: { $0.id == b.drafts[i].id }) {
            // Older backups cannot prove whether a draft was already logged.
            b.drafts[i].needsDuplicateReview = true
            b.drafts[i].interrupted = true
        }
        let tombstones = b.tombstones ?? []
        func isDeleted<T: Record>(_ item: T, kind: String) -> Bool {
            tombstones.contains { $0.kind == kind && $0.recordID == item.id && $0.updatedAt >= item.updatedAt }
        }
        b.rates.removeAll { isDeleted($0, kind: "rate") }
        b.frequentTrips.removeAll { isDeleted($0, kind: "frequent") }
        b.purposes.removeAll { isDeleted($0, kind: "purpose") }
        // Keep local onboarding/default choices. Imported choices help a fresh installation only.
        if b.preferences == nil { b.preferences = imported.preferences }
        if var preferences = b.preferences {
            preferences.installedRateIDs = Array(Set(preferences.installedRateIDs + (imported.preferences?.installedRateIDs ?? [])))
            b.preferences = preferences
        }
        try validate(b)
        return b
    }
}
