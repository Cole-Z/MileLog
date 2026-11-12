import SwiftUI

@MainActor @Observable final class TripEditorModel {
    var details: TripDetails
    var miles: String
    var odoStart: String
    var odoEnd: String
    var parking: String
    var tolls: String
    var favorite = ""
    var savePurpose = false
    var error: String?
    let original: Trip?
    private let initialDetails: TripDetails

    init(original: Trip? = nil, initial: TripDetails = TripDetails()) {
        self.original = original
        let details = original?.details ?? initial
        self.details = details; initialDetails = details
        miles = details.miles == 0 ? "" : Self.display(details.miles)
        odoStart = details.odometerStart.map(Self.display) ?? ""
        odoEnd = details.odometerEnd.map(Self.display) ?? ""
        parking = Self.displayMoney(details.parking); tolls = Self.displayMoney(details.tolls)
    }
    static func display(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
    }
    static func displayMoney(_ value: Decimal) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }
    private func normalized(_ text: String) -> String {
        let formatter = NumberFormatter(); formatter.locale = .current
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: formatter.decimalSeparator ?? ".", with: ".")
    }
    func number(_ text: String, optional: Bool = false) throws -> Double? {
        let text = normalized(text)
        if optional && text.isEmpty { return nil }
        guard let value = Double(text), value.isFinite, value >= 0 else { throw LogError("Enter a valid nonnegative number.") }
        return value
    }
    private func money(_ text: String) throws -> Decimal {
        let normalized = normalized(text)
        if normalized.isEmpty { return 0 }
        guard let value = Double(normalized), value.isFinite, value >= 0,
              var decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), !decimal.isNaN else {
            throw LogError("Enter a valid amount for parking and tolls.")
        }
        var rounded = Decimal(); NSDecimalRound(&rounded, &decimal, 2, .plain)
        return rounded
    }
    var previewDetails: TripDetails? {
        guard let miles = try? number(miles), miles > 0 else { return nil }
        var details = self.details; details.miles = miles; return details
    }
    var hasChanges: Bool {
        details != initialDetails || !favorite.isEmpty || savePurpose ||
        miles != (initialDetails.miles == 0 ? "" : Self.display(initialDetails.miles)) ||
        odoStart != (initialDetails.odometerStart.map(Self.display) ?? "") ||
        odoEnd != (initialDetails.odometerEnd.map(Self.display) ?? "") ||
        parking != Self.displayMoney(initialDetails.parking) || tolls != Self.displayMoney(initialDetails.tolls)
    }
    func useOdometers() {
        do {
            guard let start = try number(odoStart), let end = try number(odoEnd), end > start else {
                throw LogError("Enter an end odometer greater than the start.")
            }
            miles = Self.display(end - start)
            details.roundTrip = false
        } catch { self.error = error.localizedDescription }
    }
    func save(store: LogStore, draftID: UUID?) -> Bool {
        do {
            var details = self.details
            details.miles = try number(miles) ?? 0
            details.odometerStart = try number(odoStart, optional: true)
            details.odometerEnd = try number(odoEnd, optional: true)
            details.parking = try money(parking); details.tolls = try money(tolls)
            details.purpose = details.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            if self.details.method == .gps && abs(details.miles - self.details.miles) > 0.00051 {
                details.method = .manual
                details.notes += "\nManually corrected GPS mileage (original: \(CSVExporter.number(self.details.miles)) mi)."
            }
            try store.saveTrip(original, details: details, draftID: draftID, favorite: favorite, savePurpose: savePurpose)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

struct TripEditor: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var model: TripEditorModel
    @State private var lookup: LocationField?
    @State private var confirmCancel = false
    @State private var addVehicle = false
    @State private var reviewedDuplicate = false
    @FocusState private var inputFocused: Bool
    let draftID: UUID?
    let duplicateReview: Bool
    let onSave: () -> Void
    enum LocationField: String, Identifiable { case start, end; var id: String { rawValue } }
    init(original: Trip? = nil, initial: TripDetails = TripDetails(), draftID: UUID? = nil, duplicateReview: Bool = false, onSave: @escaping () -> Void = {}) {
        _model = State(initialValue: TripEditorModel(original: original, initial: initial))
        self.draftID = draftID; self.duplicateReview = duplicateReview; self.onSave = onSave
    }
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                if duplicateReview {
                    Section("Restored recording") {
                        Label("This draft came from a backup. Check your log before saving another copy of the same drive.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Toggle("I checked that this trip isn't already logged", isOn: $reviewedDuplicate)
                    }
                }
                Section("Trip details") {
                    DatePicker("Date", selection: Binding(get: { Day.date(model.details.day) ?? Date() }, set: { model.details.day = Day.string($0) }), displayedComponents: .date)
                    Picker("Vehicle", selection: $model.details.vehicleID) {
                        Text("No vehicle").tag(nil as UUID?)
                        ForEach(store.data.vehicles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if store.data.vehicles.isEmpty { Button("Add your vehicle", systemImage: "car.badge.gearshape") { inputFocused = false; addVehicle = true } }
                    Picker("Category", selection: $model.details.category) { ForEach(Category.allCases) { Text($0.rawValue).tag($0) } }
                }
                Section("Where did you go?") {
                    locationRow("Start location", field: .start)
                    locationRow("Destination", field: .end)
                    if !recentPlaces.isEmpty {
                        Menu("Use a recent place", systemImage: "clock") {
                            ForEach(recentPlaces, id: \.text) { place in
                                Menu(place.text) {
                                    Button("Use as start") { model.details.start = place }
                                    Button("Use as destination") { model.details.end = place }
                                }
                            }
                        }
                    }
                }
                Section {
                    LabeledContent(model.details.roundTrip ? "One-way miles" : "Miles driven") {
                        TextField("0.0", text: $model.miles).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).focused($inputFocused).accessibilityLabel("Miles driven")
                    }
                    if model.details.method == .manual { Toggle("Round trip", isOn: $model.details.roundTrip) }
                    if let preview = model.previewDetails {
                        LabeledContent("Total distance", value: "\(preview.totalMiles.formatted(.number.precision(.fractionLength(1...3)))) mi")
                        if let estimate = RateLookup.amount(for: preview, rates: store.data.rates), preview.category != .personal {
                            LabeledContent("Mileage estimate", value: estimate.money).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Distance") } footer: {
                    if model.details.roundTrip { Text("Enter one-way miles. The total includes the return; your destination is the turnaround point.") }
                    else if model.details.method == .gps { Text("Measured by GPS. Verify the distance and endpoints. Editing the mileage records a manual correction and keeps the original distance in notes.") }
                }
                Section {
                    TextField(model.details.category == .business ? "What was the business purpose?" : "Purpose (optional)", text: $model.details.purpose, axis: .vertical)
                        .focused($inputFocused)
                    if !purposes.isEmpty {
                        Menu("Choose a purpose", systemImage: "text.badge.checkmark") {
                            ForEach(purposes, id: \.self) { purpose in Button(purpose) { model.details.purpose = purpose } }
                        }
                    }
                } header: { Text("Purpose") } footer: {
                    if model.details.category == .business { Text("Be specific, such as “Client meeting at Acme” or “Materials for the Oak Street job.”") }
                }
                Section("Optional details") {
                    DisclosureGroup("Odometer readings") {
                        TextField("Start odometer", text: $model.odoStart).keyboardType(.decimalPad).focused($inputFocused)
                        TextField("End odometer", text: $model.odoEnd).keyboardType(.decimalPad).focused($inputFocused)
                        Button("Use odometer difference as total miles") { model.useOdometers() }
                        Text("This uses the full distance driven and turns off round-trip doubling.").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Parking, tolls & notes") {
                        LabeledContent("Parking ($)") { TextField("0", text: $model.parking).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($inputFocused).accessibilityLabel("Parking dollars") }
                        LabeledContent("Tolls ($)") { TextField("0", text: $model.tolls).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($inputFocused).accessibilityLabel("Toll dollars") }
                        TextField("Notes", text: $model.details.notes, axis: .vertical).focused($inputFocused)
                    }
                    DisclosureGroup("Save for next time") {
                        Toggle("Reuse this purpose", isOn: $model.savePurpose)
                        TextField("Quick-add trip name (optional)", text: $model.favorite).focused($inputFocused)
                        Text("A quick-add trip reuses this route and mileage with today's date. Review the details before saving.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let original = model.original {
                    Section {
                        DisclosureGroup("Record history · \(original.history.count) events") {
                            LabeledContent("Created", value: original.createdAt.formatted())
                            LabeledContent("Last edited", value: original.updatedAt.formatted())
                            ForEach(original.history.reversed()) { event in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(event.action) · \(event.at.formatted())").font(.caption.weight(.semibold))
                                    Text("\(event.details.start.text) → \(event.details.end.text)")
                                    Text("\(event.details.totalMiles.formatted()) mi · \(event.details.category.rawValue)")
                                    Text(event.details.purpose)
                                    if !event.details.notes.isEmpty { Text(event.details.notes).font(.caption) }
                                }
                            }
                        }
                    }
                }
            }.navigationTitle(model.original == nil ? "Add a trip" : "Edit trip").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if model.hasChanges { confirmCancel = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { if model.save(store: store, draftID: draftID) { onSave(); dismiss() } }
                            .bold().disabled(duplicateReview && !reviewedDuplicate)
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { inputFocused = false } }
                }
                .interactiveDismissDisabled()
                .confirmationDialog("Discard unsaved changes? Your GPS draft will remain available.", isPresented: $confirmCancel, titleVisibility: .visible) {
                    Button("Discard changes", role: .destructive) { dismiss() }
                }
                .errorAlert($model.error)
                .sheet(isPresented: $addVehicle) { VehicleEditor(vehicle: Vehicle()) { vehicle in model.details.vehicleID = vehicle.id } }
                .sheet(item: $lookup) { field in
                    PlaceSearchView(initial: field == .start ? model.details.start.text : model.details.end.text) { place in
                        if field == .start { model.details.start = place } else { model.details.end = place }
                    }
                }
        }
    }
    private func locationRow(_ title: String, field: LocationField) -> some View {
        HStack {
            TextField(title, text: Binding(get: { field == .start ? model.details.start.text : model.details.end.text }, set: { text in
                if field == .start {
                    if model.details.method == .gps { model.details.start.text = text } else { model.details.start = Place(text: text) }
                } else {
                    if model.details.method == .gps { model.details.end.text = text } else { model.details.end = Place(text: text) }
                }
            })).focused($inputFocused)
            Button { inputFocused = false; lookup = field } label: { Image(systemName: "magnifyingglass").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Look up \(title)")
        }
    }
    private var recentPlaces: [Place] {
        var seen = Set<String>()
        return store.trips.flatMap { [$0.details.start, $0.details.end] }
            .filter { !$0.text.isEmpty && seen.insert($0.text).inserted }.prefix(10).map { $0 }
    }
    private var purposes: [String] {
        var seen = Set<String>()
        return (store.data.purposes.map(\.text) + store.trips.map { $0.details.purpose })
            .filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(12).map { $0 }
    }
}
#Preview("Trip editor") { TripEditor().environment(PreviewData.store()) }
