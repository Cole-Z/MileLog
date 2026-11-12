import Foundation
import Testing
@testable import MileLogCore

private func details(day: String = "2026-07-01", miles: Double = 10, category: MileLogCore.Category = .business) -> TripDetails {
    var d = TripDetails(); d.day = day; d.start.text = "Office"; d.end.text = "Client"; d.purpose = "Client meeting"; d.miles = miles; d.category = category; return d
}
private func rate(start: String = "2026-07-01", end: String = "2026-12-31", cents: Decimal = 76, employer: Bool = false) -> MileageRate {
    var r = MileageRate(); r.taxYear = 2026; r.startDay = start; r.endDay = end; r.cents = cents; r.employer = employer; return r
}
private func trip(_ d: TripDetails) -> Trip { var t = Trip(); t.details = d; t.history = [TripEditEvent(action: "Created", details: d)]; return t }
struct DistanceTests {
    @Test func knownDistanceAndConversion() {
        let a = GPSFix(latitude: 0, longitude: 0, accuracy: 5, timestamp: Date())
        let b = GPSFix(latitude: 0, longitude: 1, accuracy: 5, timestamp: Date())
        #expect(abs(DistanceCalculator.meters(a, b) - 111_194.927) < 1)
        #expect(DistanceCalculator.metersPerMile == 1609.344)
        #expect(DistanceCalculator.meters(a, a) == 0)
    }
    @Test func rejectsStalePoorAndImpossibleFixes() {
        let now = Date()
        var a = GPSFix(latitude: 40, longitude: -90, accuracy: 10, timestamp: now)
        #expect(DistanceCalculator.usable(a, now: now))
        a.accuracy = 100; #expect(!DistanceCalculator.usable(a, now: now))
        a.accuracy = 10; a.timestamp = now.addingTimeInterval(-20); #expect(!DistanceCalculator.usable(a, now: now))
        let b = GPSFix(latitude: 41, longitude: -90, accuracy: 10, timestamp: now)
        #expect(DistanceCalculator.segment(a, b) == nil)
        a.timestamp = now.addingTimeInterval(-40); #expect(DistanceCalculator.segment(a, b) == nil)
        a.timestamp = now; #expect(DistanceCalculator.segment(a, a) == nil)
    }
    @Test func stationaryDriftAndRealMotion() {
        let a = GPSFix(latitude: 0, longitude: 0, accuracy: 10, timestamp: Date())
        var b = a; b.timestamp = a.timestamp.addingTimeInterval(5); b.longitude = 0.00001
        #expect(DistanceCalculator.segment(a, b) == 0)
        b.longitude = 0.001
        #expect(abs((DistanceCalculator.segment(a, b) ?? 0) - 111.195) < 0.1)
    }
}
struct RateAndTotalTests {
    @Test func inclusiveMidyearBoundaryAndMissingYear() {
        let first = rate(start: "2026-01-01", end: "2026-06-30", cents: 72.5)
        let last = rate(); let rates = [first, last]
        #expect(RateLookup.rate(for: details(day: "2026-06-30"), rates: rates)?.cents == 72.5)
        #expect(RateLookup.rate(for: details(), rates: rates)?.cents == 76)
        #expect(RateLookup.rate(for: details(day: "2026-12-31"), rates: rates)?.cents == 76)
        #expect(RateLookup.rate(for: details(day: "2027-01-01"), rates: rates) == nil)
        #expect(RateLookup.rate(for: details(), rates: rates, employer: true) == nil)
        #expect(throws: (any Error).self) { try Validation.rate(last, others: [rate()]) }
    }
    @Test func decimalRoundingEmployerAndRoundTrip() {
        var d = details(miles: 1); d.roundTrip = true
        #expect(RateLookup.amount(for: d, rates: [rate(cents: 72.5)]) == Decimal(string: "1.45"))
        d.roundTrip = false
        #expect(RateLookup.amount(for: d, rates: [rate(cents: 72.5)]) == Decimal(string: "0.73"))
        #expect(RateLookup.amount(for: d, rates: [rate(), rate(cents: 50, employer: true)], employer: true) == Decimal(string: "0.50"))
    }
    @Test func totalsExcludePersonalDeletedAndOtherYears() {
        var d = details(); d.parking = 3; d.tolls = 2
        let business = trip(d), personal = trip(details(miles: 50, category: .personal)), old = trip(details(day: "2025-07-01"))
        var deleted = trip(details()); deleted.deletedAt = Date()
        let missing = trip(details(day: "2026-01-01", miles: 5))
        let totals = Totals(trips: [business, personal, old, deleted, missing], rates: [rate()], prefix: "2026")
        #expect(totals.miles == 15); #expect(totals.mileageAmount == Decimal(string: "7.60")); #expect(totals.missingRates == 1)
        #expect(totals.parking == 3); #expect(totals.tolls == 2)
        #expect(Totals(trips: [business, missing], rates: [rate()], prefix: "2026-07").miles == 10)
    }
    @Test func annualOdometerDenominator() {
        var v = Vehicle(name: "Car"); let y = VehicleYear(year: 2025, start: 1000, end: 2000, startDay: "2025-01-01", endDay: "2025-12-31", startRecorded: true, fullYearConfirmed: true)
        v.years = [y]
        var d = details(day: "2025-07-01", miles: 100); d.vehicleID = v.id
        #expect(Totals.businessUse(vehicle: v, year: y, trips: [trip(d)]) == 10)
        #expect(Totals.businessUse(vehicle: v, year: VehicleYear(start: 0), trips: []) == nil)
    }
}
struct ValidationAndExportTests {
    @Test func requiredFieldsAndInvalidNumbers() {
        var d = details(); d.purpose = "  "
        #expect(throws: (any Error).self) { try Validation.trip(d) }
        d.category = .personal; #expect(throws: Never.self) { try Validation.trip(d) }
        d.miles = .nan; #expect(throws: (any Error).self) { try Validation.trip(d) }
        d.miles = 10; d.odometerStart = 100; d.odometerEnd = 50
        #expect(throws: (any Error).self) { try Validation.trip(d) }
        #expect(Day.date("2026-02-30") == nil)
    }
    @Test func csvEscapingFormulaProtectionAndColumns() {
        #expect(CSVExporter.cell("A, \"B\"\nC") == "\"A, \"\"B\"\"\nC\"")
        #expect(CSVExporter.cell("=1+1") == "\"'=1+1\"")
        #expect(CSVExporter.cell(" @SUM(A1)").hasPrefix("\"'"))
        var b = Backup(); b.trips = [trip(details())]; b.rates = [rate()]
        let csv = CSVExporter.export(b)
        #expect(CSVExporter.headers.contains("Original GPS Meters"))
        #expect(CSVExporter.headers.contains("Record Status"))
        #expect(csv.contains("\"0.76\",\"7.6\""))
        #expect(csv.hasSuffix("\r\n")); #expect(csv.hasPrefix("\u{FEFF}"))
        b.rates = []; #expect(CSVExporter.export(b).contains("\"10.0\",\"\",\"\",\"\",\"\""))
    }
    @Test func backupRoundtripAndSafeMerge() throws {
        var b = Backup(); b.trips = [trip(details())]; b.feedback = [FeedbackNote(text: "Issue")]; b.rates = [rate()]
        let restored = try BackupService.decode(BackupService.encode(b))
        #expect(restored.trips.first?.details == b.trips.first?.details); #expect(restored.feedback.first?.text == "Issue")
        var newer = b.trips[0]; newer.updatedAt = newer.updatedAt.addingTimeInterval(10); newer.deletedAt = Date()
        var current = b; current.trips = [newer]
        let merged = try BackupService.merge(current, b)
        #expect(merged.trips.count == 1); #expect(merged.trips[0].deletedAt != nil)
        b.version = 99; #expect(throws: (any Error).self) { try BackupService.decode(BackupService.encode(b)) }
    }
    @Test func malformedBackupAndConflictingRatesAreRejected() {
        var b = Backup(); let t = trip(details()); b.trips = [t, t]
        #expect(throws: (any Error).self) { try BackupService.validate(b) }
        b.trips = []; b.rates = [rate(), rate()]
        #expect(throws: (any Error).self) { try BackupService.validate(b) }
        #expect(throws: (any Error).self) { try BackupService.decode(Data("{}".utf8)) }
    }
}
