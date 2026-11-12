import SwiftUI

struct RatesView: View {
    @Environment(LogStore.self) private var store
    @State private var editing: MileageRate?
    var body: some View {
        List {
            Section { Text("Rates apply by trip date and category. Saved trips retain their rate snapshots when this table changes. To recalculate a saved trip, open it and choose Refresh saved rates; changing its date or category also refreshes its rates. Verify rates against the official IRS source. Employer reimbursement rates are separate.").font(.footnote); Link("IRS standard mileage rates", destination: URL(string: "https://www.irs.gov/tax-professionals/standard-mileage-rates")!) }
            ForEach(store.data.rates.sorted { $0.startDay == $1.startDay ? $0.category.rawValue < $1.category.rawValue : $0.startDay > $1.startDay }) { rate in
                Button { editing = rate } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(rate.category.rawValue).bold(); Spacer(); Text("\(CSVExporter.decimal(rate.cents))¢/mi") }
                        Text("\(rate.startDay) – \(rate.endDay)").font(.caption).foregroundStyle(.secondary)
                        Text(rate.employer ? "Employer reimbursement" : "IRS estimate").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("Rates").toolbar { Button("Add rate", systemImage: "plus") { var r = MileageRate(); r.startDay = "\(r.taxYear)-01-01"; r.endDay = "\(r.taxYear)-12-31"; editing = r } }.sheet(item: $editing) { RateEditor(rate: $0) }
    }
}
struct RateEditor: View {
    @Environment(LogStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var rate: MileageRate
    @State private var error: String?
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tax year", value: $rate.taxYear, format: .number.grouping(.never)).keyboardType(.numberPad)
                    Picker("Category", selection: $rate.category) { ForEach(Category.allCases.filter { $0 != .personal }) { Text($0.rawValue).tag($0) } }
                    LabeledContent("Cents per mile") { TextField("Cents", value: $rate.cents, format: .number.grouping(.never)).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    DatePicker("First day", selection: Binding(get: { Day.date(rate.startDay) ?? Date() }, set: { rate.startDay = Day.string($0) }), displayedComponents: .date)
                    DatePicker("Last day (inclusive)", selection: Binding(get: { Day.date(rate.endDay) ?? Date() }, set: { rate.endDay = Day.string($0) }), displayedComponents: .date)
                    Toggle("Employer reimbursement rate", isOn: $rate.employer)
                    TextField("Source / verification note", text: $rate.source, axis: .vertical)
                } footer: { Text("Rates for the same category and type cannot overlap. Employer rates are independent of IRS estimate rates.") }
                if store.data.rates.contains(where: { $0.id == rate.id }) { Button("Delete rate", role: .destructive) { deleting = true } }
            }.navigationTitle("Mileage rate").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.bold() }
            }.errorAlert($error).interactiveDismissDisabled()
                .confirmationDialog("Delete this rate from the table? Existing trip snapshots are retained. New or explicitly refreshed trips may have no matching rate.", isPresented: $deleting, titleVisibility: .visible) { Button("Delete rate", role: .destructive) { do { try store.removeRecord(id: rate.id, kind: "rate"); dismiss() } catch { self.error = error.localizedDescription } } }
        }
    }
    private func save() {
        do { try Validation.rate(rate, others: store.data.rates); rate.updatedAt = Date(); var b = store.data; b.rates.removeAll { $0.id == rate.id }; b.rates.append(rate); try store.commit(b); dismiss() } catch { self.error = error.localizedDescription }
    }
}
#Preview("Rates") { NavigationStack { RatesView().environment(PreviewData.store()) } }
#Preview("Rate editor") { RateEditor(rate: MileageRate()).environment(PreviewData.store()) }
