import Foundation

@MainActor
final class MeltStore: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var phase = Phase.loading
    @Published private(set) var profile: Profile?
    @Published private(set) var products: [Product] = []
    @Published private(set) var liveDuels: [Duel] = []
    @Published private(set) var settledDuels: [Duel] = []
    @Published private(set) var stakes: [Stake] = []

    private let scenario =
        Fixtures.Scenario(rawValue: UserDefaults.standard.string(forKey: "MeltScenario") ?? "") ?? .demo

    func load() async {
        phase = .loading
        try? await Task.sleep(for: .milliseconds(600))
        if scenario == .error {
            phase = .failed("The Melt backend didn't answer. Check your connection and try again.")
            return
        }
        let world = scenario == .empty ? Fixtures.empty() : Fixtures.demo()
        profile = world.profile
        products = world.products
        liveDuels = world.liveDuels
        settledDuels = world.settledDuels
        stakes = world.stakes
        phase = .ready
    }

    func duel(id: String) -> Duel? {
        (liveDuels + settledDuels).first { $0.id == id }
    }

    func product(id: String) -> Product? {
        let inDuels = (liveDuels + settledDuels).flatMap { [$0.productA, $0.productB] }
        return (products + inDuels).first { $0.id == id }
    }

    func stake(for duelId: String) -> Stake? {
        stakes.first { $0.duelId == duelId }
    }

    func placeStake(_ amount: Int, on side: Side, duelId: String) async throws {
        guard var profile, let index = liveDuels.firstIndex(where: { $0.id == duelId }) else {
            throw MeltError("This duel is no longer open")
        }
        guard stake(for: duelId) == nil else {
            throw MeltError("You already backed a side in this duel")
        }
        guard profile.credits >= amount else {
            throw MeltError("Not enough credits")
        }
        profile.credits -= amount
        self.profile = profile
        if side == .a {
            liveDuels[index].poolA += amount
        } else {
            liveDuels[index].poolB += amount
        }
        stakes.append(Stake(duelId: duelId, side: side, amount: amount))
    }

    func generate(prompt: String, filament: Filament) async throws -> String {
        let id = "local-\(UUID().uuidString)"
        products.insert(
            Product(
                id: id, name: String(prompt.prefix(40)), prompt: prompt,
                creatorName: profile?.displayName ?? "You", isMine: true,
                status: .generating, filament: filament, priceCents: 1500, salesCount: 0
            ),
            at: 0
        )
        Task {
            try? await Task.sleep(for: .seconds(3))
            if let index = products.firstIndex(where: { $0.id == id }) {
                products[index].status = .ready
            }
        }
        return id
    }
}
