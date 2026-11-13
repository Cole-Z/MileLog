import SwiftUI

@main struct MileLogApp: App {
    @State private var startup = StartupController()
    var body: some Scene {
        WindowGroup {
            Group {
                if let store = startup.store { LoadedAppView(store: store).onAppear { startup.recordReady() } }
                else if let startupError = startup.error {
                    ContentUnavailableView {
                        Label("Your log could not open", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("\(startupError)\n\nYour data has not been erased. Keep MileLog installed and contact support for help.")
                    } actions: {
                        Button("Retry") { startup.start() }.buttonStyle(.borderedProminent)
                        Link("Contact support", destination: ReleaseInfo.supportURL)
                    }
                } else { StartupView(stage: startup.stage, showProgress: startup.showProgress) }
            }.task { startup.start() }.tint(Color.mileAccent)
        }
    }
}

private struct LoadedAppView: View {
    let store: LogStore
    @State private var recorder: LocationRecorder
    init(store: LogStore) {
        self.store = store
        _recorder = State(initialValue: LocationRecorder(store: store))
    }
    var body: some View { RootView().environment(store).environment(recorder) }
}

private struct StartupView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let stage: StartupStage
    let showProgress: Bool
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "car.side.fill").font(.largeTitle).foregroundStyle(Color.mileMint).accessibilityHidden(true)
                    Text("MileLog").font(.largeTitle.bold()).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: !showProgress || reduceMotion || scenePhase != .active)) { timeline in
                        let position = showProgress && !reduceMotion && scenePhase == .active ? (sin(timeline.date.timeIntervalSinceReferenceDate * 2) + 1) / 2 : 0.5
                        Capsule().fill(Color.mileMint.opacity(0.25)).frame(width: 160, height: 4)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.mileMint).frame(width: 40, height: 4).offset(x: position * 120)
                            }
                    }.accessibilityHidden(true)
                    if showProgress {
                        Text(stage.message).font(.body).foregroundStyle(.white).multilineTextAlignment(.center)
                            .accessibilityLabel("MileLog is loading. \(stage.message)")
                    }
                }.padding(32).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }.background(Color.mileInk.ignoresSafeArea())
            .onChange(of: showProgress) { _, visible in if visible { announceStage() } }
            .onChange(of: stage) { _, _ in announceStage() }
    }
    private func announceStage() {
        guard showProgress, scenePhase == .active, UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: stage.message)
    }
}
struct RootView: View {
    @Environment(LogStore.self) private var store
    @Environment(LocationRecorder.self) private var recorder
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    @State private var welcome = false
    var body: some View {
        TabView(selection: $tab) {
            TripsView().tabItem { Label("Trips", systemImage: "car.side") }.tag(0)
            ReportsView().tabItem { Label("Reports", systemImage: "chart.bar.xaxis") }.tag(1)
            SettingsView(showReports: { tab = 1 }).tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .errorAlert(Binding(get: {
            let messages = [store.error, recorder.error].compactMap { $0 }
            return messages.isEmpty ? nil : messages.joined(separator: "\n\n")
        }, set: { value in
            if value == nil { store.error = nil; recorder.error = nil }
        }))
        .onChange(of: phase) { _, phase in
            if phase == .background { recorder.checkpoint() }
            else if phase == .active { recorder.becameActive() }
        }
        .task { welcome = !store.preferences.hasCompletedWelcome }
        .onChange(of: store.preferences.hasCompletedWelcome) { _, completed in welcome = !completed }
        .sheet(isPresented: $welcome) { WelcomeView() }
    }
}
#Preview("MileLog") { let s = PreviewData.store(); RootView().environment(s).environment(LocationRecorder(store: s)) }
