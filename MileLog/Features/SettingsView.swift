import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(LogStore.self) private var store
    @Environment(LocationRecorder.self) private var recorder
    @State private var file: ShareFile?
    @State private var importing = false
    @State private var incoming: Backup?
    @State private var confirmRestore = false
    @State private var feedback = false
    @State private var message: String?
    @State private var employer = false
    var body: some View {
        NavigationStack {
            List {
                Section("Your log") {
                    NavigationLink("Vehicles", destination: VehiclesView())
                    NavigationLink("Mileage rates", destination: RatesView())
                }
                Section {
                    Toggle("CSV uses employer rates", isOn: $employer)
                    Button("Export trips as CSV", systemImage: "tablecells") {
                        store.perform { let text = CSVExporter.export(store.data, employer: employer); file = ShareFile(url: try store.writeFile(Data(text.utf8), name: "MileLog-\(employer ? "employer" : "IRS")-\(Day.string(Date())).csv")) }
                    }
                    Text("Exports all saved trips, including Personal. Rate is dollars per mile; Amount is mileage only. Missing rates leave Rate and Amount blank. Parking and tolls have separate columns.").font(.caption).foregroundStyle(.secondary)
                } header: { Text("Export") }
                Section {
                    Button("Create JSON backup", systemImage: "square.and.arrow.up") { store.perform { file = ShareFile(url: try store.backupFile()) } }
                    Button("Restore JSON backup", systemImage: "square.and.arrow.down") { importing = true }.disabled(recorder.recording)
                    NavigationLink("Local recovery copies", destination: RecoveryFilesView())
                } header: { Text("Keep your data safe") } footer: { Text("Save backups outside MileLog, such as to Files or your Mac. A backup contains trips, edit history, vehicles, rates, shortcuts, GPS drafts and feedback. Restore merges records by ID, keeps the newest version, and saves a local recovery copy first. Deleting the app removes its local copies too.") }
                Section("About") {
                    Text("MileLog helps you keep mileage records. It is not tax advice. Estimates are not guaranteed, and IRS or employer acceptance depends on your circumstances and supporting records.")
                    Link("IRS Publication 463", destination: URL(string: "https://www.irs.gov/publications/p463")!)
                    Text("Your log stays on this device. No account, analytics or tracking SDKs. Optional place search uses Apple Maps. Exports leave the device only when you choose where to share them.").font(.footnote).foregroundStyle(.secondary)
                    Text("MileLog · MVP 1.0").font(.footnote).foregroundStyle(.secondary).onLongPressGesture(minimumDuration: 1) { feedback = true }.accessibilityHint("Long press to open feedback notes")
                }
            }.navigationTitle("Settings")
                .sheet(item: $file) { ShareSheet(url: $0.url) }
                .sheet(isPresented: $feedback) { NavigationStack { FeedbackView() } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size < 50_000_000 else { throw LogError("This backup exceeds the 50 MB import limit.") }
                        incoming = try BackupService.decode(Data(contentsOf: url)); confirmRestore = true
                    } catch { message = error.localizedDescription }
                }
                .confirmationDialog("Merge this backup (\(incoming?.trips.count ?? 0) trip records)? Existing newer records will be kept. A recovery copy will be saved first.", isPresented: $confirmRestore, titleVisibility: .visible) {
                    Button("Restore backup") {
                        do { guard let incoming else { return }; try store.restore(incoming); recorder.refresh(); self.incoming = nil; message = "Backup restored. Your current and imported records have been merged." } catch { message = error.localizedDescription }
                    }
                }.errorAlert($message)
        }
    }
}
struct FeedbackView: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        List {
            Section {
                TextField("What happened? What did you expect?", text: $text, axis: .vertical).lineLimit(4...10)
                Button("Save feedback note") { store.perform { var b = store.data; b.feedback.append(FeedbackNote(text: text)); try store.commit(b); text = "" } }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: { Text("These notes stay on your device and are included in JSON backups. Nothing is sent automatically.") }
            Section("Saved notes") { ForEach(store.data.feedback.sorted { $0.createdAt > $1.createdAt }) { note in VStack(alignment: .leading, spacing: 6) { Text(note.text); Text(note.createdAt.formatted()).font(.caption).foregroundStyle(.secondary) } } }
        }.navigationTitle("Send feedback").toolbar { Button("Done") { dismiss() } }
    }
}
struct RecoveryFilesView: View {
    @State private var urls: [URL] = []
    @State private var share: ShareFile?
    @State private var error: String?
    var body: some View {
        List {
            Text("Share a copy to Files or your Mac to protect it from app deletion. These files contain your trip history and locations.").font(.footnote).foregroundStyle(.secondary)
            ForEach(urls, id: \.self) { url in Button(url.lastPathComponent) { share = ShareFile(url: url) } }
        }.navigationTitle("Recovery copies").task {
            do { let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]; urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent } } catch { self.error = error.localizedDescription }
        }.sheet(item: $share) { ShareSheet(url: $0.url) }.errorAlert($error)
    }
}
#Preview("Settings") { let s = PreviewData.store(); SettingsView().environment(s).environment(LocationRecorder(store: s)) }
#Preview("Feedback") { NavigationStack { FeedbackView().environment(PreviewData.store()) } }
#Preview("Recovery copies") { NavigationStack { RecoveryFilesView() } }
