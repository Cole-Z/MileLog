import XCTest
import PDFKit
import CoreLocation
@testable import MileLog

@MainActor final class NativeTests: XCTestCase {
    func testPDFPaginationEvidenceAndTotals() throws {
        let store = try LogStore(inMemory: true)
        var backup = store.data
        let vehicle = Vehicle(name: "Test car")
        backup.vehicles = [vehicle]
        for index in 0..<30 {
            var details = TripDetails()
            details.day = "2026-07-01"; details.vehicleID = vehicle.id
            details.start = Place(text: "Office", latitude: 41.123456789, longitude: -87.123456789)
            details.end = Place(text: "Client \(index)", latitude: 41.2, longitude: -87.2)
            details.purpose = index == 1 ? "" : "Client meeting \(index)"
            details.miles = 1.729123456789; details.status = index == 1 ? .incomplete : .complete
            details.notes = index == 29 ? String(repeating: "A long readable note with Unicode café and commas, ", count: 150) + "FINAL_NOTE_MARKER" : ""
            details.parking = 2.25; details.tolls = 1.50
            var trip = Trip(); trip.details = details; trip.originalDetails = details
            trip.history = [TripEditEvent(action: "Created", details: details)]
            Recordkeeping.snapshotRates(&trip, rates: backup.rates, note: "Test")
            backup.trips.append(trip)
        }
        let report = MileageReport(backup: backup)
        let pdf = PDFReportExporter.export(backup: backup, selection: ReportSelection(period: .all, category: nil))
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertGreaterThan(document.pageCount, 3)
        let text = try XCTUnwrap(document.string)
        XCTAssertTrue(text.contains(report.total.money))
        // PDFKit may extract underscores as separate text runs.
        XCTAssertTrue(text.filter { !$0.isWhitespace && $0 != "_" }.contains("FINALNOTEMARKER"))
        XCTAssertTrue(text.contains("41.123456789"))
        XCTAssertTrue(text.contains("Incomplete"))
        XCTAssertTrue(text.contains("Annual mileage is unavailable"))
        for trip in backup.trips { XCTAssertTrue(text.contains(trip.id.uuidString)) }
        for index in [0, document.pageCount - 1] {
            let page = try XCTUnwrap(document.page(at: index))
            let image = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
            let attachment = XCTAttachment(image: image); attachment.name = "PDF-page-\(index + 1)"; attachment.lifetime = .keepAlways
            add(attachment)
        }
        let attachment = XCTAttachment(data: pdf, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "MileLog-native-report"; attachment.lifetime = .keepAlways; add(attachment)
        let csv = CSVExporter.export(backup)
        XCTAssertTrue(csv.contains("Annual Mileage Status"))
        XCTAssertTrue(csv.contains("Annual mileage is unavailable"))
    }

    func testUnchangedEditorRetainsDistanceAndCorrectionReason() throws {
        var original = Trip()
        original.details.miles = 1.729123456789
        original.details.status = .incomplete
        original.details.correctionReason = "Earlier documented correction"
        original.history = [TripEditEvent(action: "Created", details: original.details)]
        let store = try LogStore(inMemory: true)
        var backup = store.data; backup.trips = [original]; try store.commit(backup)
        let editor = TripEditorModel(original: original)
        editor.details.purpose = "Updated purpose only"
        XCTAssertTrue(editor.save(store: store, draftID: nil))
        XCTAssertEqual(store.trips[0].details.miles, original.details.miles)
        XCTAssertEqual(store.trips[0].details.correctionReason, original.details.correctionReason)
    }

    func testShareCancellationAndErrorCallbackWithCompleteFile() throws {
        let store = try LogStore(inMemory: true)
        let bytes = PDFReportExporter.export(backup: store.data, selection: ReportSelection(period: .all))
        let file = try store.writeFile(bytes, name: "MileLog-test.pdf")
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertNotNil(PDFDocument(url: file))
        var failure: String?
        let controller = ShareSheet(url: file, onError: { failure = $0 }).makeController()
        controller.completionWithItemsHandler?(nil, false, nil, nil)
        XCTAssertNil(failure)
        controller.completionWithItemsHandler?(nil, false, nil, NSError(domain: "TestShare", code: 1))
        XCTAssertTrue(failure?.contains("Try sharing again") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testLocationPromptOnlyAfterStartAndReducedAccuracyFailure() throws {
        let store = try LogStore(inMemory: true)
        let manager = TestLocationManager()
        let recorder = LocationRecorder(store: store, manager: manager)
        XCTAssertEqual(manager.requests, 0)
        recorder.becameActive()
        XCTAssertEqual(manager.requests, 0)
        recorder.start()
        XCTAssertEqual(manager.requests, 1)
        manager.permission = .denied
        recorder.locationManagerDidChangeAuthorization(manager)
        XCTAssertFalse(recorder.recording)
        manager.permission = .authorizedWhenInUse; manager.accuracy = .reducedAccuracy
        recorder.start()
        XCTAssertFalse(recorder.recording)
        XCTAssertTrue(recorder.error?.contains("Precise Location") == true)
        XCTAssertNil(recorder.draft)
    }

    func testPauseEndAndLateFailureDoNotLoseDraft() throws {
        let store = try LogStore(inMemory: true)
        let manager = TestLocationManager(); manager.permission = .authorizedWhenInUse
        let recorder = LocationRecorder(store: store, manager: manager)
        recorder.start()
        XCTAssertTrue(recorder.recording)
        let now = Date()
        let first = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: now)
        let next = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.0001), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: now.addingTimeInterval(0.5))
        recorder.locationManager(manager, didUpdateLocations: [first, next])
        XCTAssertGreaterThan(recorder.draft?.meters ?? 0, 10)
        XCTAssertTrue(recorder.displayStatus(at: now.addingTimeInterval(40)).contains("Recovering GPS"))
        recorder.pause()
        let meters = recorder.draft?.meters
        XCTAssertEqual(store.data.drafts.first?.meters, meters)
        recorder.locationManager(manager, didUpdateLocations: [next])
        XCTAssertEqual(recorder.draft?.meters, meters)
        XCTAssertTrue(recorder.end())
        let status = recorder.status
        recorder.locationManager(manager, didFailWithError: CLError(.locationUnknown))
        XCTAssertEqual(recorder.status, status)
        XCTAssertEqual(store.data.drafts.first?.ended, true)
        XCTAssertEqual(store.data.drafts.first?.meters, meters)
    }
}

private final class TestLocationManager: CLLocationManager {
    var requests = 0
    var permission: CLAuthorizationStatus = .notDetermined
    var accuracy: CLAccuracyAuthorization = .fullAccuracy
    override var authorizationStatus: CLAuthorizationStatus { permission }
    override var accuracyAuthorization: CLAccuracyAuthorization { accuracy }
    override func requestWhenInUseAuthorization() { requests += 1 }
    override func startUpdatingLocation() { }
    override func stopUpdatingLocation() { }
}
