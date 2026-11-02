import SwiftUI
import SwiftData

@main
struct SteadyStrengthApp: App {
    let container = Persistence.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
