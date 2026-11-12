import SwiftUI

struct VehiclesView: View {
    @Environment(LogStore.self) private var store
    @State private var editing: Vehicle?
    var body: some View {
        List {
            if store.data.vehicles.isEmpty { ContentUnavailableView("Add your vehicle", systemImage: "car", description: Text("Keep yearly odometer readings for each vehicle you use.")) }
            ForEach(store.data.vehicles) { vehicle in
                Button { editing = vehicle } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(vehicle.name).font(.headline); if store.defaultVehicleID == vehicle.id { Text("Default").font(.caption).foregroundStyle(.secondary) } }
                        Text([vehicle.year, vehicle.make, vehicle.model].filter { !$0.isEmpty }.joined(separator: " ")).font(.caption).foregroundStyle(.secondary)
                        ForEach(vehicle.years.sorted { $0.year > $1.year }) { year in
                            let annual = AnnualVehicleSummary(vehicle: vehicle, year: year.year, trips: store.trips)
                            if let percent = annual.businessPercent {
                                Text("\(String(year.year)): \(percent.formatted(.number.precision(.fractionLength(1))))% business use").font(.subheadline)
                            } else { Text("\(String(year.year)): \(annual.incompleteTrips > 0 ? "Incomplete business records need review." : annual.note)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }.navigationTitle("Vehicles").toolbar { Button("Add vehicle", systemImage: "plus") { editing = Vehicle() } }
            .sheet(item: $editing) { VehicleEditor(vehicle: $0) }
    }
}
struct VehicleEditor: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var vehicle: Vehicle
    @State private var error: String?
    @State private var makeDefault = false
    var onSave: (Vehicle) -> Void
    init(vehicle: Vehicle, onSave: @escaping (Vehicle) -> Void = { _ in }) {
        _vehicle = State(initialValue: vehicle)
        self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    TextField("Name (required)", text: $vehicle.name)
                    TextField("Year", text: $vehicle.year).keyboardType(.numberPad)
                    TextField("Make", text: $vehicle.make)
                    TextField("Model", text: $vehicle.model)
                    TextField("Plate (optional)", text: $vehicle.plate)
                    Toggle("Use as my default vehicle", isOn: $makeDefault).disabled(store.defaultVehicleID == vehicle.id || store.data.vehicles.isEmpty)
                }
                Section {
                    NavigationLink("Annual odometer records") { AnnualOdometerView(vehicle: $vehicle) }
                } footer: { Text("Keep yearly readings and business-service details. Partial-year records are not presented as annual totals.") }
            }.navigationTitle("Vehicle").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.bold() }
            }.errorAlert($error).interactiveDismissDisabled().scrollDismissesKeyboard(.interactively)
                .onAppear { makeDefault = store.defaultVehicleID == vehicle.id || store.data.vehicles.isEmpty }
        }
    }
    private func save() {
        do { try store.saveVehicle(vehicle, makeDefault: makeDefault); onSave(vehicle); dismiss() } catch { self.error = error.localizedDescription }
    }
}
#Preview("Vehicles") { NavigationStack { VehiclesView().environment(PreviewData.store()) } }
#Preview("Vehicle editor") { VehicleEditor(vehicle: Vehicle()).environment(PreviewData.store()) }

struct AnnualOdometerView: View {
    @Binding var vehicle: Vehicle
    var body: some View {
        Form {
            ForEach($vehicle.years) { $year in
                Section("Tax year \(String(year.year))") { AnnualReadingFields(year: $year) }
            }.onDelete { vehicle.years.remove(atOffsets: $0) }
            Button("Add tax year") {
                let current = Calendar(identifier: .gregorian).component(.year, from: Date())
                let next = vehicle.years.map(\.year).max().map { $0 + 1 } ?? current
                vehicle.years.append(VehicleYear(year: next, startRecorded: false, fullYearConfirmed: false))
            }
            Section("First placed in business service (optional)") {
                Toggle("Include service date and reading", isOn: Binding(get: { vehicle.businessServiceDay != nil }, set: { enabled in
                    vehicle.businessServiceDay = enabled ? Day.string(Date()) : nil
                    vehicle.businessServiceOdometer = enabled ? 0 : nil
                }))
                if vehicle.businessServiceDay != nil {
                    DatePicker("Service date", selection: Binding(get: { Day.date(vehicle.businessServiceDay ?? "") ?? Date() }, set: { vehicle.businessServiceDay = Day.string($0) }), displayedComponents: .date)
                    TextField("Odometer at first business use", value: $vehicle.businessServiceOdometer, format: .number.grouping(.never)).keyboardType(.decimalPad)
                }
            }
            Section {
                TextField("Reason for changing existing readings", text: Binding(get: { vehicle.odometerCorrectionReason ?? "" }, set: { vehicle.odometerCorrectionReason = $0 }), axis: .vertical)
                Text("Save from the Vehicle screen. Corrections preserve prior readings and require a reason. These are your recorded readings, not independently verified mileage.").font(.caption).foregroundStyle(.secondary)
            }
            if let history = vehicle.odometerHistory, !history.isEmpty {
                Section("Odometer edit history") {
                    ForEach(history.reversed()) { event in
                        DisclosureGroup(event.at.formatted()) {
                            Text(event.reason)
                            ForEach(event.years) { year in Text("\(String(year.year)): \(year.start.formatted()) → \(year.end?.formatted() ?? "Not entered") mi").font(.caption) }
                            if let day = event.serviceDay { Text("Business service: \(day), \(event.serviceOdometer?.formatted() ?? "Unknown") mi").font(.caption) }
                        }
                    }
                }
            }
        }.navigationTitle("Annual odometers").navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
    }
}
private struct AnnualReadingFields: View {
    @Binding var year: VehicleYear
    var body: some View {
        TextField("Tax year", value: $year.year, format: .number.grouping(.never)).keyboardType(.numberPad)
        Toggle("Beginning reading confirmed", isOn: Binding(get: { year.startRecorded == true }, set: { year.startRecorded = $0; if !$0 { year.fullYearConfirmed = false } }))
        LabeledContent("Beginning odometer") { TextField("Miles", value: $year.start, format: .number.grouping(.never)).keyboardType(.decimalPad) }
        DatePicker("Beginning date", selection: Binding(get: { Day.date(year.startDay ?? "\(year.year)-01-01") ?? Date() }, set: { year.startDay = Day.string($0); year.fullYearConfirmed = false }), displayedComponents: .date)
        if year.startDay == nil { Text("Beginning date is not confirmed.").font(.caption).foregroundStyle(.orange) }
        LabeledContent("Ending odometer") { TextField("Optional", value: $year.end, format: .number.grouping(.never)).keyboardType(.decimalPad) }
        DatePicker("Ending date", selection: Binding(get: { Day.date(year.endDay ?? "\(year.year)-12-31") ?? Date() }, set: { year.endDay = Day.string($0); year.fullYearConfirmed = false }), displayedComponents: .date)
        if year.endDay == nil { Text("Ending date is not confirmed.").font(.caption).foregroundStyle(.orange) }
        Button("Set dates to January 1 and December 31") { year.startDay = "\(year.year)-01-01"; year.endDay = "\(year.year)-12-31"; year.fullYearConfirmed = false }
        Toggle("Confirm these cover the entire year", isOn: Binding(get: { year.fullYearConfirmed == true }, set: { year.fullYearConfirmed = $0 }))
            .disabled(year.startRecorded != true || year.end == nil || year.startDay != "\(year.year)-01-01" || year.endDay != "\(year.year)-12-31" || "\(year.year)-12-31" > Day.string(Date()))
        if let end = year.end, end >= year.start { LabeledContent("Recorded period miles", value: (end - year.start).formatted()) }
        if year.fullYearConfirmed != true { Text("Partial or unconfirmed period — annual total unavailable.").font(.caption).foregroundStyle(.secondary) }
    }
}
