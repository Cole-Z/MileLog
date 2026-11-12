import SwiftUI

extension Color {
    static let mileAccent = Color("AccentColor")
    static let mileInk = Color(red: 0.06, green: 0.15, blue: 0.21)
    static let mileTeal = Color(red: 0.05, green: 0.43, blue: 0.39)
    static let mileMint = Color(red: 0.69, green: 0.94, blue: 0.81)
}

enum ReleaseInfo {
    static let supportEmail = "contact@collectoratlas.app"
    static let supportURL = URL(string: "mailto:contact@collectoratlas.app?subject=MileLog%20support")!
    static var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }
}

struct MetricView: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

struct WelcomeView: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var vehicle = Vehicle()
    @State private var error: String?
    @State private var privacy = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 38, weight: .semibold)).foregroundStyle(Color.mileAccent)
                        .padding(20).background(Color.mileTeal.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Make every work mile count.").font(.largeTitle.bold())
                        Text("A simple mileage log for your business, your side work, and your next tax season.")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        benefit("Start a trip. Get on with your day.", detail: "Keep recording while your phone is locked or you use navigation.", icon: "location.circle")
                        benefit("Keep a record you can use.", detail: "Add a purpose, review your miles, and export a business report.", icon: "doc.text")
                        benefit("Your log stays with you.", detail: "No account needed. Save a backup outside the app to protect your records.", icon: "lock.shield")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your first vehicle").font(.headline)
                        TextField("Nickname, e.g. My work car", text: $vehicle.name).textFieldStyle(.roundedBorder)
                        Text("Optional. You can add vehicles and odometer readings later.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button(action: finish) {
                        Text("Start my log").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).tint(Color.mileTeal)
                    Button("Privacy policy") { privacy = true }.frame(maxWidth: .infinity)
                    Text("Mileage estimates help with recordkeeping. Deduction eligibility depends on your circumstances.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.navigationTitle("Welcome to MileLog").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .sheet(isPresented: $privacy) { NavigationStack { PrivacyView().toolbar { Button("Done") { privacy = false } } } }
                .errorAlert($error)
        }.interactiveDismissDisabled()
    }
    private func benefit(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.mileAccent).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    private func finish() {
        do {
            if !vehicle.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try store.saveVehicle(vehicle, makeDefault: true) }
            var preferences = store.preferences; preferences.hasCompletedWelcome = true
            try store.savePreferences(preferences)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Label("Your mileage. Your record.", systemImage: "lock.shield").font(.headline)
                Text("MileLog does not require an account and does not operate a server for your trip log. We do not receive your trips through the app. There are no advertising or analytics SDKs.")
            }
            Section("What is stored") {
                Text("Trips, purposes, locations, vehicle details, expenses, edit history, settings, and recording drafts are stored on your device. GPS recording retains distance and endpoints, not a complete route trace.")
            }
            Section("Location permission") {
                Text("Location is used only for trips you explicitly start. Recording can continue with the screen locked or while another app is open, and stops when you pause or end the trip. MileLog does not automatically detect drives. You can revoke location access in iPhone Settings and continue to enter trips manually.")
            }
            Section("Apple Maps and sharing") {
                Text("Optional place search sends your search to Apple Maps. Look up endpoint names sends the saved endpoint coordinates to Apple's geocoding service only when you tap it. Results are cached in memory while the editor is open. You can type labels without using either service; original GPS coordinates are retained. Apple's privacy practices apply to its services.")
                Link("Apple Maps & Privacy", destination: URL(string: "https://www.apple.com/legal/privacy/data/en/apple-maps/")!)
                Text("CSV/PDF reports and backups leave the app when you choose a destination in the share sheet. That destination handles the copy under its own policies. iOS device backups may also contain app data, depending on your device settings.")
            }
            Section("Retention and deletion") {
                Text("Deleting a trip removes it from the active log but keeps its history in backups. Settings → Erase all local data removes the log, history, drafts, preferences, and local export/recovery files. Deleting MileLog also removes its local data. Copies you previously exported or included in device backups must be managed separately.")
            }
            Section("Contact") {
                Text("If you email support, the information you choose to send is used to respond to your request. Please avoid sending private destinations or full backups unless needed. You can ask us to delete support correspondence.")
                Link(ReleaseInfo.supportEmail, destination: ReleaseInfo.supportURL)
                Text("Effective November 12, 2026").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Privacy policy").navigationBarTitleDisplayMode(.inline)
    }
}

struct HelpView: View {
    var body: some View {
        List {
            Section("Record a drive") {
                Text("While parked, tap Start trip and allow precise location. Wait for a location fix before driving. You can lock the phone or use navigation. When parked at the destination, end the trip, check the distance, add its purpose, and save.")
                Text("A pause, poor signal, force quit, or system interruption can leave a gap. Reopen MileLog to review a recovered recording. Compare against your odometer and correct missing miles before saving.")
            }
            Section("Log a trip manually") {
                Text("Tap Add manually. Enter the date, locations, miles, and purpose. For round trips, enter the one-way miles and enable Round trip. Optional details include odometers, parking, tolls, and notes.")
            }
            Section("Prepare a report") {
                Text("Choose Reports, select the dates and vehicle, and review the category. Business is selected by default. CSV and PDF use those trip filters. Incomplete records and missing rates leave amounts blank; parking and tolls stay separate. Enter annual odometers in Settings → Vehicles; partial-year readings are not annual totals.")
            }
            Section("Records and eligibility") {
                Text("Records support substantiation but do not establish tax eligibility. Include a business destination and purpose. Ordinary commuting between home and a regular workplace is generally personal, not business travel.")
                Text("Ordinary W-2 employees generally cannot claim federal deductions for unreimbursed business mileage, although specific exceptions may apply. Employer reimbursement is separate from deductibility. MileLog does not make personalized tax determinations.")
                Link("IRS Publication 463", destination: URL(string: "https://www.irs.gov/publications/p463")!)
                Link("IRS mileage rates", destination: URL(string: "https://www.irs.gov/tax-professionals/standard-mileage-rates")!)
            }
            Section("Protect your log") {
                Text("Create a backup in Settings and save it outside MileLog, such as to Files. Do this regularly and before updating or deleting the app. Local recovery copies are removed when the app is deleted.")
            }
            Section("Need help?") {
                Link("Email \(ReleaseInfo.supportEmail)", destination: ReleaseInfo.supportURL)
                Text("Include your iPhone model, iOS version, app version, and what you expected to happen. Redact private locations.").font(.footnote).foregroundStyle(.secondary)
                Text(ReleaseInfo.version).font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Help & support").navigationBarTitleDisplayMode(.inline)
    }
}
