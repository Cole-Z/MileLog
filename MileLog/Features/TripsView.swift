import SwiftUI

struct TripPresentation: Identifiable { let id = UUID(); var original: Trip?; var details = TripDetails(); var draftID: UUID? }
struct TripsView: View {
    @Environment(LogStore.self) private var store
    @Environment(LocationRecorder.self) private var recorder
    @State private var editor: TripPresentation?
    @State private var deleting: Trip?
    @State private var discard = false
    var body: some View {
        @Bindable var recorder = recorder
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("YOUR MILEAGE, RECORDED", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.caption.weight(.semibold)).foregroundStyle(.teal)
                        if let draft = recorder.draft {
                            Text("\((draft.meters / DistanceCalculator.metersPerMile).formatted(.number.precision(.fractionLength(2)))) mi").font(.largeTitle.bold()).monospacedDigit()
                            Text(recorder.status).font(.subheadline)
                            if draft.interrupted { Label("Review for missing miles before saving", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                            HStack {
                                if recorder.recording {
                                    Button("End trip", systemImage: "stop.circle.fill") { recorder.end(); review() }.buttonStyle(.borderedProminent)
                                } else {
                                    if !draft.ended { Button("Resume", systemImage: "play.fill") { recorder.start() }.buttonStyle(.borderedProminent) }
                                    Button("Review & save") { recorder.end(); review() }.buttonStyle(.bordered)
                                    Button(role: .destructive) { discard = true } label: { Image(systemName: "trash") }.accessibilityLabel("Discard recording")
                                }
                            }
                        } else {
                            Text("Every drive counts.").font(.title2.bold())
                            Text("Keep a clear record, one trip at a time.").foregroundStyle(.secondary)
                            Button("Start GPS trip", systemImage: "location.fill") { recorder.start() }.buttonStyle(.borderedProminent)
                        }
                        Text("GPS records while MileLog is open. The screen stays awake during recording. Use only when safely parked.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                if !store.data.frequentTrips.isEmpty && recorder.draft == nil {
                    Section("Frequent trips") {
                        ForEach(store.data.frequentTrips) { frequent in
                            Button { var d = frequent.details; d.day = Day.string(Date()); d.method = .manual; d.odometerStart = nil; d.odometerEnd = nil; d.parking = 0; d.tolls = 0; d.notes = ""; editor = TripPresentation(details: d) } label: { Label(frequent.name, systemImage: "arrow.turn.down.right") }
                        }
                    }
                }
                Section("Trip log") {
                    if store.trips.isEmpty { ContentUnavailableView("Your first mile starts here", systemImage: "car.side", description: Text("Tap + to log a drive manually, or start a GPS trip.")) }
                    ForEach(store.trips) { trip in
                        Button { editor = TripPresentation(original: trip) } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(trip.details.end.text).font(.headline).foregroundStyle(.primary)
                                    Text(trip.details.purpose.isEmpty ? trip.details.category.rawValue : trip.details.purpose).font(.subheadline).foregroundStyle(.secondary)
                                    Text("\(trip.details.day) · \(trip.details.category.rawValue)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("\(trip.details.totalMiles.formatted(.number.precision(.fractionLength(1)))) mi").font(.headline).foregroundStyle(.primary)
                                    Text(trip.details.method.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 3)
                        }.swipeActions { Button("Delete", role: .destructive) { deleting = trip } }
                    }
                }
            }.navigationTitle("MileLog").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add trip", systemImage: "plus") { var d = TripDetails(); d.vehicleID = store.trips.first?.details.vehicleID ?? store.data.vehicles.first?.id; editor = TripPresentation(details: d) } } }
                .sheet(item: $editor) { p in TripEditor(original: p.original, initial: p.details, draftID: p.draftID) { if p.draftID != nil { recorder.refresh() } } }
                .confirmationDialog("Delete this trip from your log? Its history stays in backups.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { Button("Delete trip", role: .destructive) { if let deleting { store.perform { try store.delete(deleting) } }; deleting = nil } }
                .confirmationDialog("Discard the saved GPS draft?", isPresented: $discard, titleVisibility: .visible) { Button("Discard recording", role: .destructive) { recorder.discard() } }
                .errorAlert($recorder.error)
        }
    }
    private func review() { editor = TripPresentation(details: recorder.details(), draftID: recorder.draft?.id) }
}
struct TotalsView: View {
    @Environment(LogStore.self) private var store
    @State private var employer = false
    var body: some View {
        NavigationStack {
            List {
                Section { Toggle("Use employer rates", isOn: $employer) }
                summary("This month", prefix: String(Day.string(Date()).prefix(7)))
                summary("This tax year", prefix: String(Day.string(Date()).prefix(4)))
                Section { Text("Estimates use the current rate table and exclude Personal trips. Parking and tolls are shown separately. A category alone does not establish eligibility for a deduction or reimbursement.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Totals")
        }
    }
    @ViewBuilder private func summary(_ title: String, prefix: String) -> some View {
        let totals = Totals(trips: store.trips, rates: store.data.rates, prefix: prefix, employer: employer)
        Section(title) {
            LabeledContent("Nonpersonal miles", value: totals.miles.formatted(.number.precision(.fractionLength(1))))
            LabeledContent("Business miles", value: totals.businessMiles.formatted(.number.precision(.fractionLength(1))))
            LabeledContent("Mileage estimate", value: totals.mileageAmount.money)
            LabeledContent("Parking", value: totals.parking.money)
            LabeledContent("Tolls", value: totals.tolls.money)
            if totals.missingRates > 0 { Label("\(totals.missingRates) trip(s) have no matching rate. The mileage estimate is incomplete.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
        }
    }
}
#Preview("Trips") { let s = PreviewData.store(); TripsView().environment(s).environment(LocationRecorder(store: s)) }
#Preview("Totals") { TotalsView().environment(PreviewData.store()) }
