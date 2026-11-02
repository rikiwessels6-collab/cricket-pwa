import Foundation
import Observation
import SteadyCore

/// The bundled programs, exercise library, equipment profiles and check-in
/// defaults (Resources/Generated, built by tools/importer). Loaded once, off
/// the main thread.
@Observable
@MainActor
final class ContentStore {
    enum State { case loading, ready(BundledContent), failed(String) }
    private(set) var state: State = .loading

    var content: BundledContent? {
        if case .ready(let c) = state { return c }
        return nil
    }

    func load() async {
        guard case .loading = state else { return }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { () throws -> BundledContent in
                func data(_ name: String) throws -> Data {
                    guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
                    }
                    return try Data(contentsOf: url)
                }
                return try BundledContent(programs: data("programs"), library: data("exercise_library"),
                                          equipment: data("equipment"), checkIn: data("checkin_defaults"))
            }.value
            state = .ready(loaded)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
