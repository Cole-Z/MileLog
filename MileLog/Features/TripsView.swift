import SwiftUI

struct TripPresentation: Identifiable {
    let id = UUID()
    var original: Trip?
    var details = TripDetails()
    var draftID: UUID?
    var duplicateReview = false
}
struct TripsView: View {
    @Environment(LogStore.self) private var store
    @Environment(LocationRecorder.self) private var recorder
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editor: TripPresentation?
    @State private var deleting: Trip?
    @State private var discard = false
    @State private var search = ""
    @State private var filters = ReportSelection(period: .all, category: nil)
    @State private var showFilters = false

    private var filteredTrips: [Trip] {
        store.trips.filter { trip in
            filters.includes(trip) && (search.isEmpty || [trip.details.start.text, trip.details.end.text, trip.details.purpose, trip.details.notes]
                .contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    private var groups: [String: [Trip]] { Dictionary(grouping: filteredTrips, by: { $0.details.day }) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    recordingCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if recorder.draft == nil { monthSummary }
                if !store.data.frequentTrips.isEmpty && recorder.draft == nil {
                    Section("Quick add") {
                        ForEach(store.data.frequentTrips.prefix(4)) { frequent in
                            Button {
                                var details = frequent.details
                                details.day = Day.string(Date()); details.method = .manual
                                details.odometerStart = nil; details.odometerEnd = nil
                                details.parking = 0; details.tolls = 0; details.notes = ""
                                editor = TripPresentation(details: details)
                            } label: {
                                Label(frequent.name, systemImage: "arrow.turn.down.right").foregroundStyle(Color.mileAccent)
                            }
                        }
                    }
                }
                if filteredTrips.isEmpty {
                    Section {
                        if store.trips.isEmpty {
                            ContentUnavailableView {
                                Label("Your first trip starts here", systemImage: "car.side")
                            } description: {
                                Text("Record your next drive or add one you've already taken.")
                            } actions: { Button("Add a trip manually", action: addManual).buttonStyle(.bordered) }
                        } else {
                            ContentUnavailableView {
                                Label("No matching trips", systemImage: "line.3.horizontal.decrease.circle")
                            } description: { Text("Try different dates, a different vehicle, or another search.")
                            } actions: { Button("Clear filters") { filters = ReportSelection(period: .all, category: nil); search = "" } }
                        }
                    }
                } else {
                    Section {
                        HStack {
                            Text("\(filteredTrips.count) trips").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(filteredTrips.reduce(0) { $0 + $1.details.totalMiles }.formatted(.number.precision(.fractionLength(1)))) mi")
                                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                        Section(Day.date(day)?.formatted(date: .abbreviated, time: .omitted) ?? day) {
                            ForEach(groups[day] ?? []) { trip in
                                Button { editor = TripPresentation(original: trip) } label: { tripRow(trip) }
                                    .buttonStyle(.plain)
                                    .swipeActions {
                                        Button("Delete", role: .destructive) { deleting = trip }
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("MileLog")
            .searchable(text: $search, prompt: "Find a place or purpose")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Filter trips", systemImage: "line.3.horizontal.decrease.circle") { showFilters = true } }
                ToolbarItem(placement: .topBarTrailing) { Button("Add trip", systemImage: "plus", action: addManual) }
            }
            .sheet(item: $editor) { presentation in
                TripEditor(original: presentation.original, initial: presentation.details, draftID: presentation.draftID, duplicateReview: presentation.duplicateReview) {
                    if presentation.draftID != nil { recorder.refresh() }
                }
            }
            .sheet(isPresented: $showFilters) {
                NavigationStack {
                    Form { ReportFilterFields(selection: $filters) }
                        .navigationTitle("Filter trips").navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button("Done") { showFilters = false }.disabled(!filters.valid) }
                }
            }
            .confirmationDialog("Delete this trip? Its edit history remains in backups.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete trip", role: .destructive) { if let deleting { store.perform { try store.delete(deleting) } }; deleting = nil }
            }
            .confirmationDialog("Discard this recording and its measured distance?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard recording", role: .destructive) { recorder.discard() }
            }
        }
    }

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(recorder.draft == nil ? "YOUR WORK. YOUR MILES." : "YOUR CURRENT TRIP", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.caption.weight(.semibold)).tracking(1).foregroundStyle(Color.mileMint)
            if let draft = recorder.draft {
                Text("\((draft.meters / DistanceCalculator.metersPerMile).formatted(.number.precision(.fractionLength(2)))) mi")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recorder.status).font(.subheadline)
                        if recorder.recording, let last = draft.last, context.date.timeIntervalSince(last.timestamp) > 30 {
                            Label("No recent location. Distance may be missing.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Color.mileMint)
                        }
                    }
                }
                if draft.interrupted { Label("Check for missing miles before saving", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Color.mileMint) }
                if recorder.recording {
                    adaptiveLayout {
                        Button("End trip", systemImage: "stop.circle.fill") { if recorder.end() { review() } }.buttonStyle(.borderedProminent).tint(Color.mileMint).foregroundStyle(Color.mileInk)
                        Button("Pause", systemImage: "pause.fill") { recorder.pause() }.buttonStyle(.bordered).tint(.white)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        adaptiveLayout {
                            if !draft.ended { Button("Resume", systemImage: "play.fill") { recorder.start() }.buttonStyle(.borderedProminent).tint(Color.mileMint).foregroundStyle(Color.mileInk) }
                            Button("Review & save") { if recorder.end() { review() } }.buttonStyle(.bordered).tint(.white)
                        }
                        Button("Discard recording", systemImage: "trash") { discard = true }.font(.subheadline).buttonStyle(.borderless).tint(.white)
                    }
                }
            } else {
                Text("Ready for your\nnext work trip?").font(.system(.title, design: .rounded, weight: .bold))
                Text("Start while parked. Keep recording through screen lock and navigation.").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                adaptiveLayout {
                    Button("Start trip", systemImage: "location.fill") { recorder.start() }.buttonStyle(.borderedProminent).tint(Color.mileMint).foregroundStyle(Color.mileInk)
                    Button("Add manually", systemImage: "plus", action: addManual).buttonStyle(.bordered).tint(.white)
                }
            }
            Text("Use trip controls only when safely parked.").font(.caption).foregroundStyle(.white.opacity(0.8))
        }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(22)
            .background(LinearGradient(colors: [.mileInk, .mileTeal], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
    }
    private var adaptiveLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 10))
    }
    private var monthSummary: some View {
        let business = store.trips.filter { $0.details.category == .business }
        let totals = Totals(trips: business, rates: store.data.rates, prefix: String(Day.string(Date()).prefix(7)))
        return Section {
            adaptiveLayout {
                MetricView(title: "Business miles", value: totals.businessMiles.formatted(.number.precision(.fractionLength(1))))
                MetricView(title: "Estimated deduction", value: totals.mileageAmount.money)
            }.padding(.vertical, 5)
            if totals.missingRates > 0 { Label("Some trips need a mileage rate. This estimate is incomplete.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
        } header: { Text("This month") } footer: { Text("Mileage only. An estimate of deductible expenses, not tax savings.") }
    }
    private func tripRow(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(trip.details.end.text).font(.headline).foregroundStyle(.primary)
                Spacer(minLength: 12)
                Text("\(trip.details.totalMiles.formatted(.number.precision(.fractionLength(1)))) mi")
                    .font(.headline).monospacedDigit().foregroundStyle(.primary)
            }
            Text("From \(trip.details.start.text)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if !trip.details.purpose.isEmpty { Text(trip.details.purpose).font(.subheadline).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                Text(trip.details.category.rawValue).font(.caption.weight(.medium)).foregroundStyle(Color.mileAccent)
                Text("· \(trip.details.method.rawValue)").font(.caption).foregroundStyle(.secondary)
                if let name = store.data.vehicles.first(where: { $0.id == trip.details.vehicleID })?.name {
                    Text("· \(name)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 7).accessibilityElement(children: .combine)
    }
    private func addManual() {
        var details = TripDetails(); details.vehicleID = store.defaultVehicleID
        editor = TripPresentation(details: details)
    }
    private func review() {
        editor = TripPresentation(details: recorder.details(), draftID: recorder.draft?.id, duplicateReview: recorder.draft?.needsDuplicateReview == true)
    }
}

struct ReportFilterFields: View {
    @Environment(LogStore.self) private var store
    @Binding var selection: ReportSelection
    var body: some View {
        Section("Dates") {
            Picker("Period", selection: $selection.period) { ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) } }
            if selection.period == .month || selection.period == .year {
                DatePicker("Period containing", selection: $selection.anchor, displayedComponents: .date)
                Text(selection.label).font(.subheadline).foregroundStyle(.secondary)
            } else if selection.period == .custom {
                DatePicker("From", selection: $selection.start, displayedComponents: .date)
                DatePicker("Through", selection: $selection.end, displayedComponents: .date)
                if !selection.valid { Text("Choose an end date on or after the start date.").foregroundStyle(.red) }
            }
        }
        Section("Include") {
            Picker("Category", selection: $selection.category) {
                Text("All categories").tag(nil as Category?)
                ForEach(Category.allCases) { Text($0.rawValue).tag(Optional($0)) }
            }
            Picker("Vehicle", selection: $selection.vehicleID) {
                Text("All vehicles").tag(nil as UUID?)
                ForEach(store.data.vehicles) { Text($0.name).tag(Optional($0.id)) }
            }
        }
    }
}

struct ReportsView: View {
    @Environment(LogStore.self) private var store
    @State private var file: ShareFile?
    @State private var error: String?
    var body: some View {
        @Bindable var store = store
        let trips = store.reportTrips
        let totals = Totals(trips: trips, rates: store.data.rates, prefix: "", employer: store.report.employer)
        NavigationStack {
            List {
                Section {
                    Label("A clear record for your next step", systemImage: "doc.text").font(.headline)
                    Text("Choose what to include. Review the totals. Share a report with your accountant or employer.").font(.subheadline).foregroundStyle(.secondary)
                }
                ReportFilterFields(selection: $store.report)
                Section("Calculation") {
                    Toggle("Use employer rates", isOn: $store.report.employer)
                    Text(store.report.employer ? "Uses your custom employer rate table. Add rates in Settings." : "Uses the IRS rate table by trip date. Eligibility depends on your circumstances.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Trips", value: String(trips.count))
                    LabeledContent("Logged miles", value: trips.reduce(0) { $0 + $1.details.totalMiles }.formatted(.number.precision(.fractionLength(1))))
                    LabeledContent("Business miles", value: totals.businessMiles.formatted(.number.precision(.fractionLength(1))))
                    LabeledContent(store.report.employer ? "Mileage reimbursement estimate" : "Mileage deduction estimate", value: totals.mileageAmount.money)
                    LabeledContent("Nonpersonal parking", value: totals.parking.money)
                    LabeledContent("Nonpersonal tolls", value: totals.tolls.money)
                    if totals.missingRates > 0 {
                        Label("\(totals.missingRates) trips have no matching rate. The estimate is incomplete; CSV amounts will be blank for those trips.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                } header: { Text(store.report.label) } footer: {
                    Text("Personal miles are included in logged miles when selected, but excluded from deduction/reimbursement estimates. Parking and tolls are separate from mileage.")
                }
                Section {
                    Button(action: export) {
                        Label("Export \(trips.count) trips as CSV", systemImage: "square.and.arrow.up")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.borderedProminent).tint(Color.mileTeal).foregroundStyle(.white).disabled(trips.isEmpty || !store.report.valid)
                    Text("Includes only the trips selected above, with dates, locations, purposes, vehicles, miles, rates, and expenses.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Reports").sheet(item: $file) { ShareSheet(url: $0.url) }.errorAlert($error)
        }
    }
    private func export() {
        do {
            var selected = store.data; selected.trips = store.reportTrips
            let csv = CSVExporter.export(selected, employer: store.report.employer)
            file = ShareFile(url: try store.writeFile(Data(csv.utf8), name: "MileLog-\(store.report.employer ? "employer" : "mileage")-\(Day.string(Date()))-\(UUID().uuidString.prefix(6)).csv"))
        } catch { self.error = error.localizedDescription }
    }
}
#Preview("Trips") { let s = PreviewData.store(); TripsView().environment(s).environment(LocationRecorder(store: s)) }
#Preview("Reports") { ReportsView().environment(PreviewData.store()) }
