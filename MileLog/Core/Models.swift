import Foundation

enum Category: String, Codable, CaseIterable, Identifiable, Sendable {
    case business = "Business", medical = "Medical", charitable = "Charitable", moving = "Moving-military", personal = "Personal"
    var id: String { rawValue }
}
enum CaptureMethod: String, Codable, CaseIterable, Sendable { case manual = "Manual", gps = "GPS" }
struct Place: Codable, Equatable, Sendable {
    var text = ""
    var latitude: Double?
    var longitude: Double?
}
struct TripDetails: Codable, Equatable, Sendable {
    // Civil date remains stable when the user travels across time zones.
    var day = Day.string(Date())
    var start = Place()
    var end = Place()
    var purpose = ""
    var miles: Double = 0
    var method: CaptureMethod = .manual
    var category: Category = .business
    var vehicleID: UUID?
    var odometerStart: Double?
    var odometerEnd: Double?
    var parking: Decimal = 0
    var tolls: Decimal = 0
    var notes = ""
    var roundTrip = false
    var status: TripStatus?
    var startedAt: Date?
    var endedAt: Date?
    var startTimeZoneID: String?
    var endTimeZoneID: String?
    var jurisdiction: String?
    var correctionReason: String?
    var parkingDescription: String?
    var tollsDescription: String?
    var evidenceReference: String?
    var totalMiles: Double { miles * (roundTrip ? 2 : 1) }
}
struct TripEditEvent: Codable, Identifiable, Sendable {
    var id = UUID()
    var at = Date()
    var action: String
    var details: TripDetails
    var irsRate: MileageRate?
    var employerRate: MileageRate?
}
protocol Record: Codable, Identifiable, Sendable where ID == UUID { var updatedAt: Date { get } }
struct Trip: Record {
    var id = UUID()
    var details = TripDetails()
    var createdAt = Date()
    var updatedAt = Date()
    var deletedAt: Date?
    var history: [TripEditEvent] = []
    var sourceDraftID: UUID?
    var gpsEvidence: GPSRecordingEvidence?
    var originalDetails: TripDetails?
    var irsRate: MileageRate?
    var employerRate: MileageRate?
    var ratesCapturedAt: Date?
    var rateCaptureNote: String?
}
struct VehicleYear: Codable, Identifiable, Sendable {
    var id = UUID()
    var year: Int = Calendar.current.component(.year, from: Date())
    var start: Double = 0
    var end: Double?
    var startDay: String?
    var endDay: String?
    var startRecorded: Bool?
    var fullYearConfirmed: Bool?
}
struct Vehicle: Record {
    var id = UUID()
    var name = ""
    var year = ""
    var make = ""
    var model = ""
    var plate = ""
    var years: [VehicleYear] = []
    var businessServiceDay: String?
    var businessServiceOdometer: Double?
    var odometerHistory: [OdometerEdit]?
    var odometerCorrectionReason: String?
    var updatedAt = Date()
}
struct MileageRate: Record, Equatable {
    var id = UUID()
    var taxYear = Calendar.current.component(.year, from: Date())
    var category: Category = .business
    var cents: Decimal = 0
    var startDay = "2026-01-01"
    var endDay = "2026-12-31"
    var employer = false
    var jurisdiction: String?
    var source = "User entered; verify before use"
    var updatedAt = Date()
}
struct FrequentTrip: Record {
    var id = UUID()
    var name = ""
    var details = TripDetails()
    var updatedAt = Date()
}
struct SavedPurpose: Record {
    var id = UUID()
    var text = ""
    var updatedAt = Date()
}
struct FeedbackNote: Record {
    var id = UUID()
    var text = ""
    var createdAt = Date()
    var updatedAt = Date()
}
struct GPSFix: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var timestamp: Date
    var place: Place { Place(text: String(format: "%.5f, %.5f", latitude, longitude), latitude: latitude, longitude: longitude) }
}
struct RecordingDraft: Record {
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var meters = 0.0
    var first: GPSFix?
    var last: GPSFix?
    var interrupted = false
    var ended = false
    var vehicleID: UUID?
    var needsDuplicateReview: Bool?
    var startDay: String?
    var endedAt: Date?
    var startTimeZoneID: String?
    var endTimeZoneID: String?
    var acceptedFixes: Int?
    var rejectedFixes: Int?
    var interruptionReasons: [String]?
}
struct RecordTombstone: Record {
    var id = UUID()
    var recordID: UUID
    var kind: String
    var updatedAt = Date()
}
struct LogPreferences: Record {
    var id = UUID(uuidString: "B43818A8-C957-4F57-9882-3DC761162529")!
    var updatedAt = Date()
    var schemaVersion = 3
    var hasCompletedWelcome = false
    var defaultVehicleID: UUID?
    var installedRateIDs: [UUID] = []
}
struct Backup: Codable, Sendable {
    var format = "MileLog"
    var version = 3
    var exportedAt = Date()
    var trips: [Trip] = []
    var vehicles: [Vehicle] = []
    var rates: [MileageRate] = []
    var purposes: [SavedPurpose] = []
    var frequentTrips: [FrequentTrip] = []
    var feedback: [FeedbackNote] = []
    var drafts: [RecordingDraft] = []
    // Optional additions allow version-1 files and existing payloads to decode unchanged.
    var tombstones: [RecordTombstone]?
    var preferences: LogPreferences?
}
struct LogError: LocalizedError { var message: String; var errorDescription: String? { message }; init(_ message: String) { self.message = message } }

enum Day {
    static func string(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func date(_ string: String) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        guard let date = f.date(from: string), self.string(date) == string else { return nil }; return date
    }
}
