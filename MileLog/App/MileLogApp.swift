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
                        Text("\(startupError)\n\nYour data has not been erased. Keep the app installed and report this error.")
                    } actions: { Button("Retry") { open() } }
                } else { ProgressView("Opening MileLog…") }
            }.task { if store == nil { open() } }.tint(.teal)
        }
    }
    private func open() {
        do { let loaded = try LogStore(); store = loaded; recorder = LocationRecorder(store: loaded); startupError = nil } catch { startupError = error.localizedDescription }
    }
}
struct RootView: View {
    @Environment(LogStore.self) private var store
    @Environment(LocationRecorder.self) private var recorder
    @Environment(\.scenePhase) private var phase
    var body: some View {
        @Bindable var store = store
        TabView {
            TripsView().tabItem { Label("Trips", systemImage: "car.side") }
            TotalsView().tabItem { Label("Totals", systemImage: "sum") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }.errorAlert($store.error).onChange(of: phase) { _, phase in
            if phase != .active { recorder.pause() } else { recorder.becameActive() }
        }
    }
}
#Preview("MileLog") { let s = PreviewData.store(); RootView().environment(s).environment(LocationRecorder(store: s)) }
