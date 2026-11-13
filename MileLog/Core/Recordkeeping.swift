import Foundation

enum TripStatus: String, Codable, Sendable { case incomplete = "Incomplete", complete = "Complete" }
struct GPSRecordingEvidence: Codable, Equatable, Sendable {
    let meters: Double
    let first: GPSFix?
    let last: GPSFix?
    let startedAt: Date
    let endedAt: Date?
    let startTimeZoneID: String?
    let endTimeZoneID: String?
    let interrupted: Bool
    let acceptedFixes: Int?
    let rejectedFixes: Int?
    let interruptionReasons: [String]?
    init(_ draft: RecordingDraft) {
        meters = draft.meters; first = draft.first; last = draft.last
        startedAt = draft.createdAt; endedAt = draft.endedAt
        startTimeZoneID = draft.startTimeZoneID; endTimeZoneID = draft.endTimeZoneID
        interrupted = draft.interrupted; acceptedFixes = draft.acceptedFixes; rejectedFixes = draft.rejectedFixes
        interruptionReasons = draft.interruptionReasons
    }
}
struct OdometerEdit: Codable, Identifiable, Sendable {
    var id = UUID()
    var at = Date()
    var years: [VehicleYear]
    var serviceDay: String?
    var serviceOdometer: Double?
    var reason: String
}

enum Recordkeeping {
    static func isCoordinateLabel(_ value: String) -> Bool {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.count == 2 && Double(parts[0]) != nil && Double(parts[1]) != nil
    }
    static func issues(_ d: TripDetails) -> [String] {
        var issues: [String] = []
        if d.start.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Add an origin") }
        if d.end.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (d.category == .business && isCoordinateLabel(d.end.text)) {
            issues.append("Name the destination or business location")
        }
        if d.category == .business && d.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Add a business purpose") }
        if !d.totalMiles.isFinite || d.totalMiles <= 0 { issues.append("Enter a positive distance") }
        return issues
    }
    static func isComplete(_ d: TripDetails) -> Bool { d.status != .incomplete && issues(d).isEmpty }
    static func retainedDistance(stored: Double, displayed: String, entered: String, parsed: Double) -> Double {
        entered == displayed ? stored : parsed
    }
    static func snapshotRates(_ trip: inout Trip, rates: [MileageRate], note: String) {
        trip.irsRate = RateLookup.rate(for: trip.details, rates: rates)
        trip.employerRate = RateLookup.rate(for: trip.details, rates: rates, employer: true)
        trip.ratesCapturedAt = Date(); trip.rateCaptureNote = note
    }
    static func migrate(_ input: Backup) -> Backup {
        var backup = input
        backup.version = 3
        if var preferences = backup.preferences { preferences.schemaVersion = 3; backup.preferences = preferences }
        for i in backup.trips.indices where backup.trips[i].ratesCapturedAt == nil {
            snapshotRates(&backup.trips[i], rates: input.rates, note: "Captured from the existing rate table during upgrade/import; original applied rate was not stored.")
        }
        return backup
    }
    static func plural(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : (plural ?? singular + "s"))"
    }
}

extension MileageRate { var effectiveJurisdiction: String { jurisdiction ?? "US" } }
extension TripDetails { var effectiveJurisdiction: String { jurisdiction ?? "US" } }

struct AnnualVehicleSummary {
    let vehicleID: UUID
    let vehicleName: String
    let year: Int
    let businessMiles: Double
    let incompleteTrips: Int
    let periodMiles: Double?
    let annualMiles: Double?
    let note: String
    let beginningOdometer: Double?
    let endingOdometer: Double?
    let beginningDay: String?
    let endingDay: String?
    init(vehicle: Vehicle, year: Int, trips: [Trip], today: String = Day.string(Date())) {
        vehicleID = vehicle.id; vehicleName = vehicle.name; self.year = year
        let readings = vehicle.years.first { $0.year == year }
        beginningOdometer = readings?.startRecorded == true ? readings?.start : nil
        endingOdometer = readings?.end
        beginningDay = readings?.startDay; endingDay = readings?.endDay
        let matching = trips.filter { $0.deletedAt == nil && $0.details.vehicleID == vehicle.id && $0.details.day.hasPrefix("\(year)-") && $0.details.category == .business }
        businessMiles = matching.reduce(0) { $0 + $1.details.totalMiles }
        incompleteTrips = matching.filter { !Recordkeeping.isComplete($0.details) }.count
        if let readings = vehicle.years.first(where: { $0.year == year }), let end = readings.end, end >= readings.start {
            periodMiles = end - readings.start
            let complete = readings.startRecorded == true && readings.fullYearConfirmed == true &&
                readings.startDay == "\(year)-01-01" && readings.endDay == "\(year)-12-31" && "\(year)-12-31" <= today
            annualMiles = complete ? end - readings.start : nil
            note = complete ? (businessMiles > end - readings.start ? "Business miles exceed the annual odometer total. Review these records; no business-use percentage is calculated." : "Annual total from user-entered odometers; not independently verified.") : "Partial period or unconfirmed dates. Annual mileage is unavailable."
        } else {
            periodMiles = nil; annualMiles = nil
            note = "Beginning/end readings are missing. Annual mileage is unavailable."
        }
    }
    var businessPercent: Double? {
        guard let annualMiles, annualMiles > 0, incompleteTrips == 0, businessMiles <= annualMiles else { return nil }
        return businessMiles / annualMiles * 100
    }
}

struct ReportRow {
    let trip: Trip
    let vehicle: String
    let rate: MileageRate?
    let amount: Decimal?
    let issues: [String]
    init(trip: Trip, backup: Backup, employer: Bool) {
        self.trip = trip
        vehicle = backup.vehicles.first { $0.id == trip.details.vehicleID }?.name ?? "Unassigned"
        rate = RateLookup.rate(for: trip, rates: backup.rates, employer: employer)
        issues = Recordkeeping.issues(trip.details)
        amount = Recordkeeping.isComplete(trip.details) ? RateLookup.amount(for: trip, rates: backup.rates, employer: employer) : nil
    }
    var status: String { Recordkeeping.isComplete(trip.details) ? "Required details supplied" : "Incomplete — " + (issues.isEmpty ? "review needed" : issues.joined(separator: "; ")) }
}
struct MileageReport {
    let rows: [ReportRow]
    let annual: [AnnualVehicleSummary]
    let total: Decimal
    let incomplete: Int
    let missingRates: Int
    let unassignedVehicles: Int
    init(backup: Backup, employer: Bool = false, selected: [Trip]? = nil, years: [Int]? = nil, vehicleIDs: Set<UUID>? = nil) {
        let trips = (selected ?? backup.trips).filter { $0.deletedAt == nil }.sorted { $0.details.day == $1.details.day ? $0.id.uuidString < $1.id.uuidString : $0.details.day < $1.details.day }
        rows = trips.map { ReportRow(trip: $0, backup: backup, employer: employer) }
        total = rows.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
        incomplete = rows.filter { !Recordkeeping.isComplete($0.trip.details) }.count
        missingRates = rows.filter { Recordkeeping.isComplete($0.trip.details) && $0.trip.details.category != .personal && $0.rate == nil }.count
        unassignedVehicles = trips.filter { $0.details.vehicleID == nil }.count
        let reportYears = years ?? Array(Set(trips.compactMap { Int($0.details.day.prefix(4)) })).sorted()
        annual = backup.vehicles.filter { vehicleIDs?.contains($0.id) ?? true }.flatMap { vehicle in
            reportYears.map { AnnualVehicleSummary(vehicle: vehicle, year: $0, trips: backup.trips) }
        }
    }
}

extension RecordingDraft {
    var recordedDetails: TripDetails {
        var d = TripDetails()
        d.day = startDay ?? Day.string(createdAt); d.method = .gps; d.status = .incomplete
        d.miles = meters / DistanceCalculator.metersPerMile
        d.start = first?.place ?? Place(); d.end = last?.place ?? Place(); d.vehicleID = vehicleID
        d.startedAt = createdAt; d.endedAt = endedAt
        d.startTimeZoneID = startTimeZoneID; d.endTimeZoneID = endTimeZoneID
        if interrupted { d.notes = "Recording has gaps or was recovered. Verify distance before relying on this record." }
        return d
    }
}

extension ReportSelection {
    func years(in backup: Backup) -> [Int] {
        switch period {
        case .month, .year: return Int(Day.string(anchor).prefix(4)).map { [$0] } ?? []
        case .custom:
            guard valid, let first = Int(Day.string(start).prefix(4)), let last = Int(Day.string(end).prefix(4)), last - first <= 300 else { return [] }
            return Array(first...last)
        case .all:
            return Array(Set(backup.trips.compactMap { Int($0.details.day.prefix(4)) } + backup.vehicles.flatMap { $0.years.map(\.year) })).sorted()
        }
    }
}
extension Trip {
    var displayTitle: String {
        let destination = details.end.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return destination.isEmpty || Recordkeeping.isCoordinateLabel(destination)
            ? (details.purpose.isEmpty ? "Destination needs a label" : details.purpose) : destination
    }
    func matchesSearch(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [details.start.text, details.end.text, details.purpose, details.notes].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
extension MileageReport {
    var ratePeriods: [String] {
        Array(Set(rows.compactMap { row in
            row.rate.map { "\($0.category.rawValue) · \($0.effectiveJurisdiction) · \(CSVExporter.decimal($0.cents))¢/mi · \($0.startDay)–\($0.endDay)" }
        })).sorted()
    }
}
