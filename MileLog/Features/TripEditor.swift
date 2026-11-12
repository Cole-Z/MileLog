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
    var refreshRates = false
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
    var proposedDetails: TripDetails {
        let parsed = (try? number(miles)) ?? 0
        var details = self.details
        details.miles = Recordkeeping.retainedDistance(stored: initialDetails.miles, displayed: initialDetails.miles == 0 ? "" : Self.display(initialDetails.miles), entered: miles, parsed: parsed)
        details.status = Recordkeeping.issues(details).isEmpty ? .complete : .incomplete
        return details
    }
    var previewDetails: TripDetails? { proposedDetails.miles > 0 ? proposedDetails : nil }
    var hasChanges: Bool {
        details != initialDetails || !favorite.isEmpty || savePurpose || refreshRates ||
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
            miles = (end - start).formatted(.number.grouping(.never).precision(.significantDigits(1...17)))
            details.roundTrip = false
        } catch { self.error = error.localizedDescription }
    }
    func save(store: LogStore, draftID: UUID?) -> Bool {
        do {
            var details = self.details
            let parsed = miles.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : (try number(miles) ?? 0)
            details.miles = Recordkeeping.retainedDistance(stored: initialDetails.miles, displayed: initialDetails.miles == 0 ? "" : Self.display(initialDetails.miles), entered: miles, parsed: parsed)
            details.odometerStart = odoStart == (initialDetails.odometerStart.map(Self.display) ?? "") ? initialDetails.odometerStart : try number(odoStart, optional: true)
            details.odometerEnd = odoEnd == (initialDetails.odometerEnd.map(Self.display) ?? "") ? initialDetails.odometerEnd : try number(odoEnd, optional: true)
            details.parking = try money(parking); details.tolls = try money(tolls)
            details.purpose = details.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            details.status = Recordkeeping.issues(details).isEmpty ? .complete : .incomplete
            try store.saveTrip(original, details: details, draftID: draftID, favorite: favorite, savePurpose: savePurpose, refreshRates: refreshRates)
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
    @State private var geocoding = false
    @State private var geocodeMessage: String?
    @State private var geocoder = EndpointGeocoder()
    @State private var reviewedDuplicate = false
    @State private var namingDestination = false
    @State private var destinationName = ""
    @FocusState private var inputFocused: Bool
    @FocusState private var locationFocus: LocationField?
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
                Section {
                    let pending = Recordkeeping.issues(model.proposedDetails)
                    if pending.isEmpty {
                        Label("Required details supplied", systemImage: "checkmark.circle").foregroundStyle(Color.mileAccent)
                    } else {
                        Label("Will save as incomplete", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                        Text(pending.joined(separator: " · ")).font(.caption)
                        if needsDestinationName {
                            destinationNameButton
                        }
                    }
                    Text("Incomplete records stay visible in reports, with blank estimate amounts. Completeness does not establish tax eligibility.").font(.caption).foregroundStyle(.secondary)
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
                    locationRow("Destination / business location", field: .end)
                    if model.details.start.latitude != nil || model.details.end.latitude != nil {
                        Button(geocoding ? "Looking up addresses…" : "Look up recorded endpoint addresses", systemImage: "mappin.and.ellipse") { lookupEndpoints() }.disabled(geocoding)
                        Text("Sends endpoint coordinates to Apple's geocoding service when tapped. Original coordinates stay unchanged; typing labels works offline.").font(.caption).foregroundStyle(.secondary)
                        if let geocodeMessage { Text(geocodeMessage).font(.caption).foregroundStyle(.secondary) }
                    }
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
                        if Recordkeeping.isComplete(preview), let estimate = previewEstimate(preview), preview.category != .personal {
                            LabeledContent("Mileage estimate", value: estimate.money).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Distance") } footer: {
                    if model.details.roundTrip { Text("Enter one-way miles. The total includes the return; your destination is the turnaround point.") }
                    else if model.details.method == .gps { Text("Measured by GPS. Verify the distance and endpoints. Corrections require a reason and leave original GPS evidence unchanged.") }
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
                if model.details.method == .gps || model.original?.gpsEvidence != nil {
                    Section("Original recording & corrections") {
                        if let evidence = model.original?.gpsEvidence {
                            LabeledContent("Original GPS miles", value: CSVExporter.precise(evidence.meters / DistanceCalculator.metersPerMile))
                            LabeledContent("Original meters", value: CSVExporter.precise(evidence.meters))
                            Text("Original endpoints: \(evidence.first?.place.text ?? "Unavailable") → \(evidence.last?.place.text ?? "Unavailable")").font(.caption)
                            Text("Original start: \(evidence.startedAt.formatted()) [\(evidence.startTimeZoneID ?? "Zone unknown")]").font(.caption)
                            Text("Original end: \(evidence.endedAt?.formatted() ?? "Not recorded") [\(evidence.endTimeZoneID ?? "Zone unknown")]").font(.caption)
                            if evidence.interrupted { Label("Recording had gaps; verify the distance", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                        } else if model.original != nil { Text("Original GPS evidence was not separately stored by the earlier app version.").font(.caption) }
                        TextField("Reason for correcting distance, coordinates, or times", text: optionalText(\.correctionReason), axis: .vertical).focused($inputFocused)
                    }
                }
                Section("Optional details") {
                    DisclosureGroup("Times & time zones") {
                        Toggle("Record start/end times", isOn: Binding(get: { model.details.startedAt != nil }, set: { enabled in
                            if enabled {
                                let day = Day.date(model.details.day) ?? Date()
                                model.details.startedAt = day; model.details.endedAt = day
                                model.details.startTimeZoneID = TimeZone.current.identifier; model.details.endTimeZoneID = TimeZone.current.identifier
                            } else { model.details.startedAt = nil; model.details.endedAt = nil; model.details.startTimeZoneID = nil; model.details.endTimeZoneID = nil }
                        }))
                        if model.details.startedAt != nil {
                            DatePicker("Started", selection: Binding(get: { model.details.startedAt ?? Date() }, set: { model.details.startedAt = $0 }))
                            DatePicker("Ended", selection: Binding(get: { model.details.endedAt ?? model.details.startedAt ?? Date() }, set: { model.details.endedAt = $0 }))
                            TextField("Start time zone (e.g. America/Chicago)", text: optionalText(\.startTimeZoneID)).textInputAutocapitalization(.never)
                            TextField("End time zone", text: optionalText(\.endTimeZoneID)).textInputAutocapitalization(.never)
                            Text("Times display in this device's time zone. The recorded zone identifiers and UTC instants are retained in exports.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    DisclosureGroup("Odometer readings") {
                        TextField("Start odometer", text: $model.odoStart).keyboardType(.decimalPad).focused($inputFocused)
                        TextField("End odometer", text: $model.odoEnd).keyboardType(.decimalPad).focused($inputFocused)
                        Button("Use odometer difference as total miles") { model.useOdometers() }
                        Text("This uses the full distance driven and turns off round-trip doubling.").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Parking, tolls & notes") {
                        LabeledContent("Parking ($)") { TextField("0", text: $model.parking).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($inputFocused).accessibilityLabel("Parking dollars") }
                        LabeledContent("Tolls ($)") { TextField("0", text: $model.tolls).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($inputFocused).accessibilityLabel("Toll dollars") }
                        TextField("Parking description", text: optionalText(\.parkingDescription)).focused($inputFocused)
                        TextField("Toll description", text: optionalText(\.tollsDescription)).focused($inputFocused)
                        TextField("Receipt/reference note (optional)", text: optionalText(\.evidenceReference)).focused($inputFocused)
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
                        Toggle("Refresh this trip's saved rates", isOn: $model.refreshRates)
                        Text("Saved rate snapshots keep estimates stable when the rate table changes. Refreshing, or changing the trip date/category, uses the matching current table and records an edit.").font(.caption).foregroundStyle(.secondary)
                        if let note = original.rateCaptureNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                        DisclosureGroup("Record history · \(original.history.count) events") {
                            LabeledContent("Created", value: original.createdAt.formatted())
                            LabeledContent("Last edited", value: original.updatedAt.formatted())
                            ForEach(original.history.reversed()) { event in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(event.action) · \(event.at.formatted())").font(.caption.weight(.semibold))
                                    Text("\(event.details.start.text) → \(event.details.end.text)")
                                    Text("\(event.details.totalMiles.formatted()) mi · \(event.details.category.rawValue)")
                                    Text(event.details.purpose)
                                    if let reason = event.details.correctionReason { Text("Correction: \(reason)").font(.caption) }
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
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { inputFocused = false; locationFocus = nil } }
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
    private func optionalText(_ path: WritableKeyPath<TripDetails, String?>) -> Binding<String> {
        Binding(get: { model.details[keyPath: path] ?? "" }, set: { model.details[keyPath: path] = $0.isEmpty ? nil : $0 })
    }
    private func previewEstimate(_ details: TripDetails) -> Decimal? {
        if var trip = model.original, !model.refreshRates, trip.details.day == details.day, trip.details.category == details.category {
            trip.details = details
            return RateLookup.amount(for: trip, rates: store.data.rates)
        }
        return RateLookup.amount(for: details, rates: store.data.rates)
    }
    private func lookupEndpoints() {
        inputFocused = false; locationFocus = nil
        geocoding = true; geocodeMessage = nil
        let start = model.details.start, end = model.details.end
        Task { @MainActor in
            defer { geocoding = false }
            var failures = 0
            for (place, isStart) in [(start, true), (end, false)] where place.latitude != nil && place.longitude != nil {
                do {
                    let label = try await geocoder.label(for: place)
                    // Do not replace a newer user edit while an async request was in flight.
                    if isStart && model.details.start == start { model.details.start.text = label }
                    if !isStart && model.details.end == end { model.details.end.text = label }
                } catch { failures += 1 }
            }
            geocodeMessage = failures == 0 ? "Endpoint labels updated. Review them, then tap Save." : "Some addresses are unavailable. Tap Name destination in the banner or type a place name in the labeled field."
        }
    }
    private var needsDestinationName: Bool {
        model.details.end.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            (model.details.category == .business && Recordkeeping.isCoordinateLabel(model.details.end.text))
    }
    private var destinationNameButton: some View {
        Button("Name destination", systemImage: "pencil") { presentDestinationName() }
            .buttonStyle(.borderless).frame(minHeight: 44)
            .alert("Name destination", isPresented: $namingDestination) {
                TextField("Place name and street or city", text: $destinationName)
                Button("Use name") { model.details.end.text = destinationName.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .disabled(destinationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Recordkeeping.isCoordinateLabel(destinationName))
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Describe where you went. For a return trip, include the business stop and where you ended. Your GPS coordinates and miles stay unchanged. Then tap Save on the trip.")
            }
    }
    private func presentDestinationName() {
        inputFocused = false; locationFocus = nil
        destinationName = Recordkeeping.isCoordinateLabel(model.details.end.text) ? "" : model.details.end.text
        namingDestination = true
    }
    private func locationRow(_ title: String, field: LocationField) -> some View {
        let place = field == .start ? model.details.start : model.details.end
        let coordinateLabel = Recordkeeping.isCoordinateLabel(place.text)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium))
            HStack(alignment: .top) {
                TextField("Type a place name or address", text: Binding(get: {
                    let text = field == .start ? model.details.start.text : model.details.end.text
                    return Recordkeeping.isCoordinateLabel(text) ? "" : text
                }, set: { text in
                    if field == .start {
                        if model.details.method == .gps { model.details.start.text = text } else { model.details.start = Place(text: text) }
                    } else {
                        if model.details.method == .gps { model.details.end.text = text } else { model.details.end = Place(text: text) }
                    }
                }), axis: .vertical)
                    .textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    .focused($locationFocus, equals: field)
                    .accessibilityLabel(title)
                    .accessibilityHint(model.details.method == .gps ? "Enter a place name or address. Recorded GPS coordinates are retained." : "Enter a place name or address.")
                Button { inputFocused = false; locationFocus = nil; lookup = field } label: {
                    Image(systemName: "magnifyingglass").frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless).accessibilityLabel("Look up \(title)")
            }
            if coordinateLabel {
                Text(field == .end && model.details.category == .business ? "Add the destination's name to complete this business record." : "A GPS location is recorded. You can add a name for easier reading.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let latitude = place.latitude, let longitude = place.longitude {
                DisclosureGroup("Location coordinates") {
                    Text("\(CSVExporter.precise(latitude)), \(CSVExporter.precise(longitude))").font(.caption).textSelection(.enabled)
                }.font(.caption).foregroundStyle(.secondary)
            }
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
