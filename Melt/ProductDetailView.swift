import SwiftUI

struct ProductDetailView: View {
    @EnvironmentObject private var store: MeltStore
    @Environment(\.dismiss) private var dismiss
    let productId: String
    var initialAction = ProductDestination.Action.view
    @State private var errorMessage: String?
    @State private var showsOrder = false
    @State private var showsPublish = false
    @State private var handledInitialAction = false
    @State private var isWorking = false

    var body: some View {
        Group {
            if let product = store.product(id: productId) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        StudioHeading(title: product.name)
                        ModelPreview(product: product).frame(height: 330)
                        if product.creatorId == store.profile?.id && product.status == .ready {
                            FilamentPicker(selection: Binding(get: { product.filament }, set: { color in
                                run { try await store.setFilament(color, productId: product.id) }
                            }), originalSelected: product.hasOriginalAppearance && product.colorCustomized != true,
                            reset: !product.hasOriginalAppearance ? nil : { run { try await store.resetAppearance(productId: product.id) } })
                            .disabled(isWorking)
                        } else {
                            HStack { Text("COLOR"); Spacer(); Text(product.filament.label) }.font(Studio.label)
                        }
                        if product.status == .ready && product.creatorId == store.profile?.id || product.status == .published {
                            Button { showsOrder = true } label: {
                                HStack { Text("Order"); Spacer(); Text(dollars(product.priceCents)); Image(systemName: "arrow.up.right") }.padding(.horizontal, 18)
                            }.buttonStyle(StudioButton()).disabled(isWorking)
                        }
                        if product.creatorId == store.profile?.id {
                            HStack {
                                if product.status == .ready || product.status == .published {
                                    Button(product.whopListingURL == nil ? "Publish to Whop" : "View listing", systemImage: "square.and.arrow.up") { showsPublish = true }
                                    Spacer()
                                }
                                if product.status != .published {
                                    Button(product.status == .failed ? "Retry" : "Edit", systemImage: "slider.horizontal.3") {
                                        store.edit(product)
                                        dismiss()
                                    }
                                }
                            }.font(.headline).buttonStyle(.plain)
                        } else {
                            HStack {
                                Text(product.creatorName).font(.subheadline.bold())
                                Spacer()
                                if store.isFriend(profileId: product.creatorId) {
                                    Label("Connected", systemImage: "checkmark").font(.caption)
                                } else {
                                    Button("Connect") { run { try await store.connect(profileId: product.creatorId) } }
                                        .font(.subheadline.bold()).disabled(isWorking)
                                }
                            }
                        }
                        StudioRule()
                        HStack {
                            Text(product.status.label.uppercased()).font(Studio.label)
                            Spacer()
                            if product.status == .published { Text("\(product.salesCount) sold").font(Studio.label) }
                        }
                        if let note = product.printNote {
                            Label(note, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Studio.muted)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PROMPT").font(Studio.label).foregroundStyle(Studio.muted)
                            Text(product.prompt).font(.system(.body, design: .monospaced))
                        }
                    }.padding(24)
                }
                .sheet(isPresented: $showsOrder) { OrderReviewView(productId: productId) }
                .sheet(isPresented: $showsPublish) { PublishView(productId: productId) }
            } else {
                if store.phase == .ready {
                    StudioEmpty(title: "Loading design", detail: "Your design will appear here shortly.")
                } else { ProgressView() }
            }
        }
        .studioScreen()
        .navigationTitle("Design").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: store.product(id: productId)?.id) {
            guard store.product(id: productId) != nil, !handledInitialAction else { return }
            handledInitialAction = true
            showsOrder = initialAction == .order
            showsPublish = initialAction == .publish
        }
        .errorAlert("Couldn't complete that action", message: $errorMessage)
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do { try await action() } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct OrderReviewView: View {
    @EnvironmentObject private var store: MeltStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let productId: String
    @State private var result: CheckoutResult?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var order: Order? { store.orders.first { $0.id == result?.orderId } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let product = store.product(id: productId) {
                        ProductArtwork(product: product).frame(height: 240)
                        StudioHeading(title: product.name, subtitle: product.filament.label)
                        StudioRule()
                        HStack { Text("Price"); Spacer(); Text(dollars(product.priceCents)).bold() }
                        if let result {
                            if let order {
                                OrderRow(order: order, role: .buyer)
                            } else { ProgressView("Waiting for payment") }
                            if order?.status != .paid, let url = result.purchaseURL {
                                Button("Continue checkout") { openURL(url) }.buttonStyle(StudioButton())
                            }
                            Button("View orders") {
                                store.shelfSection = .orders
                                store.selectedTab = .shelf
                                dismiss()
                            }.buttonStyle(StudioButton(secondary: true))
                        } else {
                            Button {
                                isWorking = true
                                Task {
                                    defer { isWorking = false }
                                    do {
                                        result = try await store.checkout(productId: productId)
                                        if let url = result?.purchaseURL { openURL(url) }
                                    } catch { errorMessage = error.localizedDescription }
                                }
                            } label: {
                                HStack { Text(isWorking ? "Preparing checkout" : "Continue to checkout"); Image(systemName: "arrow.up.right") }
                            }.buttonStyle(StudioButton()).disabled(isWorking)
                        }
                    }
                }.padding(24)
            }.studioScreen().navigationTitle("Order").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
                .errorAlert("Couldn't open checkout", message: $errorMessage)
        }.tint(Studio.orange)
    }
}

struct PublishView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: MeltStore
    @Environment(\.dismiss) private var dismiss
    let productId: String
    @State private var price = ""
    @State private var isWorking = false
    @State private var published = false
    @State private var listingURL: URL?
    @State private var errorMessage: String?

    private var cents: Int? {
        guard price.range(of: "^[0-9]+([.,][0-9]{0,2})?$", options: .regularExpression) != nil,
              let value = Decimal(string: price.replacingOccurrences(of: ",", with: ".")), value >= 5, value <= 500 else { return nil }
        let scaled = value * 100
        let number = NSDecimalNumber(decimal: scaled)
        guard number.decimalValue == Decimal(number.intValue) else { return nil }
        return number.intValue
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let product = store.product(id: productId) {
                        ProductArtwork(product: product).frame(height: 260)
                        StudioHeading(title: product.name)
                        if published || product.whopListingURL != nil {
                            Label("Published", systemImage: "checkmark.circle.fill").font(.title2.bold())
                            Text("Your design is listed in \(store.whopStore?.name ?? "your Whop store").").foregroundStyle(Studio.muted)
                            if let url = listingURL ?? product.whopListingURL {
                                Button("View on Whop") { openURL(url) }.buttonStyle(StudioButton())
                            }
                            Button("Done") { dismiss() }.buttonStyle(StudioButton())
                        } else {
                            StudioRule()
                            if let whopStore = store.whopStore {
                                Label(whopStore.name, systemImage: "storefront").font(.headline)
                            } else if store.whopStoreLoaded {
                                Text("Your demo Whop store has not been assigned yet. Ask the demo organizer to set it up.").foregroundStyle(Studio.muted)
                                Text("Profile: \(store.profile?.id ?? "")").font(.caption).textSelection(.enabled)
                            } else {
                                ProgressView("Loading your store")
                            }
                            Text("PRICE / USD").font(Studio.label)
                            HStack {
                                Text("$")
                                TextField("15.00", text: $price).keyboardType(.decimalPad).accessibilityIdentifier("listing-price").disabled(isWorking || product.whopPublishPriceCents != nil)
                            }.font(Studio.title(32))
                            Text("$5–$500").font(.caption).foregroundStyle(Studio.muted)
                            Button(isWorking ? "Publishing to Whop…" : "Publish") {
                                guard let cents else { return }
                                isWorking = true
                                Task {
                                    defer { isWorking = false }
                                    do { listingURL = try await store.publish(productId: productId, priceCents: cents); published = true }
                                    catch { errorMessage = error.localizedDescription }
                                }
                            }.buttonStyle(StudioButton()).disabled(cents == nil || isWorking || store.whopStore == nil)
                        }
                    }
                }.padding(24)
            }.studioScreen().navigationTitle("Publish").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
                .task { if let product = store.product(id: productId) { price = String(format: "%.2f", Double(product.whopPublishPriceCents ?? product.priceCents) / 100) } }
                .errorAlert("Couldn't publish", message: $errorMessage)
        }.tint(Studio.orange)
    }
}
