import SwiftUI

@main
struct MeltApp: App {
    @StateObject private var store = MeltStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
