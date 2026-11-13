import Foundation
import Observation
import os

@MainActor @Observable final class StartupController {
    typealias Loader = @Sendable (@escaping @Sendable (StartupStage) -> Void) async throws -> PreparedLog
    private(set) var store: LogStore?
    private(set) var error: String?
    private(set) var stage = StartupStage.opening
    private(set) var isOpening = false
    private(set) var showProgress = false
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    @ObservationIgnored private let loader: Loader
    @ObservationIgnored private let clockStart = ContinuousClock.now
    @ObservationIgnored private var recordedReady = false
    private static let logger = Logger(subsystem: "com.colezill.MileLog", category: "Startup")

    init(loader: @escaping Loader = { progress in
        try await Task.detached(priority: .userInitiated) {
            try LogLoader.prepare(progress: progress)
        }.value
    }) { self.loader = loader }

    func start() {
        guard store == nil, !isOpening else { return }
        isOpening = true; error = nil; stage = .opening; showProgress = false
        task = Task { await open() }
    }

    private func open() async {
        let loadStart = ContinuousClock.now
        // Only defer the indicator, never data readiness or the Trips screen.
        let indicator = Task {
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            if isOpening { showProgress = true }
        }
        defer { indicator.cancel(); isOpening = false; showProgress = false }
        do {
            let prepared = try await loader { [weak self] stage in
                Task { @MainActor in
                    guard let self, self.isOpening, stage.rawValue >= self.stage.rawValue else { return }
                    self.stage = stage
                }
            }
            store = LogStore(prepared: prepared)
            Self.logger.notice("Load \(String(describing: loadStart.duration(to: .now)), privacy: .public)")
        } catch {
            self.error = error.localizedDescription
            Self.logger.error("Opening failed; original store retained")
        }
    }

    func recordReady() {
        guard !recordedReady else { return }
        recordedReady = true
        // Local duration only: no trip, location, or account data is logged.
        Self.logger.notice("Ready \(String(describing: self.clockStart.duration(to: .now)), privacy: .public)")
    }
}
