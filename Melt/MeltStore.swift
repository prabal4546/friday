import Combine
import ConvexMobile
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

    private let scenario = Fixtures.Scenario(rawValue: UserDefaults.standard.string(forKey: "MeltScenario") ?? "")
    private let deviceId = DeviceIdentity.current()
    private lazy var client = ConvexClient(
        deploymentUrl: UserDefaults.standard.string(forKey: "ConvexDeploymentURL")
            ?? Bundle.main.object(forInfoDictionaryKey: "ConvexDeploymentURL") as? String ?? ""
    )
    private var subscriptions = Set<AnyCancellable>()
    private var awaited = Set<String>()

    func load() async {
        phase = .loading
        if let scenario {
            await loadFixtures(scenario)
            return
        }
        subscriptions.removeAll()
        do {
            try await ensureProfile()
        } catch {
            phase = .failed(Self.message(for: error))
            return
        }
        awaited = ["profiles:me", "duels:live", "products:mine"]
        let mine: [String: ConvexEncodable?] = ["deviceId": deviceId]
        watch("profiles:me", with: mine) { [weak self] (record: ProfileRecord?) in
            self?.profile = record?.profile
        }
        watch("duels:live") { [weak self] (records: [DuelRecord]) in
            self?.liveDuels = records.map(\.duel)
        }
        watch("duels:settled") { [weak self] (records: [DuelRecord]) in
            self?.settledDuels = records.map(\.duel)
        }
        watch("products:mine", with: mine) { [weak self] (records: [ProductRecord]) in
            self?.products = records.map { $0.product(creatorName: "You") }
        }
        watch("stakes:mine", with: mine) { [weak self] (records: [StakeRecord]) in
            self?.stakes = records.compactMap(\.stake)
        }
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
        if scenario != nil {
            try placeFixtureStake(amount, on: side, duelId: duelId)
            return
        }
        do {
            let _: String = try await client.mutation(
                "stakes:place",
                with: ["deviceId": deviceId, "duelId": duelId, "side": side.rawValue, "amount": Double(amount)]
            )
        } catch {
            throw MeltError(Self.message(for: error))
        }
    }

    func generate(prompt: String, filament: Filament) async throws -> String {
        if scenario != nil {
            return generateFixture(prompt: prompt, filament: filament)
        }
        do {
            return try await client.mutation(
                "products:create",
                with: ["deviceId": deviceId, "prompt": prompt, "filament": filament.rawValue]
            )
        } catch {
            throw MeltError(Self.message(for: error))
        }
    }

    private func ensureProfile() async throws {
        let client = client
        let deviceId = deviceId
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once(continuation)
            Task { @MainActor in
                do {
                    let _: String = try await client.mutation(
                        "profiles:ensure",
                        with: ["deviceId": deviceId, "claimSeed": true]
                    )
                    once.resume(with: .success(()))
                } catch {
                    once.resume(with: .failure(error))
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                once.resume(with: .failure(MeltError("Melt couldn't reach its backend. Check your connection and try again.")))
            }
        }
    }

    private func watch<Value: Decodable>(
        _ name: String,
        with args: [String: ConvexEncodable?]? = nil,
        receive: @escaping (Value) -> Void
    ) {
        client.subscribe(to: name, with: args, yielding: Value.self)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.phase = .failed(Self.message(for: error))
                    }
                },
                receiveValue: { [weak self] value in
                    receive(value)
                    guard let self, self.phase == .loading else { return }
                    self.awaited.remove(name)
                    if self.awaited.isEmpty {
                        self.phase = .ready
                    }
                }
            )
            .store(in: &subscriptions)
    }

    private static func message(for error: Error) -> String {
        guard let clientError = error as? ClientError else { return error.localizedDescription }
        switch clientError {
        case .ConvexError(let data):
            return (try? JSONDecoder().decode(String.self, from: Data(data.utf8))) ?? data
        case .ServerError(let message), .InternalError(let message):
            return message
        }
    }

    private func loadFixtures(_ scenario: Fixtures.Scenario) async {
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

    private func placeFixtureStake(_ amount: Int, on side: Side, duelId: String) throws {
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

    private func generateFixture(prompt: String, filament: Filament) -> String {
        let id = "local-\(UUID().uuidString)"
        products.insert(
            Product(
                id: id, name: String(prompt.prefix(40)), prompt: prompt,
                creatorId: profile?.id ?? "You", creatorName: profile?.displayName ?? "You",
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

@MainActor
private final class Once {
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Void, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
