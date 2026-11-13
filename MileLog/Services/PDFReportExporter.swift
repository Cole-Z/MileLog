import UIKit

@MainActor enum PDFReportExporter {
    static func export(backup: Backup, selection: ReportSelection) -> Data {
        let report = MileageReport(backup: backup, employer: selection.employer, selected: backup.trips.filter(selection.includes), years: selection.years(in: backup), vehicleIDs: selection.vehicleID.map { Set([$0]) })
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "MileLog — \(selection.label)", kCGPDFContextCreator as String: "MileLog"]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        return renderer.pdfData { context in
            var y: CGFloat = 0
            var page = 0
            let left: CGFloat = 36, width: CGFloat = 540, bottom: CGFloat = 736
            func nextPage() {
                context.beginPage(); page += 1; y = 58
                ("MileLog · \(selection.label)" as NSString).draw(at: CGPoint(x: left, y: 26), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.black])
                ("Page \(page) · Records support substantiation; eligibility is not established." as NSString).draw(at: CGPoint(x: left, y: 761), withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray])
            }
            func text(_ value: String, size: CGFloat = 10, bold: Bool = false) {
                let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
                let lineHeight = ceil(font.lineHeight) + 3
                for line in wrappedLines(value, font: font, width: width) {
                    if y + lineHeight > bottom { nextPage() }
                    (line as NSString).draw(at: CGPoint(x: left, y: y), withAttributes: attributes)
                    y += lineHeight
                }
                y += 4
            }
            func heading(_ value: String) { if y > bottom - 75 { nextPage() }; y += 8; text(value, size: 13, bold: true) }
            nextPage()
            text(selection.employer ? "Employer reimbursement estimate" : "IRS mileage deduction estimate", size: 18, bold: true)
            text("Period: \(selection.label) · Category: \(selection.category?.rawValue ?? "All")")
            text("\(Recordkeeping.plural(report.rows.count, "trip")) · Logged miles: \(CSVExporter.precise(report.rows.reduce(0) { $0 + $1.trip.details.totalMiles }))")
            text("Mileage estimate: \(report.total.money)", size: 14, bold: true)
            let nonpersonal = report.rows.filter { $0.trip.details.category != .personal }
            text("Separately tracked nonpersonal parking: \(nonpersonal.reduce(Decimal(0)) { $0 + $1.trip.details.parking }.money) · Tolls: \(nonpersonal.reduce(Decimal(0)) { $0 + $1.trip.details.tolls }.money)")
            text("Incomplete records: \(report.incomplete) · Complete records missing rates: \(report.missingRates) · Trips without a vehicle: \(report.unassignedVehicles)")
            text("All selected trips remain in this report. Incomplete records and records without rates have no estimate amount. Personal mileage amounts are zero. Parking and tolls are not added to mileage estimates. Each trip uses full stored distance; its currency amount is rounded half-up to cents. Totals sum those rounded amounts.", size: 9)
            text("Saved rate snapshots are used. Refreshing rates or changing a trip's date/category is an explicit recalculation. Legacy snapshots were captured from the pre-upgrade table; missing original GPS evidence is not reconstructed.", size: 9)
            if selection.employer {
                text("An employer reimbursement estimate is not necessarily a deductible amount. Employer policy determines reimbursement.", size: 9)
            } else {
                text("Ordinary W-2 employees generally cannot claim federal deductions for unreimbursed business mileage, although specific exceptions may apply. Ordinary commuting is generally personal. No eligibility determination is made.", size: 9)
            }
            if !report.annual.isEmpty {
                heading("Annual vehicle records")
                text("These use all logged business trips for the full calendar year, independently of the selected report period/category. Odometer totals are user-entered, not independently verified. No annual total is inferred from trip samples.", size: 9)
                for annual in report.annual {
                    text("\(annual.vehicleName) · \(annual.year)", bold: true)
                    text("Business miles logged: \(CSVExporter.precise(annual.businessMiles)) · Incomplete business records: \(annual.incompleteTrips)")
                    text("Beginning odometer: \(annual.beginningOdometer.map(CSVExporter.precise) ?? "Missing or unconfirmed") [\(annual.beginningDay ?? "Date missing")] · Ending: \(annual.endingOdometer.map(CSVExporter.precise) ?? "Missing") [\(annual.endingDay ?? "Date missing")]")
                    text("Annual mileage: \(annual.annualMiles.map(CSVExporter.precise) ?? "Unavailable") · Recorded period mileage: \(annual.periodMiles.map(CSVExporter.precise) ?? "Unavailable")")
                    if let percent = annual.businessPercent { text("Recorded business use: \(percent.formatted(.number.precision(.fractionLength(1))))%") }
                    text(annual.note, size: 9)
                }
            }
            heading("Applied rate periods")
            for period in report.ratePeriods { text(period, size: 9) }
            if report.ratePeriods.isEmpty { text("No matching rate snapshots.", size: 9) }
            heading("Trip detail")
            let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for (index, row) in report.rows.enumerated() {
                let t = row.trip, d = t.details
                if y > bottom - 90 { nextPage() }
                text("\(index + 1). \(d.day) · \(row.vehicle) · \(d.category.rawValue)", bold: true)
                text("\(d.start.text.isEmpty ? "Origin missing" : d.start.text) → \(d.end.text.isEmpty ? "Destination missing" : d.end.text)")
                text("Purpose: \(d.purpose.isEmpty ? "Not supplied" : d.purpose)")
                text("Miles used: \(CSVExporter.precise(d.totalMiles)) · Original GPS miles: \(t.gpsEvidence.map { CSVExporter.precise($0.meters / DistanceCalculator.metersPerMile) } ?? "Unavailable")")
                if let original = t.originalDetails { text("Originally recorded miles: \(CSVExporter.precise(original.totalMiles))", size: 9) }
                text("Endpoint coordinates: \(coordinates(d.start)) → \(coordinates(d.end))", size: 9)
                if let evidence = t.gpsEvidence {
                    text("Original GPS coordinates: \(evidence.first.map { coordinates($0.place) } ?? "Unavailable") → \(evidence.last.map { coordinates($0.place) } ?? "Unavailable")", size: 9)
                }
                text("Rate: \(row.rate.map { "$" + CSVExporter.decimal($0.cents / 100) + "/mi" } ?? "Missing") · Estimate: \(row.amount?.money ?? "Not calculated")")
                text("Parking: \(d.parking.money) \(d.parkingDescription ?? "") · Tolls: \(d.tolls.money) \(d.tollsDescription ?? "")")
                text("Start: \(d.startedAt.map { iso.string(from: $0) } ?? "Not recorded") [\(d.startTimeZoneID ?? "Zone unknown")] · End: \(d.endedAt.map { iso.string(from: $0) } ?? "Not recorded") [\(d.endTimeZoneID ?? "Zone unknown")]")
                text("Source: \(d.method.rawValue) · \(row.status)", size: 9)
                if let reason = d.correctionReason { text("Correction reason: \(reason)", size: 9) }
                if t.gpsEvidence?.interrupted == true { text("Recording had interruptions. Verify the distance.", size: 9) }
                if !d.notes.isEmpty { text("Notes: \(d.notes)", size: 9) }
                if let reference = d.evidenceReference { text("Evidence reference: \(reference)", size: 9) }
                text("ID: \(t.id.uuidString) · Created: \(iso.string(from: t.createdAt)) · Edited: \(iso.string(from: t.updatedAt))", size: 8)
                y += 5
            }
            heading("Recordkeeping notes")
            text("Keep supporting documents and external backups. Deleting the app can remove local records and recovery files. This report is not IRS approval, proof of accuracy, or a determination of deductibility.", size: 9)
            text("IRS Publication 463: https://www.irs.gov/publications/p463\nMileage rates: https://www.irs.gov/tax-professionals/standard-mileage-rates", size: 8)
        }
    }
    private static func coordinates(_ place: Place) -> String {
        guard let latitude = place.latitude, let longitude = place.longitude else { return "Not recorded" }
        return "\(CSVExporter.precise(latitude)), \(CSVExporter.precise(longitude))"
    }
    /// Wrap by words and split oversized tokens, so long notes cannot overflow a page.
    nonisolated private static func wrappedLines(_ value: String, font: UIFont, width: CGFloat) -> [String] {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var lines: [String] = []
        for paragraph in value.components(separatedBy: "\n") {
            var line = ""
            for word in paragraph.split(whereSeparator: { $0.isWhitespace }) {
                let candidate = line.isEmpty ? String(word) : line + " " + word
                if (candidate as NSString).size(withAttributes: attributes).width <= width { line = candidate; continue }
                if !line.isEmpty { lines.append(line); line = "" }
                for character in word {
                    let candidate = line + String(character)
                    if (candidate as NSString).size(withAttributes: attributes).width > width && !line.isEmpty { lines.append(line); line = String(character) }
                    else { line = candidate }
                }
            }
            lines.append(line)
        }
        return lines
    }
}
