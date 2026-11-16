import SwiftUI

struct ArenaView: View {
    @EnvironmentObject private var store: MeltStore
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            NavigationLink { NewDuelView() } label: {
                HStack { Text("Challenge a friend"); Spacer(); Image(systemName: "plus") }.padding(.horizontal, 18)
            }.buttonStyle(StudioButton())
            if store.liveDuels.isEmpty {
                StudioEmpty(title: "No active challenges", detail: "Choose two published designs to start a sales challenge.", symbol: "flag.checkered")
            }
            ForEach(store.liveDuels) { duel in
                NavigationLink { DuelDetailView(duelId: duel.id) } label: { DuelRow(duel: duel) }.buttonStyle(.plain)
                StudioRule()
            }
            if !store.settledDuels.isEmpty {
                Text("COMPLETED").font(Studio.label).foregroundStyle(Studio.muted)
                ForEach(store.settledDuels) { duel in
                    NavigationLink { DuelDetailView(duelId: duel.id) } label: { DuelRow(duel: duel) }.buttonStyle(.plain)
                    StudioRule()
                }
            }
        }
    }
}

struct NewDuelView: View {
    @EnvironmentObject private var store: MeltStore
    @Environment(\.dismiss) private var dismiss
    @State private var productId = ""
    @State private var opponentProductId = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var duelId: String?
    private var mine: [Product] { store.products.filter { $0.status == .published } }
    private var opponents: [Product] { store.friends.flatMap(\.products) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                StudioHeading(title: "New challenge", subtitle: "Most sales in 24 hours wins.")
                Text("YOUR DESIGN").font(Studio.label)
                if mine.isEmpty {
                    Text("Publish a design to enter a challenge.").foregroundStyle(Studio.muted)
                } else {
                    selection(products: mine, value: $productId)
                }
                StudioRule()
                Text("FRIEND'S DESIGN").font(Studio.label)
                if opponents.isEmpty {
                    Text("Connect with a creator from their product page to challenge them.").foregroundStyle(Studio.muted)
                } else {
                    selection(products: opponents, value: $opponentProductId)
                }
                Button("Start challenge") {
                    isWorking = true
                    Task {
                        defer { isWorking = false }
                        do { duelId = try await store.createDuel(productId: productId, opponentProductId: opponentProductId) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }.buttonStyle(StudioButton()).disabled(productId.isEmpty || opponentProductId.isEmpty || isWorking)
            }.padding(24)
        }.studioScreen().navigationTitle("Challenge").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .navigationDestination(item: $duelId) { DuelDetailView(duelId: $0) }
            .errorAlert("Couldn't start challenge", message: $errorMessage)
    }

    private func selection(products: [Product], value: Binding<String>) -> some View {
        VStack(spacing: 12) {
            ForEach(products) { product in
                Button { value.wrappedValue = product.id } label: {
                    HStack {
                        ProductRow(product: product, showsCreator: true)
                        Image(systemName: value.wrappedValue == product.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(value.wrappedValue == product.id ? Studio.orange : Studio.muted)
                    }.padding(10).background(Studio.ink.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).accessibilityAddTraits(value.wrappedValue == product.id ? .isSelected : [])
            }
        }
    }
}

struct DuelRow: View {
    let duel: Duel
    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                contender(duel.productA, sold: duel.salesA)
                Text("VS").font(Studio.label).foregroundStyle(Studio.muted).padding(.top, 66)
                contender(duel.productB, sold: duel.salesB)
            }
            SalesBar(duel: duel)
            HStack {
                if duel.isLive {
                    Text("24H CHALLENGE").font(Studio.label)
                    Spacer()
                    Text(duel.endsAt, style: .relative).font(Studio.label)
                } else {
                    Text(duel.winner.map { "\(duel.product($0).creatorName) won" } ?? "Tie").font(Studio.label)
                    Spacer()
                    Image(systemName: "flag.checkered")
                }
            }.foregroundStyle(Studio.muted)
        }.foregroundStyle(Studio.ink)
    }
    private func contender(_ product: Product, sold: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProductArtwork(product: product).frame(height: 138)
            Text(product.name).font(.system(.subheadline, design: .rounded).weight(.bold)).lineLimit(2)
            Text(product.creatorName).font(.caption).foregroundStyle(Studio.muted).lineLimit(1)
            Text("\(sold) sold").font(.title3.bold())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SalesBar: View {
    let duel: Duel
    var body: some View {
        let total = duel.salesA + duel.salesB
        let share = total == 0 ? 0.5 : Double(duel.salesA) / Double(total)
        GeometryReader { proxy in
            HStack(spacing: 3) {
                Capsule().fill(Studio.orange).frame(width: max(5, (proxy.size.width - 3) * share))
                Capsule().fill(Studio.ink)
            }
        }.frame(height: 6).accessibilityLabel("\(duel.salesA) sales to \(duel.salesB)")
    }
}

struct DuelDetailView: View {
    @EnvironmentObject private var store: MeltStore
    let duelId: String
    @State private var showsBacking = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let duel = store.duel(id: duelId) {
                    StudioHeading(title: "Sales challenge")
                    DuelRow(duel: duel)
                    StudioRule()
                    ForEach(Side.allCases, id: \.self) { side in
                        NavigationLink { ProductDetailView(productId: duel.product(side).id) } label: {
                            ProductRow(product: duel.product(side), showsCreator: true)
                        }.buttonStyle(.plain)
                    }
                    StudioRule()
                    if let stake = store.stake(for: duel.id) {
                        Text(stake.summary(in: duel)).font(.subheadline)
                    } else if duel.isLive {
                        Button("Back a design", systemImage: "flag") { showsBacking = true }
                            .buttonStyle(StudioButton(secondary: true))
                    }
                    HStack {
                        Text("CREDIT POOL").font(Studio.label)
                        Spacer()
                        Text((duel.poolA + duel.poolB).formatted()).font(.headline)
                    }.foregroundStyle(Studio.muted)
                } else {
                    StudioEmpty(title: "Challenge unavailable", detail: "This challenge couldn't be found.")
                }
            }.padding(24)
        }.studioScreen().navigationTitle("Challenge").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .sheet(isPresented: $showsBacking) { BackDesignView(duelId: duelId) }
    }
}

struct BackDesignView: View {
    @EnvironmentObject private var store: MeltStore
    @Environment(\.dismiss) private var dismiss
    let duelId: String
    @State private var side = Side.a
    @State private var amount = 100
    @State private var isWorking = false
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let duel = store.duel(id: duelId) {
                        StudioHeading(title: "Back a design", subtitle: "\(store.profile?.credits.formatted() ?? "0") credits available")
                        ForEach(Side.allCases, id: \.self) { option in
                            Button { side = option } label: {
                                HStack {
                                    ProductRow(product: duel.product(option), showsCreator: true)
                                    Image(systemName: side == option ? "checkmark.circle.fill" : "circle").foregroundStyle(Studio.orange)
                                }
                            }.buttonStyle(.plain).accessibilityAddTraits(side == option ? .isSelected : [])
                        }
                        StudioSegments(values: [50, 100, 250, 500], selection: $amount) { "\($0)" }
                        Button("Back with \(amount) credits") {
                            isWorking = true
                            Task {
                                defer { isWorking = false }
                                do { try await store.placeStake(amount, on: side, duelId: duelId); dismiss() }
                                catch { errorMessage = error.localizedDescription }
                            }
                        }.buttonStyle(StudioButton()).disabled(isWorking || amount > (store.profile?.credits ?? 0))
                    }
                }.padding(24)
            }.studioScreen().navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
                .errorAlert("Couldn't back this design", message: $errorMessage)
        }.tint(Studio.orange)
    }
}

extension Stake {
    func summary(in duel: Duel) -> String {
        let position = "You backed \(duel.product(side).name) with \(amount) credits"
        guard let payout else { return position }
        if payout == 0 { return "\(position) and lost them" }
        return side == duel.winner ? "\(position) and won \(payout)" : "\(position) and got them back"
    }
}
