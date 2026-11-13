import Foundation
import Testing
import SwiftData
@testable import MileLogCore

private func entry(_ miles: Double = 1.729, day: String = "2026-11-01") -> TripDetails {
    var d = TripDetails(); d.day = day; d.start.text = "Office"; d.end.text = "Acme, Main Street"
    d.purpose = "Client meeting"; d.miles = miles; return d
}
private func businessRate(_ cents: Decimal, start: String, end: String) -> MileageRate {
    var r = MileageRate(); r.cents = cents; r.taxYear = Int(start.prefix(4))!; r.startDay = start; r.endDay = end; return r
}
private let rates = [businessRate(70, start: "2025-01-01", end: "2025-12-31"), businessRate(72.5, start: "2026-01-01", end: "2026-06-30"), businessRate(76, start: "2026-07-01", end: "2026-12-31")]
private func saved(_ d: TripDetails) -> Trip {
    var t = Trip(); t.details = d; t.history = [TripEditEvent(action: "Created", details: d)]; return t
}

struct QualityRateTests {
    @MainActor @Test func bundledRatesMatchPublishedPeriods() throws {
        let store = try LogStore(inMemory: true)
        for (day, business, medical) in [("2025-12-31", Decimal(70), Decimal(21)), ("2026-01-01", Decimal(string: "72.5")!, Decimal(string: "20.5")!), ("2026-06-30", Decimal(string: "72.5")!, Decimal(string: "20.5")!), ("2026-07-01", Decimal(76), Decimal(string: "23.5")!), ("2026-12-31", Decimal(76), Decimal(string: "23.5")!)] {
            var details = entry(1, day: day)
            #expect(RateLookup.rate(for: details, rates: store.data.rates)?.cents == business)
            for category in [Category.medical, .moving] {
                details.category = category
                #expect(RateLookup.rate(for: details, rates: store.data.rates)?.cents == medical)
            }
            details.category = .charitable
            #expect(RateLookup.rate(for: details, rates: store.data.rates)?.cents == 14)
        }
    }
    @Test(arguments: [("2025-12-31", "0.70"), ("2026-06-30", "0.73"), ("2026-07-01", "0.76"), ("2026-12-31", "0.76")])
    func boundaries(_ example: (String, String)) {
        #expect(RateLookup.amount(for: entry(1, day: example.0), rates: rates) == Decimal(string: example.1))
    }
    @Test func fullPrecisionAndRowRounding() {
        #expect(RateLookup.amount(for: entry(), rates: rates) == Decimal(string: "1.31"))
        #expect(RateLookup.amount(for: entry(1.7), rates: rates) == Decimal(string: "1.29"))
        #expect(RateLookup.amount(for: entry(0.01), rates: rates) == Decimal(string: "0.01"))
        #expect(RateLookup.amount(for: entry(0.001), rates: rates) == 0)
        let exact = 1.729123456789
        #expect(Recordkeeping.retainedDistance(stored: exact, displayed: "1.729", entered: "1.729", parsed: 1.729) == exact)
        var b = Backup(); b.rates = rates; b.trips = [saved(entry(1, day: "2026-06-30")), saved(entry(1, day: "2026-06-30"))]
        #expect(MileageReport(backup: b).total == Decimal(string: "1.46"))
    }
    @Test func snapshotsAndJurisdiction() {
        var t = saved(entry())
        Recordkeeping.snapshotRates(&t, rates: rates, note: "Test")
        var changed = rates; changed[2].cents = 99
        #expect(RateLookup.amount(for: t, rates: changed) == Decimal(string: "1.31"))
        Recordkeeping.snapshotRates(&t, rates: changed, note: "Explicit refresh")
        #expect(RateLookup.amount(for: t, rates: changed) == Decimal(string: "1.71"))
        var nonUS = entry(); nonUS.jurisdiction = "CA"
        #expect(RateLookup.rate(for: nonUS, rates: rates) == nil)
        #expect(RateLookup.amount(for: entry(), rates: rates, employer: true) == nil)
    }
    @Test func incompleteRowsRemainVisible() throws {
        var d = entry(); d.status = .incomplete; d.purpose = ""; d.end.text = "41.0, -87.0"
        try Validation.trip(d)
        var b = Backup(); b.rates = rates; b.trips = [saved(d), saved(entry())]
        let report = MileageReport(backup: b)
        #expect(report.rows.count == 2 && report.incomplete == 1)
        #expect(report.total == Decimal(string: "1.31"))
        #expect(CSVExporter.export(b).contains("Incomplete"))
        d.status = .complete
        #expect(throws: (any Error).self) { try Validation.trip(d) }
    }
    @Test func annualCompleteness() {
        var v = Vehicle(name: "Work car")
        v.years = [VehicleYear(year: 2025, start: 1000, end: 11000)]
        var d = entry(1000, day: "2025-06-01"); d.vehicleID = v.id
        #expect(AnnualVehicleSummary(vehicle: v, year: 2025, trips: [saved(d)], today: "2026-01-01").annualMiles == nil)
        v.years[0].startDay = "2025-01-01"; v.years[0].endDay = "2025-12-31"
        v.years[0].startRecorded = true; v.years[0].fullYearConfirmed = true
        let report = AnnualVehicleSummary(vehicle: v, year: 2025, trips: [saved(d)], today: "2026-01-01")
        #expect(report.annualMiles == 10000 && report.businessPercent == 10)
        #expect(AnnualVehicleSummary(vehicle: v, year: 2025, trips: [saved(d)], today: "2025-11-01").annualMiles == nil)
    }
}

struct QualityGPSTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func fix(_ meters: Double, _ seconds: Double, accuracy: Double = 5) -> GPSFix {
        GPSFix(latitude: 0, longitude: meters / 111_194.927, accuracy: accuracy, timestamp: now.addingTimeInterval(seconds))
    }
    @Test(arguments: [6.0, 50.0]) func walkingAndDriving(_ step: Double) {
        var accumulator = DistanceAccumulator(); var total = 0.0
        for i in 0...10 { total += accumulator.add(fix(Double(i) * step, Double(i) * 5)).meters }
        #expect(abs(total - step * 10) < 0.1)
    }
    @Test func stationaryDuplicateOutlierAndReset() {
        var accumulator = DistanceAccumulator()
        _ = accumulator.add(fix(0, 0))
        for i in 1...10 { #expect(accumulator.add(fix(Double(i % 3), Double(i))).meters == 0) }
        #expect(!accumulator.add(fix(100, 5)).accepted)
        #expect(!accumulator.add(fix(100, 10)).accepted)
        #expect(!accumulator.add(fix(10000, 11)).accepted)
        let next = accumulator.add(fix(20, 12))
        #expect(next.accepted && abs(next.meters - 20) < 0.1)
        accumulator.reset()
        #expect(accumulator.add(fix(3000, 15)).meters == 0)
        let gap = accumulator.add(fix(5000, 100))
        #expect(gap.gap && gap.meters == 0)
    }
    @Test func stalePoorAndFutureSamples() {
        #expect(!DistanceCalculator.usable(fix(0, -16), now: now))
        #expect(!DistanceCalculator.usable(fix(0, 2), now: now))
        #expect(!DistanceCalculator.usable(fix(0, 0, accuracy: 80), now: now))
        #expect(DistanceCalculator.usable(fix(0, 0), now: now))
        #expect(!DistanceCalculator.usable(fix(0, -2), now: now, notBefore: now.addingTimeInterval(-1)))
        #expect(DistanceCalculator.usable(fix(0, 0), now: now, notBefore: now.addingTimeInterval(-1)))
    }
}

struct QualityPersistenceTests {
    @Test func csvAnnualReadingsRemainExplicitAndIncompleteTotalsStayBlank() throws {
        var vehicle = Vehicle(name: "Work car")
        vehicle.years = [VehicleYear(year: 2025, start: 1000, end: 11000)]
        var details = entry(10, day: "2025-06-01"); details.vehicleID = vehicle.id
        var backup = Backup(); backup.vehicles = [vehicle]; backup.trips = [saved(details)]
        func field(_ name: String, in backup: Backup) throws -> String {
            let rows = parseCSV(CSVExporter.export(backup))
            let index = try #require(rows[0].firstIndex(of: name))
            return rows[1][index]
        }
        #expect(try field("Annual Vehicle Miles", in: backup).isEmpty)
        #expect(try field("Annual Beginning Odometer", in: backup).isEmpty)
        #expect(try field("Annual Mileage Status", in: backup).contains("unconfirmed"))
        backup.vehicles[0].years[0].startRecorded = true
        backup.vehicles[0].years[0].startDay = "2025-01-01"
        backup.vehicles[0].years[0].endDay = "2025-12-31"
        backup.vehicles[0].years[0].fullYearConfirmed = true
        #expect(try field("Annual Vehicle Miles", in: backup) == "10000.0")
        #expect(try field("Annual Beginning Odometer", in: backup) == "1000.0")
        #expect(try field("Annual Ending Date", in: backup) == "2025-12-31")
    }
    @Test func oldBackupsAndUnknownVersions() throws {
        var b = Backup(); b.version = 1; b.rates = rates; b.trips = [saved(entry())]
        let legacy = JSONEncoder(); legacy.dateEncodingStrategy = .iso8601
        let decoded = try BackupService.decode(legacy.encode(b))
        let upgraded = Recordkeeping.migrate(decoded)
        #expect(upgraded.version == 3 && upgraded.trips[0].gpsEvidence == nil)
        #expect(upgraded.trips[0].details.miles == b.trips[0].details.miles)
        #expect(RateLookup.amount(for: upgraded.trips[0], rates: []) == Decimal(string: "1.31"))
        let roundTrip = try BackupService.decode(BackupService.encode(upgraded))
        #expect(roundTrip.trips[0].ratesCapturedAt == upgraded.trips[0].ratesCapturedAt)
        b.version = 99
        #expect(throws: (any Error).self) { try BackupService.encode(b) }
        #expect(throws: (any Error).self) { try BackupService.decode(legacy.encode(b)) }
    }
    @MainActor @Test func persistenceEvidenceCorrectionsAndRestore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LogStore(inMemory: true, fileDirectory: directory)
        var draft = RecordingDraft(); draft.meters = 2782.5123456
        draft.startDay = "2026-11-01"; draft.startTimeZoneID = "America/Chicago"
        draft.endedAt = draft.createdAt.addingTimeInterval(300); draft.endTimeZoneID = "America/Chicago"; draft.ended = true
        draft.first = GPSFix(latitude: 41, longitude: -87, accuracy: 5, timestamp: draft.createdAt)
        draft.last = GPSFix(latitude: 41.01, longitude: -87.01, accuracy: 5, timestamp: draft.endedAt!)
        try store.saveDraft(draft)
        let oldBackup = store.data
        var d = draft.recordedDetails; d.end.text = "Acme office"; d.purpose = "Client visit"; d.status = .complete
        try store.saveTrip(nil, details: d, draftID: draft.id)
        let first = store.trips[0]
        #expect(first.gpsEvidence?.meters == draft.meters)
        #expect(first.details.miles == draft.meters / DistanceCalculator.metersPerMile)
        var changed = d; changed.miles += 1
        #expect(throws: (any Error).self) { try store.saveTrip(first, details: changed) }
        changed.correctionReason = "Odometer shows mileage missed during weak reception"
        try store.saveTrip(first, details: changed)
        let reopened = try LogStore(inMemory: true, existingContainer: store.container, fileDirectory: directory)
        #expect(reopened.trips[0].gpsEvidence == first.gpsEvidence)
        #expect(reopened.trips[0].history.count == 2)
        try reopened.restore(oldBackup)
        try reopened.restore(oldBackup)
        #expect(reopened.trips.count == 1 && reopened.data.drafts.isEmpty)
        #expect(throws: (any Error).self) { try reopened.saveDraft(draft) }
        let portable = try BackupService.decode(BackupService.encode(reopened.data))
        #expect(portable.trips[0].gpsEvidence == first.gpsEvidence)
        #expect(portable.trips[0].details.correctionReason == changed.correctionReason)
        let csv = CSVExporter.export(portable)
        #expect(csv.contains(String(draft.meters)))
        #expect(csv.contains("America/Chicago"))
    }
    @MainActor @Test func populatedLegacyStoreUpgradeAndOdometerHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LogStore(inMemory: true, fileDirectory: directory)
        var old = store.data; old.preferences?.schemaVersion = 2
        old.trips = [saved(entry())]; try store.commit(old)
        let reopened = try LogStore(inMemory: true, existingContainer: store.container, fileDirectory: directory)
        #expect(reopened.trips.count == 1 && reopened.preferences.schemaVersion == 3)
        #expect(reopened.trips[0].ratesCapturedAt != nil)
        var vehicle = Vehicle(name: "Work car"); vehicle.years = [VehicleYear(year: 2025, start: 1000, end: 12000)]
        try reopened.saveVehicle(vehicle)
        vehicle = reopened.data.vehicles[0]; vehicle.years[0].end = 12500
        #expect(throws: (any Error).self) { try reopened.saveVehicle(vehicle) }
        vehicle.odometerCorrectionReason = "Corrected transcription from year-end photo"
        try reopened.saveVehicle(vehicle)
        #expect(reopened.data.vehicles[0].odometerHistory?.count == 2)
        vehicle = reopened.data.vehicles[0]
        vehicle.years[0].startRecorded = true; vehicle.years[0].startDay = "2025-01-01"; vehicle.years[0].endDay = "2025-12-31"; vehicle.years[0].fullYearConfirmed = true
        vehicle.businessServiceDay = "2025-01-15"; vehicle.businessServiceOdometer = 1500
        try reopened.saveVehicle(vehicle)
        let portable = try BackupService.decode(BackupService.encode(reopened.data))
        #expect(portable.vehicles[0].years[0].fullYearConfirmed == true)
        #expect(portable.vehicles[0].businessServiceOdometer == 1500)
        #expect(portable.vehicles[0].odometerHistory?.count == 3)
    }

    @Test func restorePreservesOriginalEvidenceAndBranchHistory() throws {
        var draft = RecordingDraft(); draft.meters = 1234.567
        var trip = saved(entry()); trip.gpsEvidence = GPSRecordingEvidence(draft); trip.originalDetails = trip.details
        var current = Backup(); current.trips = [trip]
        var incoming = current
        incoming.trips[0].updatedAt = trip.updatedAt.addingTimeInterval(10)
        incoming.trips[0].gpsEvidence = nil; incoming.trips[0].originalDetails = nil
        incoming.trips[0].details.notes = "Newer edit from another copy"
        incoming.trips[0].history = [TripEditEvent(action: "Edited", details: incoming.trips[0].details)]
        let merged = try BackupService.merge(current, incoming)
        #expect(merged.trips[0].gpsEvidence == trip.gpsEvidence)
        #expect(merged.trips[0].originalDetails == trip.originalDetails)
        #expect(merged.trips[0].details.notes == incoming.trips[0].details.notes)
        #expect(merged.trips[0].history.count == 2)
        #expect(try BackupService.merge(merged, incoming).trips[0].history.count == 2)
        draft.meters = 5000; incoming.trips[0].gpsEvidence = GPSRecordingEvidence(draft)
        #expect(throws: (any Error).self) { try BackupService.merge(current, incoming) }
    }

    @Test func csvReconcilesAndEscapesMultilineRecords() throws {
        var details = entry(); details.notes = "Quoted \"note\"\nSecond line, comma"
        details.start = Place(text: "=1+1", latitude: 41, longitude: -87)
        details.parking = 2.25; details.tolls = 1.50
        details.parkingDescription = "Client garage"; details.tollsDescription = "Bridge"; details.evidenceReference = "Receipt A"
        var b = Backup(); b.rates = rates; b.trips = [saved(details), saved(entry(1, day: "2026-06-30"))]
        var incomplete = entry(3); incomplete.status = .incomplete; incomplete.purpose = ""
        b.trips.append(saved(incomplete))
        var personal = entry(4); personal.category = .personal; b.trips.append(saved(personal))
        b = Recordkeeping.migrate(b)
        let restored = try BackupService.decode(BackupService.encode(b))
        #expect(restored.trips[0].details == details)
        let report = MileageReport(backup: restored)
        let rows = parseCSV(CSVExporter.export(restored))
        let header = try #require(rows.first)
        #expect(header == CSVExporter.headers)
        #expect(rows.count == 5)
        for row in rows { #expect(row.count == header.count) }
        let amountIndex = try #require(header.firstIndex(of: "Amount"))
        let idIndex = try #require(header.firstIndex(of: "Trip ID"))
        let noteIndex = try #require(header.firstIndex(of: "Notes"))
        let csvTotal = rows.dropFirst().reduce(Decimal(0)) { $0 + (Decimal(string: $1[amountIndex]) ?? 0) }
        #expect(csvTotal == report.total && csvTotal == Decimal(string: "2.04"))
        let original = try #require(rows.dropFirst().first { $0[idIndex] == b.trips[0].id.uuidString })
        #expect(original[noteIndex] == details.notes)
        #expect(original[2] == "'=1+1")
        #expect(original[23] == "-87.0")
        #expect(original[6] == "1.729")
        #expect(original[11] == "2.25" && original[12] == "1.5")
        #expect(report.ratePeriods.count == 2)
    }
}

/// Independent CSV reader exercises quotes, embedded newlines, UTF-8 BOM and CRLF.
private func parseCSV(_ text: String) -> [[String]] {
    let characters = Array(text.replacingOccurrences(of: "\u{FEFF}", with: ""))
    var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, i = 0
    while i < characters.count {
        let c = characters[i]
        if c == "\"" {
            if quoted && i + 1 < characters.count && characters[i + 1] == "\"" { field.append("\""); i += 1 }
            else { quoted.toggle() }
        } else if c == "," && !quoted { row.append(field); field = "" }
        else if (c == "\r\n" || c == "\n" || c == "\r") && !quoted {
            row.append(field); rows.append(row); row = []; field = ""
        } else { field.append(c) }
        i += 1
    }
    if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
    return rows
}
