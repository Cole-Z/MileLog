import Foundation
import SwiftData
import Testing
@testable import MileLogCore

@MainActor struct StartupTests {
    @Test func fastLoadNeverWaitsForBrandingAndDoesNotRepeat() async throws {
        let prepared = try LogLoader.prepare(inMemory: true)
        let controller = StartupController { _ in prepared }
        controller.start()
        await controller.task?.value
        #expect(controller.store != nil && !controller.showProgress && !controller.isOpening)
        let first = controller.store
        controller.start() // foreground/task reappearance must not reopen storage
        #expect(controller.store === first)
    }

    @Test func slowLoadShowsRealStageThenClearsImmediately() async throws {
        let prepared = try LogLoader.prepare(inMemory: true)
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let controller = StartupController { progress in
            progress(.reading)
            for await _ in stream { break }
            return prepared
        }
        controller.start()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !controller.showProgress && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.showProgress && controller.store == nil && controller.stage == .reading)
        continuation.yield(()); continuation.finish()
        await controller.task?.value
        #expect(controller.store != nil && !controller.showProgress)
    }

    @Test func failureCanRetryWithoutOverlappingLoads() async throws {
        actor Attempts {
            var count = 0
            func next() -> Int { count += 1; return count }
        }
        let attempts = Attempts(), prepared = try LogLoader.prepare(inMemory: true)
        let controller = StartupController { _ in
            if await attempts.next() == 1 { throw LogError("Storage temporarily unavailable") }
            return prepared
        }
        controller.start(); controller.start()
        await controller.task?.value
        #expect(controller.error == "Storage temporarily unavailable" && controller.store == nil)
        #expect(!controller.showProgress && !controller.isOpening)
        controller.start()
        await controller.task?.value
        #expect(controller.error == nil && controller.store != nil)
        #expect(await attempts.count == 2)
    }

    @Test func backgroundLoadRecoveryAndSubsequentWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = try await Task.detached {
            try LogLoader.prepare(inMemory: true, fileDirectory: directory) { _ in #expect(!Thread.isMainThread) }
        }.value
        let store = LogStore(prepared: prepared)
        var draft = RecordingDraft(); draft.meters = 1234.567890123
        try store.saveDraft(draft)
        let container = store.container
        let reopened = try await Task.detached {
            try LogLoader.prepare(existingContainer: container, fileDirectory: directory)
        }.value
        #expect(reopened.data.drafts[0].meters == draft.meters)
        #expect(reopened.data.drafts[0].interrupted)
        #expect(reopened.data.drafts[0].interruptionReasons == ["Recovered after app interruption"])
        let live = LogStore(prepared: reopened)
        var details = live.data.drafts[0].recordedDetails
        details.start.text = "Office"; details.end.text = "Client"; details.purpose = "Meeting"; details.status = .complete
        try live.saveTrip(nil, details: details, draftID: draft.id)
        let final = try await Task.detached {
            try LogLoader.prepare(existingContainer: container, fileDirectory: directory)
        }.value
        #expect(final.data.trips.count == 1 && final.data.drafts.isEmpty)
        #expect(final.data.trips[0].gpsEvidence?.meters == draft.meters)
        #expect(final.data.trips[0].history.count == 1)
    }

    @Test func corruptOrFutureStoreIsNotRewritten() async throws {
        let store = try LogStore(inMemory: true)
        let context = ModelContext(store.container)
        let corrupt = StoredRecord(id: UUID(), kind: "trip", payload: Data("broken JSON".utf8))
        context.insert(corrupt); try context.save()
        let container = store.container
        do {
            _ = try await Task.detached { try LogLoader.prepare(existingContainer: container) }.value
            Issue.record("Corrupt data must fail startup")
        } catch { }
        #expect(corrupt.payload == Data("broken JSON".utf8))
        context.delete(corrupt); try context.save()
        let preference = try #require(context.fetch(FetchDescriptor<StoredRecord>()).first { $0.kind == "preferences" })
        var future = store.preferences; future.schemaVersion = 99
        preference.payload = try JSONEncoder().encode(future); try context.save()
        do {
            _ = try await Task.detached { try LogLoader.prepare(existingContainer: container) }.value
            Issue.record("Future schema must not be normalized to version 3")
        } catch { }
        #expect(try JSONDecoder().decode(LogPreferences.self, from: preference.payload).schemaVersion == 99)
    }

    @Test func largeHistoryBackgroundReopenPreservesEveryRecord() async throws {
        let store = try LogStore(inMemory: true)
        var backup = store.data
        for index in 0..<1000 {
            var trip = Trip()
            trip.details.day = "2026-07-01"; trip.details.start.text = "Office"
            trip.details.end.text = "Client \(index)"; trip.details.purpose = "Meeting"
            trip.details.miles = 1.729123456789; trip.originalDetails = trip.details
            trip.history = [TripEditEvent(action: "Created", details: trip.details)]
            Recordkeeping.snapshotRates(&trip, rates: backup.rates, note: "Test")
            backup.trips.append(trip)
        }
        try store.commit(backup)
        let container = store.container
        let reopened = try await Task.detached {
            try LogLoader.prepare(existingContainer: container) { _ in #expect(!Thread.isMainThread) }
        }.value
        let byID = Dictionary(uniqueKeysWithValues: reopened.data.trips.map { ($0.id, $0) })
        #expect(byID.count == 1000)
        for trip in backup.trips {
            #expect(byID[trip.id]?.details == trip.details)
            #expect(byID[trip.id]?.originalDetails == trip.originalDetails)
            #expect(byID[trip.id]?.history.first?.id == trip.history.first?.id)
            #expect(byID[trip.id]?.irsRate == trip.irsRate)
        }
    }
}
