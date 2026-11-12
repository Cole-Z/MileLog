import Foundation

enum DistanceCalculator {
    static let metersPerMile = 1609.344
    static func meters(_ a: GPSFix, _ b: GPSFix) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad, dLon = (b.longitude - a.longitude) * rad
        let h = pow(sin(dLat / 2), 2) + cos(a.latitude * rad) * cos(b.latitude * rad) * pow(sin(dLon / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
    }
    static func usable(_ fix: GPSFix, now: Date) -> Bool {
        fix.latitude.isFinite && fix.longitude.isFinite && abs(fix.latitude) <= 90 && abs(fix.longitude) <= 180 && fix.accuracy >= 0 && fix.accuracy <= 50 && abs(fix.timestamp.timeIntervalSince(now)) <= 15
    }
    static func segment(_ a: GPSFix, _ b: GPSFix) -> Double? {
        let seconds = b.timestamp.timeIntervalSince(a.timestamp)
        let distance = meters(a, b)
        guard seconds > 0, seconds <= 30, distance / seconds <= 70 else { return nil }
        // Small motion within the accuracy radius is treated as stationary drift.
        return distance < max(3, min(a.accuracy, b.accuracy) * 0.5) ? 0 : distance
    }
}
enum Validation {
    static func trip(_ d: TripDetails) throws {
        guard Day.date(d.day) != nil else { throw LogError("Enter a valid trip date.") }
        guard !d.start.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !d.end.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LogError("Enter both the start and end locations.") }
        guard d.category != .business || !d.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LogError("Business trips need a business purpose.") }
        guard d.miles.isFinite, d.miles > 0, d.totalMiles.isFinite else { throw LogError("Miles must be greater than zero.") }
        guard d.parking >= 0, d.tolls >= 0 else { throw LogError("Parking and tolls cannot be negative.") }
        for value in [d.odometerStart, d.odometerEnd].compactMap({ $0 }) { guard value.isFinite, value >= 0 else { throw LogError("Odometer readings must be positive numbers.") } }
        if let a = d.odometerStart, let b = d.odometerEnd, b < a { throw LogError("End odometer cannot be less than start odometer.") }
        for p in [d.start, d.end] {
            if let lat = p.latitude { guard lat.isFinite, abs(lat) <= 90 else { throw LogError("Invalid latitude.") } }
            if let lon = p.longitude { guard lon.isFinite, abs(lon) <= 180 else { throw LogError("Invalid longitude.") } }
            guard (p.latitude == nil) == (p.longitude == nil) else { throw LogError("Incomplete coordinates.") }
        }
    }
    static func rate(_ rate: MileageRate, others: [MileageRate]) throws {
        guard rate.cents >= 0, Day.date(rate.startDay) != nil, Day.date(rate.endDay) != nil, rate.startDay <= rate.endDay,
              rate.startDay.hasPrefix("\(rate.taxYear)-"), rate.endDay.hasPrefix("\(rate.taxYear)-"), rate.category != .personal else { throw LogError("Check the rate, year and date range. Both dates must be in the tax year.") }
        guard !others.contains(where: { $0.id != rate.id && $0.category == rate.category && $0.employer == rate.employer && $0.startDay <= rate.endDay && rate.startDay <= $0.endDay }) else { throw LogError("This rate overlaps another rate for the same category and rate type.") }
    }
    static func vehicle(_ v: Vehicle) throws {
        guard !v.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LogError("Give the vehicle a name.") }
        guard Set(v.years.map(\.year)).count == v.years.count else { throw LogError("Only one odometer record per year is allowed.") }
        for y in v.years {
            guard (1900...2200).contains(y.year), y.start.isFinite, y.start >= 0, y.end == nil || (y.end!.isFinite && y.end! >= y.start) else { throw LogError("Check yearly odometer readings; end must be at least start.") }
        }
    }
}
enum RateLookup {
    static func rate(for d: TripDetails, rates: [MileageRate], employer: Bool = false) -> MileageRate? {
        guard d.category != .personal else { return nil }
        let matches = rates.filter { $0.category == d.category && $0.employer == employer && $0.startDay <= d.day && d.day <= $0.endDay && String($0.taxYear) == String(d.day.prefix(4)) }
        return matches.count == 1 ? matches.first : nil
    }
    static func amount(for d: TripDetails, rates: [MileageRate], employer: Bool = false) -> Decimal? {
        if d.category == .personal { return 0 }
        guard let r = rate(for: d, rates: rates, employer: employer) else { return nil }
        let miles = Decimal(string: String(d.totalMiles), locale: Locale(identifier: "en_US_POSIX")) ?? 0
        var raw = miles * r.cents / 100, result = Decimal()
        NSDecimalRound(&result, &raw, 2, .plain)
        return result
    }
}
struct Totals {
    var miles = 0.0
    var businessMiles = 0.0
    var mileageAmount: Decimal = 0
    var parking: Decimal = 0
    var tolls: Decimal = 0
    var missingRates = 0
    init(trips: [Trip], rates: [MileageRate], prefix: String, employer: Bool = false) {
        for t in trips where t.deletedAt == nil && t.details.day.hasPrefix(prefix) && t.details.category != .personal {
            let d = t.details
            miles += d.totalMiles
            if d.category == .business { businessMiles += d.totalMiles }
            if let amount = RateLookup.amount(for: d, rates: rates, employer: employer) { mileageAmount += amount } else { missingRates += 1 }
            parking += d.parking; tolls += d.tolls
        }
    }
    static func businessUse(vehicle: Vehicle, year: VehicleYear, trips: [Trip]) -> Double? {
        guard let end = year.end, end > year.start else { return nil }
        let business = trips.filter { $0.deletedAt == nil && $0.details.vehicleID == vehicle.id && $0.details.category == .business && $0.details.day.hasPrefix("\(year.year)-") }.reduce(0) { $0 + $1.details.totalMiles }
        return business / (end - year.start) * 100
    }
}
enum CSVExporter {
    static let headers = ["Date", "Vehicle", "Start Location", "End Location", "Business Purpose", "Category", "Miles", "Odometer Start", "Odometer End", "Rate", "Amount", "Parking", "Tolls", "Notes", "Recorded Via", "Created At", "Last Edited At"]
    static func cell(_ text: String) -> String {
        // Protect spreadsheet users against formulas in user-entered text.
        let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first
        let safe = first.map { "=+-@".contains($0) } == true || text.hasPrefix("\t") || text.hasPrefix("\r") ? "'" + text : text
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    static func number(_ value: Double) -> String { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value) }
    static func decimal(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    static func export(_ backup: Backup, employer: Bool = false) -> String {
        let iso = ISO8601DateFormatter()
        var rows = [headers.map(cell).joined(separator: ",")]
        for t in backup.trips.filter({ $0.deletedAt == nil }).sorted(by: { $0.details.day < $1.details.day }) {
            let d = t.details
            let rate = RateLookup.rate(for: d, rates: backup.rates, employer: employer)
            let amount = RateLookup.amount(for: d, rates: backup.rates, employer: employer)
            let note = d.notes + (d.roundTrip ? "\nRound trip; listed endpoint is turnaround destination. Miles include return." : "")
            let cells: [String] = [d.day, backup.vehicles.first(where: { $0.id == d.vehicleID })?.name ?? "", d.start.text, d.end.text, d.purpose, d.category.rawValue, number(d.totalMiles), d.odometerStart.map(number) ?? "", d.odometerEnd.map(number) ?? "", rate.map { decimal($0.cents / 100) } ?? "", amount.map(decimal) ?? "", decimal(d.parking), decimal(d.tolls), note, d.method.rawValue, iso.string(from: t.createdAt), iso.string(from: t.updatedAt)]
            rows.append(cells.map(cell).joined(separator: ","))
        }
        return "\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n"
    }
}

/// Keep an anchor until movement exceeds uncertainty, while checking time/speed
/// against every consecutive fix. Small real movements can then accumulate.
struct DistanceAccumulator {
    private var previous: GPSFix?
    private var anchor: GPSFix?
    mutating func reset() { previous = nil; anchor = nil }
    mutating func add(_ fix: GPSFix) -> (meters: Double, gap: Bool) {
        defer { previous = fix }
        guard let previous, let anchor else { self.anchor = fix; return (0, false) }
        guard DistanceCalculator.segment(previous, fix) != nil else {
            self.anchor = fix
            return (0, true)
        }
        let displacement = DistanceCalculator.meters(anchor, fix)
        let threshold = max(5, max(anchor.accuracy, fix.accuracy) * 0.75)
        guard displacement >= threshold else { return (0, false) }
        self.anchor = fix
        return (displacement, false)
    }
}

enum ReportPeriod: String, CaseIterable, Identifiable {
    case month = "Month", year = "Year", all = "All dates", custom = "Custom"
    var id: String { rawValue }
}
struct ReportSelection {
    var period: ReportPeriod = .month
    var anchor = Date()
    var start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    var end = Date()
    var category: Category? = .business
    var vehicleID: UUID?
    var employer = false
    var valid: Bool { period != .custom || Day.string(start) <= Day.string(end) }
    func includes(_ trip: Trip) -> Bool {
        let d = trip.details
        guard trip.deletedAt == nil, valid,
              category == nil || d.category == category,
              vehicleID == nil || d.vehicleID == vehicleID else { return false }
        switch period {
        case .month: return d.day.hasPrefix(String(Day.string(anchor).prefix(7)))
        case .year: return d.day.hasPrefix(String(Day.string(anchor).prefix(4)))
        case .all: return true
        case .custom: return d.day >= Day.string(start) && d.day <= Day.string(end)
        }
    }
    var label: String {
        switch period {
        case .month: return anchor.formatted(.dateTime.month(.wide).year())
        case .year: return String(Day.string(anchor).prefix(4))
        case .all: return "All dates"
        case .custom: return "\(Day.string(start)) – \(Day.string(end))"
        }
    }
}
