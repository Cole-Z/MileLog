import Foundation

enum CSVExporter {
    static let headers = ["Date", "Vehicle", "Start Location", "End Location", "Business Purpose", "Category", "Miles", "Odometer Start", "Odometer End", "Rate", "Amount", "Parking", "Tolls", "Notes", "Recorded Via", "Created At", "Last Edited At", "Trip ID", "Start Time", "End Time", "Start Time Zone", "End Time Zone", "Origin Latitude", "Origin Longitude", "Destination Latitude", "Destination Longitude", "Original GPS Miles", "Original GPS Meters", "Original Origin Latitude", "Original Origin Longitude", "Original Destination Latitude", "Original Destination Longitude", "Correction Reason", "Record Status", "Rate Basis", "Jurisdiction", "Rate Period Start", "Rate Period End", "Rate Source", "Rate Captured At", "Parking Description", "Toll Description", "Evidence Reference", "Recording Quality"]
    static func cell(_ text: String) -> String {
        let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first
        let safe = first.map { "=+-@".contains($0) } == true || text.hasPrefix("\t") || text.hasPrefix("\r") ? "'" + text : text
        return quote(safe)
    }
    private static func quote(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    static func number(_ value: Double) -> String { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value) }
    static func precise(_ value: Double) -> String { String(value) }
    static func decimal(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    static func export(_ backup: Backup, employer: Bool = false, selected: [Trip]? = nil) -> String {
        let report = MileageReport(backup: backup, employer: employer, selected: selected)
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let numeric = Set([6,7,8,9,10,11,12,22,23,24,25,26,27,28,29,30,31])
        var rows = [headers.map(cell).joined(separator: ",")]
        for row in report.rows {
            let t = row.trip, d = t.details, gps = t.gpsEvidence
            var fields = [d.day, row.vehicle, d.start.text, d.end.text, d.purpose, d.category.rawValue]
            fields += [precise(d.totalMiles), d.odometerStart.map(precise) ?? "", d.odometerEnd.map(precise) ?? ""]
            fields += [row.rate.map { decimal($0.cents / 100) } ?? "", row.amount.map(decimal) ?? "", decimal(d.parking), decimal(d.tolls)]
            fields += [d.notes + (d.roundTrip ? "\nRound trip; miles include the return." : ""), d.method.rawValue, iso.string(from: t.createdAt), iso.string(from: t.updatedAt), t.id.uuidString]
            fields += [d.startedAt.map { iso.string(from: $0) } ?? "", d.endedAt.map { iso.string(from: $0) } ?? "", d.startTimeZoneID ?? "", d.endTimeZoneID ?? ""]
            fields += [d.start.latitude.map(precise) ?? "", d.start.longitude.map(precise) ?? "", d.end.latitude.map(precise) ?? "", d.end.longitude.map(precise) ?? ""]
            fields += [gps.map { precise($0.meters / DistanceCalculator.metersPerMile) } ?? "", gps.map { precise($0.meters) } ?? ""]
            fields += [(gps?.first?.latitude).map(precise) ?? "", (gps?.first?.longitude).map(precise) ?? "", (gps?.last?.latitude).map(precise) ?? "", (gps?.last?.longitude).map(precise) ?? ""]
            fields += [d.correctionReason ?? "", row.status, employer ? "Employer reimbursement estimate" : "IRS mileage deduction estimate", d.effectiveJurisdiction]
            fields += [row.rate?.startDay ?? "", row.rate?.endDay ?? "", row.rate?.source ?? "", t.ratesCapturedAt.map { iso.string(from: $0) } ?? ""]
            fields += [d.parkingDescription ?? "", d.tollsDescription ?? "", d.evidenceReference ?? ""]
            fields += [gps.map { $0.interrupted ? "Interrupted; verify distance. " + ($0.interruptionReasons ?? []).joined(separator: "; ") : "GPS estimate; verify distance" } ?? (d.method == .gps ? "Original evidence unavailable (legacy)" : "User entered")]
            rows.append(fields.enumerated().map { numeric.contains($0.offset) ? quote($0.element) : cell($0.element) }.joined(separator: ","))
        }
        return "\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n"
    }
}
