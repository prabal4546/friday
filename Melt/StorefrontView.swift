import SwiftUI

struct ExploreView: View {
    enum Section: String, CaseIterable { case shop = "Shop", challenges = "Challenges" }
    @State private var section = Section.shop
    var body: some View {
        NavigationStack {
            PhaseView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        StudioHeading(title: "Explore")
                        StudioSegments(values: Section.allCases, selection: $section) { $0.rawValue }
                        switch section {
                        case .shop: StorefrontView()
                        case .challenges: ArenaView()
                        }
                    }.padding(24)
                }.studioScreen()
            }.toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct StorefrontView: View {
    @EnvironmentObject private var store: MeltStore
    var body: some View {
        if store.storefront.isEmpty {
            StudioEmpty(title: "No listings", detail: "Published designs appear here.", symbol: "bag")
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 28) {
                ForEach(store.storefront) { product in
                    NavigationLink { ProductDetailView(productId: product.id) } label: {
                        ProductTile(product: product, showsCreator: true)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
