import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: MeltStore

    var body: some View {
        TabView {
            Tab("Arena", systemImage: "flame") { ArenaView() }
            Tab("Shop", systemImage: "bag") { StorefrontView() }
            Tab("Create", systemImage: "wand.and.stars") { CreateView() }
            Tab("Library", systemImage: "square.grid.2x2") { LibraryView() }
        }
        .task { await store.load() }
    }
}

struct PhaseView<Content: View>: View {
    @EnvironmentObject private var store: MeltStore
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch store.phase {
        case .loading:
            ProgressView("Loading Melt")
        case .failed(let message):
            ContentUnavailableView {
                Label("Can't load Melt", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await store.load() } }
            }
        case .ready:
            content()
        }
    }
}

extension View {
    func errorAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
