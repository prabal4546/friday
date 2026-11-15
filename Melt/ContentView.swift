import SwiftUI

struct ContentView: View {
    @StateObject private var store = MeltStore()
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    Text(store.status)
                }
                Section("Profile") {
                    if let profile = store.profile {
                        Text(profile.displayName)
                        Text("\(Int(profile.credits)) credits")
                        Text("\(Int(profile.wins)) duel wins")
                    }
                }
                Section("Live duels") {
                    ForEach(store.liveDuels) { duel in
                        VStack(alignment: .leading) {
                            Text("\(duel.productA.name) vs \(duel.productB.name)")
                            Text("Sales \(Int(duel.salesA)) to \(Int(duel.salesB))")
                            Text("Pools \(Int(duel.poolA)) to \(Int(duel.poolB)) credits")
                            HStack {
                                Button("Stake 50 on A") { Task { await store.stake(on: "a", in: duel) } }
                                Button("Stake 50 on B") { Task { await store.stake(on: "b", in: duel) } }
                            }
                            HStack {
                                Button("Buy A") { buy(duel.productA) }
                                Button("Buy B") { buy(duel.productB) }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section("My products") {
                    ForEach(store.products) { product in
                        Text("\(product.name), \(product.status), \(Int(product.salesCount)) sold")
                    }
                }
            }
            .navigationTitle("Melt")
        }
        .task { await store.start() }
    }

    private func buy(_ product: ProductSummary) {
        Task {
            if let url = await store.checkout(product) {
                openURL(url)
            }
        }
    }
}
