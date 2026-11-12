import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(LogStore.self) private var store
    @Environment(LocationRecorder.self) private var recorder
    var showReports: () -> Void = {}
    @State private var file: ShareFile?
    @State private var importing = false
    @State private var incoming: Backup?
    @State private var confirmRestore = false
    @State private var confirmErase = false
    @State private var feedback = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            List {
                Section("Your workspace") {
                    NavigationLink { VehiclesView() } label: { Label("Vehicles", systemImage: "car.side") }
                    if !store.data.vehicles.isEmpty {
                        Picker("Default vehicle", selection: Binding(get: { store.defaultVehicleID }, set: { id in
                            do { var preferences = store.preferences; preferences.defaultVehicleID = id; try store.savePreferences(preferences) }
                            catch { message = error.localizedDescription }
                        })) { ForEach(store.data.vehicles) { Text($0.name).tag(Optional($0.id)) } }
                    }
                    NavigationLink { RatesView() } label: { Label("Mileage rates", systemImage: "dollarsign.circle") }
                    NavigationLink { ShortcutsView() } label: { Label("Quick-add trips & purposes", systemImage: "bolt") }
                    Button(action: showReports) { Label("Reports & export", systemImage: "square.and.arrow.up") }
                }
                Section {
                    Button { makeBackup() } label: { Label("Back up my log", systemImage: "externaldrive.badge.plus") }
                    Button { importing = true } label: { Label("Restore a backup", systemImage: "arrow.down.doc") }
                        .disabled(recorder.recording)
                    NavigationLink { RecoveryFilesView() } label: { Label("Recovery copies", systemImage: "folder") }
                    if recorder.recording { Text("End or pause your recording before restoring a backup.").font(.caption).foregroundStyle(.secondary) }
                } header: { Text("Protect your records") } footer: {
                    Text("Save a backup to Files or another location outside MileLog. Local copies are lost if the app is deleted. Backups include your trip history and private locations.")
                }
                Section("Help & information") {
                    NavigationLink { HelpView() } label: { Label("Help & support", systemImage: "questionmark.circle") }
                    NavigationLink { PrivacyView() } label: { Label("Privacy policy", systemImage: "hand.raised") }
                    Button { feedback = true } label: { Label("Feedback notes", systemImage: "bubble.left") }
                    Link(destination: ReleaseInfo.supportURL) { Label("Email support", systemImage: "envelope") }
                    Link("IRS mileage information", destination: URL(string: "https://www.irs.gov/tax-professionals/standard-mileage-rates")!)
                }
                Section {
                    Text("MileLog helps you keep mileage records. Estimates are not tax advice or a guarantee of eligibility. Keep supporting records and review your circumstances with a tax professional.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(ReleaseInfo.version).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Erase all local data", role: .destructive) { confirmErase = true }.disabled(recorder.recording)
                } footer: {
                    Text("Removes trips, vehicles, history, recordings, and local backups. Exported copies in other apps or device backups are separate.")
                }
            }.navigationTitle("Settings")
                .sheet(item: $file) { ShareSheet(url: $0.url) }
                .sheet(isPresented: $feedback) { NavigationStack { FeedbackView() } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get()
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size < 50_000_000 else { throw LogError("This backup exceeds the 50 MB import limit.") }
                        incoming = try BackupService.decode(Data(contentsOf: url)); confirmRestore = true
                    } catch { message = error.localizedDescription }
                }
                .confirmationDialog("Restore \(Recordkeeping.plural(incoming?.trips.filter { $0.deletedAt == nil }.count ?? 0, "trip")) from this backup? Newer records are kept. We'll save a recovery copy first.", isPresented: $confirmRestore, titleVisibility: .visible) {
                    Button("Merge backup") {
                        do {
                            guard let incoming, !recorder.recording else { return }
                            guard recorder.checkpoint() else { message = recorder.error; return }
                            try store.restore(incoming); recorder.refresh(); self.incoming = nil
                            message = "Backup restored. Review any recovered recordings before saving them as trips."
                        } catch { message = error.localizedDescription }
                    }
                }
                .confirmationDialog("Permanently erase your local log and recovery copies? Save a backup outside MileLog first. This cannot be undone.", isPresented: $confirmErase, titleVisibility: .visible) {
                    Button("Erase all local data", role: .destructive) {
                        do { try store.eraseLog(); recorder.refresh() }
                        catch { recorder.refresh(); message = error.localizedDescription }
                    }
                }
                .errorAlert($message)
        }
    }
    private func makeBackup() {
        guard recorder.checkpoint() else { message = recorder.error; return }
        do { file = ShareFile(url: try store.backupFile()) }
        catch { message = error.localizedDescription }
    }
}

struct ShortcutsView: View {
    @Environment(LogStore.self) private var store
    @State private var pendingID: UUID?
    @State private var kind = "frequent"
    @State private var error: String?
    var body: some View {
        List {
            Section("Quick-add trips") {
                ForEach(store.data.frequentTrips) { trip in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trip.name).font(.headline)
                        Text("\(trip.details.start.text) → \(trip.details.end.text)").font(.caption).foregroundStyle(.secondary)
                    }.swipeActions { Button("Delete", role: .destructive) { kind = "frequent"; pendingID = trip.id } }
                }
                if store.data.frequentTrips.isEmpty { Text("Save a route from a trip's “Save for next time” section.").foregroundStyle(.secondary) }
            }
            Section("Saved purposes") {
                ForEach(store.data.purposes) { purpose in
                    Text(purpose.text).swipeActions { Button("Delete", role: .destructive) { kind = "purpose"; pendingID = purpose.id } }
                }
            }
        }.navigationTitle("Quick add").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Remove this shortcut? Your saved trips stay in the log.", isPresented: Binding(get: { pendingID != nil }, set: { if !$0 { pendingID = nil } }), titleVisibility: .visible) {
                Button("Remove shortcut", role: .destructive) {
                    do { if let pendingID { try store.removeRecord(id: pendingID, kind: kind) }; pendingID = nil }
                    catch { self.error = error.localizedDescription }
                }
            }.errorAlert($error)
    }
}

struct FeedbackView: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    var body: some View {
        List {
            Section {
                TextField("What happened? What did you expect?", text: $text, axis: .vertical).lineLimit(4...10)
                Button("Save feedback note") {
                    do { var b = store.data; b.feedback.append(FeedbackNote(text: text)); try store.commit(b); text = "" }
                    catch { self.error = error.localizedDescription }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: { Text("Notes stay on this device and are included in backups. To contact us, use Email support in Settings.") }
            Section("Saved notes") {
                ForEach(store.data.feedback.sorted { $0.createdAt > $1.createdAt }) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.text)
                        Text(note.createdAt.formatted()).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("Feedback notes").toolbar { Button("Done") { dismiss() } }
            .scrollDismissesKeyboard(.interactively).errorAlert($error)
    }
}

struct RecoveryFilesView: View {
    @State private var urls: [URL] = []
    @State private var share: ShareFile?
    @State private var deleting: URL?
    @State private var error: String?
    var body: some View {
        List {
            Text("Save a copy outside MileLog to protect it from app deletion. These files contain your private locations and trip history.").font(.footnote).foregroundStyle(.secondary)
            if urls.isEmpty { ContentUnavailableView("No recovery copies yet", systemImage: "folder", description: Text("A local copy is created when you back up or restore your log.")) }
            ForEach(urls, id: \.self) { url in
                Button { share = ShareFile(url: url) } label: {
                    Label(url.lastPathComponent, systemImage: "doc").font(.caption).lineLimit(2)
                }.swipeActions { Button("Delete", role: .destructive) { deleting = url } }
            }
        }.navigationTitle("Recovery copies").task { load() }
            .sheet(item: $share) { ShareSheet(url: $0.url) }
            .confirmationDialog("Delete this local backup file? The current log is unchanged.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete copy", role: .destructive) {
                    do { if let deleting { try FileManager.default.removeItem(at: deleting) }; deleting = nil; load() }
                    catch { self.error = error.localizedDescription }
                }
            }.errorAlert($error)
    }
    private func load() {
        do {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("MileLog-") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        } catch { self.error = error.localizedDescription }
    }
}
#Preview("Settings") { let s = PreviewData.store(); SettingsView().environment(s).environment(LocationRecorder(store: s)) }
