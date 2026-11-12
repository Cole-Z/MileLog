import Foundation

enum DistanceCalculator {
    static let metersPerMile = 1609.344
    static func meters(_ a: GPSFix, _ b: GPSFix) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad, dLon = (b.longitude - a.longitude) * rad
        let h = pow(sin(dLat / 2), 2) + cos(a.latitude * rad) * cos(b.latitude * rad) * pow(sin(dLon / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
    }
    static func usable(_ fix: GPSFix, now: Date, notBefore: Date? = nil) -> Bool {
        fix.latitude.isFinite && fix.longitude.isFinite && abs(fix.latitude) <= 90 && abs(fix.longitude) <= 180 && fix.accuracy >= 0 && fix.accuracy <= 50 && fix.timestamp.timeIntervalSince(now) >= -15 && fix.timestamp.timeIntervalSince(now) <= 1 && (notBefore == nil || fix.timestamp >= notBefore!)
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
        if d.status != .incomplete {
        guard !d.start.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !d.end.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LogError("Enter both the start and end locations.") }
        guard d.category != .business || !d.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LogError("Business trips need a business purpose.") }
        }
        if d.status == .complete, !Recordkeeping.issues(d).isEmpty { throw LogError(Recordkeeping.issues(d).joined(separator: ". ")) }
        if let start = d.startedAt, let end = d.endedAt, end < start { throw LogError("Trip end time must follow its start time.") }
        for zone in [d.startTimeZoneID, d.endTimeZoneID].compactMap({ $0 }) where TimeZone(identifier: zone) == nil { throw LogError("Unknown trip time zone.") }
        guard d.miles.isFinite, d.miles >= 0, (d.status == .incomplete || d.miles > 0), d.totalMiles.isFinite else { throw LogError("Miles must be greater than zero.") }
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
        guard !others.contains(where: { $0.id != rate.id && $0.category == rate.category && $0.employer == rate.employer && $0.effectiveJurisdiction == rate.effectiveJurisdiction && $0.startDay <= rate.endDay && rate.startDay <= $0.endDay }) else { throw LogError("This rate overlaps another rate for the same category and rate type.") }
    }
    static func vehicle(_ v: Vehicle) throws {
        guard !v.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LogError("Give the vehicle a name.") }
        guard Set(v.years.map(\.year)).count == v.years.count else { throw LogError("Only one odometer record per year is allowed.") }
        if let day = v.businessServiceDay { guard Day.date(day) != nil else { throw LogError("Enter a valid business-service date.") } }
        if let reading = v.businessServiceOdometer { guard reading.isFinite, reading >= 0 else { throw LogError("Business-service odometer must be nonnegative.") } }
        for y in v.years {
            for day in [y.startDay, y.endDay].compactMap({ $0 }) {
                guard Day.date(day) != nil, day.hasPrefix("\(y.year)-") else { throw LogError("Odometer dates must be within their tax year.") }
            }
            if let a = y.startDay, let b = y.endDay, b < a { throw LogError("End reading date must follow the start reading date.") }
            if y.fullYearConfirmed == true {
                guard y.startRecorded == true, y.end != nil, y.startDay == "\(y.year)-01-01", y.endDay == "\(y.year)-12-31", "\(y.year)-12-31" <= Day.string(Date()) else { throw LogError("A complete annual total needs confirmed January 1 and December 31 readings for a finished year.") }
            }
            guard (1900...2200).contains(y.year), y.start.isFinite, y.start >= 0, y.end == nil || (y.end!.isFinite && y.end! >= y.start) else { throw LogError("Check yearly odometer readings; end must be at least start.") }
        }
    }
}
enum RateLookup {
    static func rate(for d: TripDetails, rates: [MileageRate], employer: Bool = false) -> MileageRate? {
        guard d.category != .personal else { return nil }
        let matches = rates.filter { $0.category == d.category && $0.employer == employer && $0.effectiveJurisdiction == d.effectiveJurisdiction && $0.startDay <= d.day && d.day <= $0.endDay && String($0.taxYear) == String(d.day.prefix(4)) }
        return matches.count == 1 ? matches.first : nil
    }
    static func rate(for trip: Trip, rates: [MileageRate], employer: Bool = false) -> MileageRate? {
        if trip.ratesCapturedAt != nil { return employer ? trip.employerRate : trip.irsRate }
        return rate(for: trip.details, rates: rates, employer: employer)
    }
    static func amount(for trip: Trip, rates: [MileageRate], employer: Bool = false) -> Decimal? {
        if trip.details.category == .personal { return 0 }
        guard let selected = rate(for: trip, rates: rates, employer: employer) else { return nil }
        return amount(for: trip.details, rates: [selected], employer: employer)
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
    var incompleteTrips = 0
    init(trips: [Trip], rates: [MileageRate], prefix: String, employer: Bool = false) {
        for t in trips where t.deletedAt == nil && t.details.day.hasPrefix(prefix) && t.details.category != .personal {
            let d = t.details
            miles += d.totalMiles
            if d.category == .business { businessMiles += d.totalMiles }
            if !Recordkeeping.isComplete(d) { incompleteTrips += 1 }
            else if let amount = RateLookup.amount(for: t, rates: rates, employer: employer) { mileageAmount += amount }
            else { missingRates += 1 }
            parking += d.parking; tolls += d.tolls
        }
    }
    static func businessUse(vehicle: Vehicle, year: VehicleYear, trips: [Trip]) -> Double? {
        AnnualVehicleSummary(vehicle: vehicle, year: year.year, trips: trips).businessPercent
    }
}

/// Keep an anchor until movement exceeds uncertainty, while checking time/speed
/// against every consecutive fix. Small real movements can then accumulate.
struct DistanceAccumulator {
    private var previous: GPSFix?
    private var anchor: GPSFix?
    mutating func reset() { previous = nil; anchor = nil }
    mutating func add(_ fix: GPSFix) -> (meters: Double, gap: Bool, accepted: Bool) {
        guard fix.latitude.isFinite, fix.longitude.isFinite, abs(fix.latitude) <= 90, abs(fix.longitude) <= 180,
              fix.accuracy >= 0, fix.accuracy <= 50 else { return (0, true, false) }
        guard let previous, let anchor else { self.previous = fix; self.anchor = fix; return (0, false, true) }
        let seconds = fix.timestamp.timeIntervalSince(previous.timestamp)
        guard seconds > 0 else { return (0, false, false) }
        if seconds > 30 { self.previous = fix; self.anchor = fix; return (0, true, true) }
        guard DistanceCalculator.meters(previous, fix) / seconds <= 70 else { return (0, true, false) }
        self.previous = fix
        let displacement = DistanceCalculator.meters(anchor, fix)
        let threshold = max(5, max(anchor.accuracy, fix.accuracy) * 0.75)
        guard displacement >= threshold else { return (0, false, true) }
        self.anchor = fix
        return (displacement, false, true)
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
