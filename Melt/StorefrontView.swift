import SwiftUI

struct StorefrontView: View {
    @EnvironmentObject private var store: MeltStore

    var body: some View {
        NavigationStack {
            PhaseView {
                List {
                    Section {
                        Text("Buy a creator's design through Whop. Every order stays in demo fulfillment until you explicitly advance it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Section("Creator storefront") {
                        if store.storefront.isEmpty {
                            ContentUnavailableView(
                                "Nothing for sale yet", systemImage: "bag",
                                description: Text("Publish a ready design and it appears here for every device.")
                            )
                        }
                        ForEach(store.storefront) { product in
                            NavigationLink {
                                ProductDetailView(productId: product.id)
                            } label: {
                                ProductRow(product: product, showsCreator: true)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shop")
        }
    }
}
