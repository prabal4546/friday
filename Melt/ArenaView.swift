import SwiftUI

struct ArenaView: View {
    @EnvironmentObject private var store: MeltStore

    var body: some View {
        NavigationStack {
            PhaseView {
                List {
                    if let profile = store.profile {
                        Section {
                            LabeledContent("Your credits", value: profile.credits.formatted())
                        }
                    }
                    Section("Create together") {
                        NavigationLink {
                            StorefrontView()
                        } label: {
                            Label("Browse creator storefront", systemImage: "bag")
                        }
                        NavigationLink {
                            NewDuelView()
                        } label: {
                            Label("Start a duel with a friend", systemImage: "plus.circle")
                        }
                    }
                    Section("Live duels") {
                        if store.liveDuels.isEmpty {
                            ContentUnavailableView(
                                "No live duels",
                                systemImage: "flame",
                                description: Text("A duel starts when a creator challenges another product.")
                            )
                        }
                        ForEach(store.liveDuels) { duel in
                            NavigationLink {
                                DuelDetailView(duelId: duel.id)
                            } label: {
                                DuelRow(duel: duel)
                            }
                        }
                    }
                    if !store.settledDuels.isEmpty {
                        Section("Settled") {
                            ForEach(store.settledDuels) { duel in
                                NavigationLink {
                                    DuelDetailView(duelId: duel.id)
                                } label: {
                                    DuelRow(duel: duel)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Arena")
        }
    }
}

struct NewDuelView: View {
    @EnvironmentObject private var store: MeltStore
    @Environment(\.dismiss) private var dismiss
    @State private var productId = ""
    @State private var opponentProductId = ""
    @State private var errorMessage: String?
    @State private var isCreating = false

    private var mine: [Product] { store.products.filter { $0.status == .published } }
    private var opponents: [Product] { store.friends.flatMap(\.products) }

    var body: some View {
        Form {
            Section("Your product") {
                if mine.isEmpty {
                    Text("Publish a ready design from Library first.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Product", selection: $productId) {
                        Text("Choose").tag("")
                        ForEach(mine) { Text($0.name).tag($0.id) }
                    }
                }
            }
            Section("Friend's product") {
                if opponents.isEmpty {
                    Text("Open another creator's product in the storefront and connect first.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Opponent", selection: $opponentProductId) {
                        Text("Choose").tag("")
                        ForEach(opponents) { Text("\($0.name) · \($0.creatorName)").tag($0.id) }
                    }
                }
            }
            Section {
                Button("Create 24-hour duel") {
                    isCreating = true
                    Task {
                        do {
                            _ = try await store.createDuel(productId: productId, opponentProductId: opponentProductId)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        isCreating = false
                    }
                }
                .disabled(productId.isEmpty || opponentProductId.isEmpty || isCreating)
            } footer: {
                Text("Sales decide the winner. Friends can back either side with demo credits.")
            }
        }
        .navigationTitle("New duel")
        .errorAlert("Couldn't create the duel", message: $errorMessage)
    }
}

struct DuelRow: View {
    @EnvironmentObject private var store: MeltStore
    let duel: Duel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(duel.productA.name)
                Spacer(minLength: 12)
                Text(duel.productB.name)
                    .multilineTextAlignment(.trailing)
            }
            .font(.headline)
            SalesBar(duel: duel)
            HStack {
                Text("\(duel.salesA) sold")
                Spacer()
                Text("\(duel.salesB) sold")
            }
            .font(.subheadline)
            HStack {
                Text("\((duel.poolA + duel.poolB).formatted()) credits staked")
                Spacer()
                if duel.isLive {
                    Text("\(duel.endsAt, style: .relative) left")
                } else {
                    Text(duel.winner.map { "\(duel.product($0).name) won" } ?? "Tied")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let stake = store.stake(for: duel.id) {
                Text(stake.summary(in: duel))
                    .font(.footnote)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SalesBar: View {
    let duel: Duel

    var body: some View {
        let total = duel.salesA + duel.salesB
        let share = total == 0 ? 0.5 : Double(duel.salesA) / Double(total)
        GeometryReader { proxy in
            HStack(spacing: 2) {
                Capsule()
                    .fill(duel.productA.filament.color)
                    .frame(width: max(8, proxy.size.width * share - 1))
                Capsule()
                    .fill(duel.productB.filament.color)
            }
        }
        .frame(height: 8)
    }
}

struct DuelDetailView: View {
    @EnvironmentObject private var store: MeltStore
    let duelId: String
    @State private var side = Side.a
    @State private var amount = 100
    @State private var errorMessage: String?

    var body: some View {
        if let duel = store.duel(id: duelId) {
            List {
                Section("Contenders") {
                    ForEach(Side.allCases, id: \.self) { side in
                        NavigationLink {
                            ProductDetailView(productId: duel.product(side).id)
                        } label: {
                            ProductRow(product: duel.product(side), showsCreator: true)
                        }
                    }
                }
                Section("Your position") {
                    if let stake = store.stake(for: duel.id) {
                        Text(stake.summary(in: duel))
                    } else if duel.isLive {
                        Picker("Back", selection: $side) {
                            Text(duel.productA.name).tag(Side.a)
                            Text(duel.productB.name).tag(Side.b)
                        }
                        Picker("Amount", selection: $amount) {
                            ForEach([50, 100, 250, 500], id: \.self) { credits in
                                Text("\(credits) credits").tag(credits)
                            }
                        }
                        Button("Stake \(amount) credits") {
                            Task {
                                do {
                                    try await store.placeStake(amount, on: side, duelId: duel.id)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                    } else {
                        Text("You didn't back a side in this duel")
                    }
                }
                Section("Sales in this duel") {
                    SalesBar(duel: duel)
                    LabeledContent(duel.productA.name, value: "\(duel.salesA) sold")
                    LabeledContent(duel.productB.name, value: "\(duel.salesB) sold")
                    if duel.isLive {
                        LabeledContent("Ends in") {
                            Text(duel.endsAt, style: .relative)
                        }
                    } else {
                        LabeledContent("Winner", value: duel.winner.map { duel.product($0).name } ?? "Tied")
                    }
                }
                Section("Prediction pool") {
                    LabeledContent(duel.productA.name, value: "\(duel.poolA.formatted()) credits")
                    LabeledContent(duel.productB.name, value: "\(duel.poolB.formatted()) credits")
                }
            }
            .navigationTitle(duel.theme ?? "Duel")
            .navigationBarTitleDisplayMode(.inline)
            .errorAlert("Couldn't place your stake", message: $errorMessage)
        } else {
            ContentUnavailableView("This duel is gone", systemImage: "questionmark.circle")
        }
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
