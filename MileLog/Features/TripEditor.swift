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
    init(original: Trip? = nil, initial: TripDetails = TripDetails()) {
        self.original = original
        let d = original?.details ?? initial; details = d
        miles = d.miles == 0 ? "" : CSVExporter.number(d.miles)
        odoStart = d.odometerStart.map(CSVExporter.number) ?? ""; odoEnd = d.odometerEnd.map(CSVExporter.number) ?? ""
        parking = CSVExporter.decimal(d.parking); tolls = CSVExporter.decimal(d.tolls)
    }
    func number(_ text: String, optional: Bool = false) throws -> Double? {
        if optional && text.isEmpty { return nil }
        let f = NumberFormatter(); f.locale = .current; f.numberStyle = .decimal
        let normalized = text.replacingOccurrences(of: f.decimalSeparator ?? ".", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0 else { throw LogError("Enter a valid nonnegative number: \(text)") }
        return value
    }
    func save(store: LogStore, draftID: UUID?) -> Bool {
        do {
            var d = details
            d.miles = try number(miles) ?? 0
            d.odometerStart = try number(odoStart, optional: true); d.odometerEnd = try number(odoEnd, optional: true)
            d.parking = Decimal(try number(parking) ?? 0); d.tolls = Decimal(try number(tolls) ?? 0)
            if details.method == .gps && abs(d.miles - details.miles) > 0.00051 {
                d.method = .manual; d.notes += "\nManually corrected GPS mileage (original: \(CSVExporter.number(details.miles)) mi)."
            }
            try store.saveTrip(original, details: d, draftID: draftID, favorite: favorite, savePurpose: savePurpose)
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
    let draftID: UUID?
    let onSave: () -> Void
    enum LocationField: String, Identifiable { case start, end; var id: String { rawValue } }
    init(original: Trip? = nil, initial: TripDetails = TripDetails(), draftID: UUID? = nil, onSave: @escaping () -> Void = {}) {
        _model = State(initialValue: TripEditorModel(original: original, initial: initial)); self.draftID = draftID; self.onSave = onSave
    }
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Trip") {
                    DatePicker("Date", selection: Binding(get: { Day.date(model.details.day) ?? Date() }, set: { model.details.day = Day.string($0) }), displayedComponents: .date)
                    Picker("Vehicle", selection: $model.details.vehicleID) {
                        Text("No vehicle").tag(nil as UUID?)
                        ForEach(store.data.vehicles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Category", selection: $model.details.category) { ForEach(Category.allCases) { Text($0.rawValue).tag($0) } }
                }
                Section("Route") {
                    locationRow("Start location", field: .start)
                    locationRow("End location", field: .end)
                    if !recentPlaces.isEmpty {
                        Menu("Recent places") {
                            ForEach(recentPlaces, id: \.text) { place in
                                Menu(place.text) { Button("Use as start") { model.details.start = place }; Button("Use as end") { model.details.end = place } }
                            }
                        }
                    }
                    TextField(model.details.roundTrip ? "One-way miles" : "Miles driven", text: $model.miles).keyboardType(.decimalPad)
                    if model.details.method == .manual {
                        Toggle("Round trip (double miles)", isOn: $model.details.roundTrip)
                        if model.details.roundTrip { Text("The end location is the turnaround destination. Enter one-way miles; the log includes the return.").font(.caption).foregroundStyle(.secondary) }
                    }
                    LabeledContent("Recorded via", value: model.details.method.rawValue)
                    if model.details.method == .gps { Text("Confirm the endpoint addresses and distance. Correcting GPS miles changes the saved source to Manual and preserves the original distance in notes.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Purpose") {
                    TextField(model.details.category == .business ? "Business purpose (required)" : "Purpose", text: $model.details.purpose, axis: .vertical)
                    Menu("Recent & saved purposes") { ForEach(purposes, id: \.self) { p in Button(p) { model.details.purpose = p } } }
                    Toggle("Save purpose for reuse", isOn: $model.savePurpose)
                }
                Section("Optional details") {
                    TextField("Odometer start", text: $model.odoStart).keyboardType(.decimalPad)
                    TextField("Odometer end", text: $model.odoEnd).keyboardType(.decimalPad)
                    LabeledContent("Parking ($)") { TextField("0", text: $model.parking).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    LabeledContent("Tolls ($)") { TextField("0", text: $model.tolls).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    TextField("Notes", text: $model.details.notes, axis: .vertical)
                    TextField("Save as frequent trip (name)", text: $model.favorite)
                }
                if let original = model.original {
                    Section("Record history") {
                        LabeledContent("Created", value: original.createdAt.formatted())
                        LabeledContent("Last edited", value: original.updatedAt.formatted())
                        ForEach(original.history.reversed()) { event in
                            DisclosureGroup("\(event.action) · \(event.at.formatted())") {
                                Text("\(event.details.day) · \(event.details.category.rawValue)")
                                Text("\(event.details.start.text) → \(event.details.end.text)")
                                Text("\(event.details.totalMiles.formatted()) mi · \(event.details.method.rawValue)")
                                Text(event.details.purpose)
                                Text(event.details.notes).font(.caption)
                            }
                        }
                    }
                }
            }.navigationTitle(model.original == nil ? "Log a trip" : "Edit trip").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { confirmCancel = true } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if model.save(store: store, draftID: draftID) { onSave(); dismiss() } }.bold() }
                }
                .interactiveDismissDisabled()
                .confirmationDialog("Discard unsaved form changes? GPS recordings remain saved as drafts.", isPresented: $confirmCancel, titleVisibility: .visible) { Button("Discard changes", role: .destructive) { dismiss() } }
                .errorAlert($model.error)
                .sheet(item: $lookup) { field in PlaceSearchView(initial: field == .start ? model.details.start.text : model.details.end.text) { place in if field == .start { model.details.start = place } else { model.details.end = place } } }
        }
    }
    @ViewBuilder private func locationRow(_ title: String, field: LocationField) -> some View {
        HStack {
            TextField(title, text: Binding(get: { field == .start ? model.details.start.text : model.details.end.text }, set: { text in
                if field == .start {
                    if model.details.method == .gps { model.details.start.text = text } else { model.details.start = Place(text: text) }
                } else {
                    if model.details.method == .gps { model.details.end.text = text } else { model.details.end = Place(text: text) }
                }
            }))
            Button { lookup = field } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Look up \(title)")
        }
    }
    private var recentPlaces: [Place] {
        var seen = Set<String>(); return store.trips.flatMap { [$0.details.start, $0.details.end] }.filter { !$0.text.isEmpty && seen.insert($0.text).inserted }.prefix(10).map { $0 }
    }
    private var purposes: [String] {
        var seen = Set<String>(); return (store.data.purposes.map(\.text) + store.trips.map { $0.details.purpose }).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(12).map { $0 }
    }
}
#Preview("Trip editor") { TripEditor().environment(PreviewData.store()) }
