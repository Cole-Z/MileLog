import SwiftUI

@main struct MileLogApp: App {
    @State private var store: LogStore?
    @State private var recorder: LocationRecorder?
    @State private var startupError: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let store, let recorder { RootView().environment(store).environment(recorder) }
                else if let startupError {
                    ContentUnavailableView {
                        Label("Your log could not open", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("\(startupError)\n\nYour data has not been erased. Keep MileLog installed and contact support for help.")
                    } actions: {
                        Button("Retry") { open() }
                        Link("Contact support", destination: ReleaseInfo.supportURL)
                    }
                } else { ProgressView("Opening your mileage log…") }
            }.task { if store == nil { open() } }.tint(Color.mileAccent)
        }
    }
    private func open() {
        do {
            let loaded = try LogStore()
            store = loaded; recorder = LocationRecorder(store: loaded); startupError = nil
        } catch { startupError = error.localizedDescription }
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
