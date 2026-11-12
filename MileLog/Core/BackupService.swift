import Foundation

enum BackupService {
    static func encode(_ backup: Backup) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }
    static func decode(_ data: Data) throws -> Backup {
        guard data.count < 50_000_000 else { throw LogError("Backup exceeds the 50 MB import limit.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)
        try validate(backup)
        return backup
    }
    static func validate(_ b: Backup) throws {
        guard b.format == "MileLog", b.version == 1 else { throw LogError("This backup format is not supported by this version of MileLog.") }
        let ids = b.trips.map(\.id) + b.vehicles.map(\.id) + b.rates.map(\.id) + b.purposes.map(\.id) + b.frequentTrips.map(\.id) + b.feedback.map(\.id) + b.drafts.map(\.id)
        guard Set(ids).count == ids.count else { throw LogError("Backup contains duplicate record IDs.") }
        let vehicles = Set(b.vehicles.map(\.id))
        for t in b.trips {
            try Validation.trip(t.details)
            guard t.details.vehicleID == nil || vehicles.contains(t.details.vehicleID!) else { throw LogError("Backup contains a trip with a missing vehicle.") }
            guard t.updatedAt >= t.createdAt, !t.history.isEmpty else { throw LogError("Backup has an incomplete trip history.") }
            for event in t.history { try Validation.trip(event.details) }
        }
        for v in b.vehicles { try Validation.vehicle(v) }
        for r in b.rates { try Validation.rate(r, others: b.rates) }
        for f in b.frequentTrips { try Validation.trip(f.details) }
        for d in b.drafts {
            guard d.meters.isFinite, d.meters >= 0 else { throw LogError("Invalid GPS draft distance.") }
            for fix in [d.first, d.last].compactMap({ $0 }) {
                guard fix.latitude.isFinite, fix.longitude.isFinite, abs(fix.latitude) <= 90, abs(fix.longitude) <= 180, fix.accuracy >= 0, fix.accuracy <= 50 else { throw LogError("Invalid GPS draft coordinates.") }
            }
        }
    }
    static func mergeRecords<T: Record>(_ current: [T], _ imported: [T]) -> [T] {
        var values = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for item in imported where values[item.id] == nil || item.updatedAt > values[item.id]!.updatedAt { values[item.id] = item }
        return values.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    static func merge(_ current: Backup, _ imported: Backup) throws -> Backup {
        var b = current
        b.trips = mergeRecords(current.trips, imported.trips)
        b.vehicles = mergeRecords(current.vehicles, imported.vehicles)
        b.rates = mergeRecords(current.rates, imported.rates)
        b.purposes = mergeRecords(current.purposes, imported.purposes)
        b.frequentTrips = mergeRecords(current.frequentTrips, imported.frequentTrips)
        b.feedback = mergeRecords(current.feedback, imported.feedback)
        b.drafts = mergeRecords(current.drafts, imported.drafts)
        try validate(b)
        return b
    }
}
