import SwiftUI

struct LibraryView: View {
    enum Filter: String, CaseIterable {
        case all = "All"
        case published = "Published"
        case drafts = "Drafts"
    }

    @EnvironmentObject private var store: MeltStore
    @State private var filter = Filter.all

    private var visibleProducts: [Product] {
        switch filter {
        case .all: store.products
        case .published: store.products.filter { $0.status == .published }
        case .drafts: store.products.filter { $0.status != .published }
        }
    }

    var body: some View {
        NavigationStack {
            PhaseView {
                List {
                    if let profile = store.profile {
                        Section(profile.displayName) {
                            LabeledContent("Credits", value: profile.credits.formatted())
                            LabeledContent("Duel wins", value: "\(profile.wins)")
                            LabeledContent("Earnings", value: dollars(profile.earningsCents))
                        }
                    }
                    Section("My designs") {
                        Picker("Show", selection: $filter) {
                            ForEach(Filter.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        if visibleProducts.isEmpty {
                            ContentUnavailableView(
                                store.products.isEmpty ? "No designs yet" : "Nothing here",
                                systemImage: "cube.transparent",
                                description: Text(
                                    store.products.isEmpty
                                        ? "Describe a product in Create and it shows up here."
                                        : "None of your designs match this filter."
                                )
                            )
                        }
                        ForEach(visibleProducts) { product in
                            NavigationLink {
                                ProductDetailView(productId: product.id)
                            } label: {
                                ProductRow(product: product)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
        }
    }
}

struct ProductRow: View {
    let product: Product
    var showsCreator = false

    private var detail: String {
        if showsCreator { return "\(product.creatorName) · \(dollars(product.priceCents))" }
        switch product.status {
        case .generating: return "Generating the model"
        case .ready: return "Draft · \(dollars(product.priceCents))"
        case .published: return "\(dollars(product.priceCents)) · \(product.salesCount) sold"
        case .failed: return product.failureReason ?? "Generation failed"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(product.filament.color)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if product.status == .generating {
                Spacer()
                ProgressView()
            }
        }
    }
}
