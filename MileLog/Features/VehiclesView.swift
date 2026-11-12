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
                        Text(vehicle.name).font(.headline)
                        Text([vehicle.year, vehicle.make, vehicle.model].filter { !$0.isEmpty }.joined(separator: " ")).font(.caption).foregroundStyle(.secondary)
                        ForEach(vehicle.years.sorted { $0.year > $1.year }) { year in
                            if let percent = Totals.businessUse(vehicle: vehicle, year: year, trips: store.trips) {
                                Text("\(String(year.year)): \(percent.formatted(.number.precision(.fractionLength(1))))% business use").font(.subheadline)
                                if percent > 100 { Text("Business miles exceed annual odometer miles. Review your records.").font(.caption).foregroundStyle(.orange) }
                            } else { Text("\(String(year.year)): add both odometer readings to calculate use").font(.caption).foregroundStyle(.secondary) }
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
    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    TextField("Name (required)", text: $vehicle.name)
                    TextField("Year", text: $vehicle.year).keyboardType(.numberPad)
                    TextField("Make", text: $vehicle.make)
                    TextField("Model", text: $vehicle.model)
                    TextField("Plate (optional)", text: $vehicle.plate)
                }
                Section {
                    ForEach($vehicle.years) { $year in
                        VStack(alignment: .leading) {
                            LabeledContent("Tax year") { TextField("Year", value: $year.year, format: .number.grouping(.never)).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                            LabeledContent("Start odometer") { TextField("Miles", value: $year.start, format: .number.grouping(.never)).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                            LabeledContent("End odometer") { TextField("Optional", value: $year.end, format: .number.grouping(.never)).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        }
                    }.onDelete { vehicle.years.remove(atOffsets: $0) }
                    Button("Add tax year") { let current = Calendar.current.component(.year, from: Date()); let year = vehicle.years.map(\.year).max().map { $0 + 1 } ?? current; vehicle.years.append(VehicleYear(year: year)) }
                } header: { Text("Yearly odometer readings") } footer: { Text("Business use = logged business miles ÷ (year-end − year-start odometer). Record the full year's driving, including personal use, in the odometer readings.") }
            }.navigationTitle("Vehicle").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.bold() }
            }.errorAlert($error).interactiveDismissDisabled()
        }
    }
    private func save() {
        do { try Validation.vehicle(vehicle); vehicle.updatedAt = Date(); var b = store.data; b.vehicles.removeAll { $0.id == vehicle.id }; b.vehicles.append(vehicle); try store.commit(b); dismiss() } catch { self.error = error.localizedDescription }
    }
}
#Preview("Vehicles") { NavigationStack { VehiclesView().environment(PreviewData.store()) } }
#Preview("Vehicle editor") { VehicleEditor(vehicle: Vehicle()).environment(PreviewData.store()) }
