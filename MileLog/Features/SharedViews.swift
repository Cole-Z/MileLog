import SwiftUI
import MapKit
import CoreLocation

extension Decimal {
    var money: String { NSDecimalNumber(decimal: self).doubleValue.formatted(.currency(code: "USD")) }
}
struct ErrorAlert: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert("MileLog", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK", role: .cancel) { message = nil } } message: { Text(message ?? "") }
    }
}
extension View { func errorAlert(_ text: Binding<String?>) -> some View { modifier(ErrorAlert(message: text)) } }
struct ShareFile: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onError: (String) -> Void = { _ in }
    func makeUIViewController(context: Context) -> UIActivityViewController {
        makeController()
    }
    func makeController() -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, error in
            // Cancellation is a normal completion. Keep the file available for retry.
            if let error { onError("Sharing could not finish. Try sharing again. \(error.localizedDescription)") }
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
struct PlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [MKMapItem] = []
    @State private var busy = false
    @State private var error: String?
    let select: (Place) -> Void
    init(initial: String, select: @escaping (Place) -> Void) { _query = State(initialValue: initial); self.select = select }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Address or place", text: $query).submitLabel(.search).onSubmit { search() }
                    Button("Search Apple Maps", action: search).disabled(busy || query.isEmpty)
                    if busy { ProgressView() }
                } footer: { Text("Address lookup sends your search to Apple Maps. You can also type a location directly without using lookup.") }
                ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                    Button { let c = item.placemark.coordinate; select(Place(text: item.placemark.title ?? item.name ?? query, latitude: c.latitude, longitude: c.longitude)); dismiss() } label: {
                        VStack(alignment: .leading) { Text(item.name ?? "Place"); Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }.navigationTitle("Find a place").toolbar { Button("Cancel") { dismiss() } }.errorAlert($error)
        }
    }
    private func search() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do { let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query; results = try await MKLocalSearch(request: request).start().mapItems; if results.isEmpty { error = "No places found. Try a fuller address, or enter it manually." } }
            catch { self.error = error.localizedDescription }
        }
    }
}
@MainActor enum PreviewData {
    static func store() -> LogStore {
        do { return try LogStore(inMemory: true) } catch { fatalError("Preview store: \(error)") }
    }
}
#Preview("Place search") { PlaceSearchView(initial: "Post office") { _ in } }

@MainActor final class EndpointGeocoder {
    private var cache: [String: String] = [:]
    private let geocoder = CLGeocoder()
    func label(for place: Place) async throws -> String {
        guard let latitude = place.latitude, let longitude = place.longitude else { throw LogError("No recorded coordinates.") }
        let key = "\(latitude),\(longitude)"
        if let cached = cache[key] { return cached }
        let results = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude))
        guard let result = results.first else { throw LogError("Address unavailable.") }
        let parts = [result.name, result.locality, result.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }
        var seen = Set<String>()
        let label = parts.filter { seen.insert($0).inserted }.joined(separator: ", ")
        guard !label.isEmpty else { throw LogError("Address unavailable.") }
        if cache.count >= 64 { cache.removeAll() }
        cache[key] = label
        return label
    }
}
