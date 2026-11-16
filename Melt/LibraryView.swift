import SwiftUI

struct LibraryView: View {
    enum Filter: String, CaseIterable {
        case all = "All"
        case published = "Published"
        case drafts = "Drafts"
    }

    @EnvironmentObject private var store: MeltStore
    @State private var filter = Filter.all
    @State private var displayName = ""
    @State private var profileError: String?

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
                            TextField("Creator name", text: $displayName)
                            Button("Save creator name") {
                                Task {
                                    do {
                                        try await store.renameProfile(displayName)
                                    } catch {
                                        profileError = error.localizedDescription
                                    }
                                }
                            }
                            .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || displayName == profile.displayName)
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
                    if !store.orders.isEmpty {
                        Section("My orders") {
                            ForEach(store.orders) { order in
                                OrderRow(order: order, role: .buyer)
                            }
                        }
                    }
                    if !store.sales.isEmpty {
                        Section("Sales to fulfill") {
                            ForEach(store.sales) { order in
                                OrderRow(order: order, role: .creator)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .task(id: store.profile?.displayName) {
                displayName = store.profile?.displayName ?? ""
            }
            .errorAlert("Couldn't change your name", message: $profileError)
        }
    }
}

struct OrderRow: View {
    enum Role { case buyer, creator }

    @EnvironmentObject private var store: MeltStore
    let order: Order
    let role: Role
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(order.productName).font(.headline)
                Spacer()
                Text(dollars(order.amountCents)).foregroundStyle(.secondary)
            }
            Text(role == .buyer ? "By \(order.creatorName)" : "For \(order.buyerName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach([Order.Fulfillment.queued, .submitted, .printing], id: \.rawValue) { step in
                    Label(step.label, systemImage: reached(step) ? "checkmark.circle.fill" : "circle")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(reached(step) ? Color.green : Color.gray.opacity(0.4))
                    if step != .printing { Rectangle().frame(height: 1).foregroundStyle(.tertiary) }
                }
                Text(order.fulfillment.label).font(.caption.bold())
            }
            if let quote = order.slantQuoteCents {
                Text("Slant draft quote \(dollars(quote)) · production disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if role == .creator, order.fulfillment == .queued || order.fulfillment == .submitted {
                Button(order.fulfillment == .queued ? "Submit print draft" : "Start demo printing") {
                    isWorking = true
                    Task {
                        do {
                            try await store.advanceFulfillment(orderId: order.id)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        isWorking = false
                    }
                }
                .disabled(isWorking)
            }
        }
        .padding(.vertical, 4)
        .errorAlert("Couldn't advance fulfillment", message: $errorMessage)
    }

    private func reached(_ step: Order.Fulfillment) -> Bool {
        let rank: [Order.Fulfillment: Int] = [.none: 0, .queued: 1, .submitted: 2, .printing: 3]
        return rank[order.fulfillment, default: 0] >= rank[step, default: 0]
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
