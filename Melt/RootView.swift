import SwiftUI

enum MeltTab: Hashable { case create, explore, shelf }

struct RootView: View {
    @EnvironmentObject private var store: MeltStore

    var body: some View {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "MeltInspectModel") {
            ModelInspectionView()
        } else {
            appTabs
        }
        #else
        appTabs
        #endif
    }

    private var appTabs: some View {
        TabView(selection: $store.selectedTab) {
            Tab("Create", systemImage: "cube", value: MeltTab.create) { CreateView() }
            Tab("Explore", systemImage: "safari", value: MeltTab.explore) { ExploreView() }
            Tab("My shelf", systemImage: "square.stack.3d.up", value: MeltTab.shelf) { LibraryView() }
        }
        .tint(Studio.orange)
        .preferredColorScheme(.light)
        .task { await store.load() }
    }
}

struct PhaseView<Content: View>: View {
    @EnvironmentObject private var store: MeltStore
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch store.phase {
        case .loading:
            ProgressView("Loading").frame(maxWidth: .infinity, maxHeight: .infinity).studioScreen()
        case .failed(let message):
            VStack(spacing: 20) {
                StudioEmpty(title: "Couldn't connect", detail: message, symbol: "wifi.exclamationmark")
                Button("Try again") { Task { await store.load() } }.buttonStyle(StudioButton())
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).studioScreen()
        case .ready:
            content()
        }
    }
}

extension View {
    func errorAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message.wrappedValue ?? "") }
    }
}

#if DEBUG
// Read-only development viewer for actual saved USDZ results. No generation, checkout,
// fixture substitution or backend mutation; excluded from Release builds.
private struct ModelInspectionView: View {
    @State private var product: Product?
    @State private var message: String?
    @State private var reduced = UserDefaults.standard.bool(forKey: "MeltInspectReduceMotion")

    var body: some View {
        VStack(spacing: 20) {
            if let product {
                Text(product.name).font(.headline)
                ModelPreview(product: product).frame(height: 360)
                    .environment(\._accessibilityReduceMotion, reduced)
                FilamentPicker(selection: Binding(get: { product.filament }, set: { color in
                    self.product?.filament = color
                    self.product?.colorCustomized = true
                }), originalSelected: product.colorCustomized != true, reset: {
                    self.product?.colorCustomized = false
                })
                Toggle("Reduce Motion", isOn: $reduced)
                Text("Development model inspection").font(.caption).foregroundStyle(Studio.muted)
            } else {
                Text(message ?? "Loading model")
            }
        }.padding(24).studioScreen()
        .task {
            do {
                // Exercises the normal catalog renderer without a backend or fixture mode.
                if let key = UserDefaults.standard.string(forKey: "MeltInspectCatalog"),
                   let bundled = Fixtures.demo().storefront.first(where: { $0.catalogKey == key }) {
                    product = bundled
                    return
                }
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("preview-inspection.json")
                let record = try JSONDecoder().decode(ProductRecord.self, from: Data(contentsOf: url))
                product = record.product(creatorName: "Inspection")
            } catch { message = error.localizedDescription }
        }
    }
}
#endif
