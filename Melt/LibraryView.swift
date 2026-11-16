import SwiftUI

enum ShelfSection: String, CaseIterable { case designs = "Designs", orders = "Orders", sales = "Sales" }

struct LibraryView: View {
    enum Filter: String, CaseIterable { case all = "All", published = "Published", drafts = "Drafts" }
    @EnvironmentObject private var store: MeltStore
    @State private var filter = Filter.all
    @State private var showsProfile = false
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            StudioHeading(title: "My shelf")
                            Button { showsProfile = true } label: { Image(systemName: "person.crop.circle").font(.title2).frame(width: 44, height: 44) }
                                .buttonStyle(.plain).accessibilityLabel("Profile")
                        }
                        StudioSegments(values: ShelfSection.allCases, selection: $store.shelfSection) { $0.rawValue }
                        switch store.shelfSection {
                        case .designs:
                            HStack(spacing: 20) {
                                ForEach(Filter.allCases, id: \.self) { value in
                                    Button(value.rawValue) { filter = value }
                                        .font(.subheadline.weight(filter == value ? .bold : .regular))
                                        .foregroundStyle(filter == value ? Studio.ink : Studio.muted)
                                        .accessibilityAddTraits(filter == value ? .isSelected : [])
                                }
                            }
                            if visibleProducts.isEmpty {
                                StudioEmpty(title: "No designs", detail: "Saved and generated designs appear here.")
                                Button("Create") { store.selectedTab = .create }.buttonStyle(StudioButton())
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 26) {
                                    ForEach(visibleProducts) { product in
                                        NavigationLink { ProductDetailView(productId: product.id) } label: { ProductTile(product: product) }.buttonStyle(.plain)
                                    }
                                }
                            }
                        case .orders:
                            orderList(store.orders, role: .buyer)
                        case .sales:
                            if let profile = store.profile {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("EARNINGS").font(Studio.label).foregroundStyle(Studio.muted)
                                    Text(dollars(profile.earningsCents)).font(Studio.title(40))
                                }
                                StudioRule()
                            }
                            orderList(store.sales, role: .creator)
                        }
                    }.padding(24)
                }.studioScreen()
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsProfile) { ProfileView() }
        }
    }

    @ViewBuilder private func orderList(_ orders: [Order], role: OrderRow.Role) -> some View {
        if orders.isEmpty {
            StudioEmpty(title: role == .buyer ? "No orders" : "No sales", detail: role == .buyer ? "Your orders appear here." : "Orders for your published designs appear here.", symbol: "shippingbox")
        } else {
            ForEach(orders) { order in
                OrderRow(order: order, role: role)
                StudioRule()
            }
        }
    }
}

struct OrderRow: View {
    enum Role { case buyer, creator }
    let order: Order
    let role: Role
    @Environment(\.openURL) private var openURL

    private var status: String {
        if order.status == .failed { return "Payment failed" }
        if order.status == .pending { return "Awaiting payment" }
        return order.fulfillment == .queued ? "Order received" : order.fulfillment.label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(order.productName).font(.system(.headline, design: .rounded))
                Spacer()
                Text(dollars(order.amountCents)).font(.subheadline.weight(.semibold))
            }
            Text(role == .buyer ? "By \(order.creatorName)" : "For \(order.buyerName)").font(.subheadline).foregroundStyle(Studio.muted)
            HStack {
                Circle().fill(order.status == .failed ? Color.red : Studio.orange).frame(width: 7, height: 7)
                Text(status).font(Studio.label)
                Spacer()
                Text(order.filament.label).font(.caption).foregroundStyle(Studio.muted)
            }
            if order.status == .pending, let url = order.purchaseURL {
                Button("Continue checkout") { openURL(url) }.font(.subheadline.bold())
            }
        }.padding(.vertical, 8)
    }
}

struct ProfileView: View {
    @EnvironmentObject private var store: MeltStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var working = false
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    StudioHeading(title: "Profile")
                    Text("NAME").font(Studio.label)
                    TextField("Your name", text: $name).textContentType(.name).font(.title2)
                    StudioRule()
                    if let profile = store.profile {
                        HStack { Text("Challenge wins"); Spacer(); Text("\(profile.wins)").bold() }
                        HStack { Text("Credits"); Spacer(); Text(profile.credits.formatted()).bold() }
                    }
                    Button("Save") {
                        working = true
                        Task {
                            defer { working = false }
                            do { try await store.renameProfile(name); dismiss() }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }.buttonStyle(StudioButton()).disabled(working || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.profile == nil)
                }.padding(24)
            }.studioScreen().navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
                .task { name = store.profile?.displayName ?? "" }
                .errorAlert("Couldn't save", message: $errorMessage)
        }.tint(Studio.orange)
    }
}

struct ProductRow: View {
    let product: Product
    var showsCreator = false
    var body: some View {
        HStack(spacing: 16) {
            ProductArtwork(product: product).frame(width: 76, height: 86).background(Studio.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(product.name).font(.headline)
                Text(showsCreator ? product.creatorName : product.status.label).font(.caption).foregroundStyle(Studio.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption)
        }.foregroundStyle(Studio.ink)
    }
}
