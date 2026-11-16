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

    @Published var shelfSection = ShelfSection.designs
    @Published var selectedTab = MeltTab.create
    @Published var creatorPrompt = Product.starter.prompt {
        didSet { UserDefaults.standard.set(creatorPrompt, forKey: "\(sessionPrefix).prompt") }
    }
    @Published var activeProductId: String? {
        didSet { UserDefaults.standard.set(activeProductId, forKey: "\(sessionPrefix).product") }
    }
    @Published var creatorColorCustomized = false
    @Published var creatorFilament = Filament.bone {
        didSet { UserDefaults.standard.set(creatorFilament.rawValue, forKey: "\(sessionPrefix).filament") }
    }
    @Published var generationQuality = GenerationQuality.detailed {
        didSet { UserDefaults.standard.set(generationQuality.rawValue, forKey: "creator.quality") }
    }
    private var introducedModels = Set(UserDefaults.standard.stringArray(forKey: "preview.introducedModels") ?? [])

    func claimModelIntroduction(_ id: String) -> Bool {
        guard introducedModels.insert(id).inserted else { return false }
        UserDefaults.standard.set(Array(introducedModels), forKey: "preview.introducedModels")
        return true
    }

    @Published private(set) var phase = Phase.loading
    @Published private(set) var profile: Profile?
    @Published private(set) var whopStore: WhopStoreRecord?
    @Published private(set) var whopStoreLoaded = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var storefront: [Product] = []
    @Published private(set) var liveDuels: [Duel] = []
    @Published private(set) var settledDuels: [Duel] = []
    @Published private(set) var stakes: [Stake] = []
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var orders: [Order] = []
    @Published private(set) var sales: [Order] = []

    private let scenario = Fixtures.Scenario(rawValue: UserDefaults.standard.string(forKey: "MeltScenario") ?? "")
    private let deviceId = DeviceIdentity.current()
    private lazy var client = ConvexClient(
        deploymentUrl: UserDefaults.standard.string(forKey: "ConvexDeploymentURL")
            ?? Bundle.main.object(forInfoDictionaryKey: "ConvexDeploymentURL") as? String ?? ""
    )
    private var subscriptions = Set<AnyCancellable>()
    private var awaited = Set<String>()

    private var sessionPrefix: String { scenario == nil ? "creator" : "fixture" }

    init() {
        generationQuality = GenerationQuality(rawValue: UserDefaults.standard.string(forKey: "creator.quality") ?? "") ?? .detailed
        if scenario == nil {
            creatorPrompt = UserDefaults.standard.string(forKey: "creator.prompt") ?? Product.starter.prompt
            // Each launch opens on the bundled design; saved work stays in My shelf.
            activeProductId = nil
            creatorFilament = Filament(rawValue: UserDefaults.standard.string(forKey: "creator.filament") ?? "") ?? .bone
        }
    }

    func load() async {
        phase = .loading
        if let scenario {
            if phase == .loading && products.isEmpty {
                activeProductId = nil
                creatorPrompt = Product.starter.prompt
                creatorFilament = .bone
            }
            whopStore = WhopStoreRecord(name: "Demo store", accountId: "fixture")
            whopStoreLoaded = true
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
        awaited = ["profiles:me", "duels:live", "products:mine", "products:storefront", "friends:list", "orders:mine", "orders:sales"]
        let mine: [String: ConvexEncodable?] = ["deviceId": deviceId]
        watch("profiles:me", with: mine) { [weak self] (record: ProfileRecord?) in
            self?.profile = record?.profile
        }
        watch("whopData:myStore", with: mine) { [weak self] (record: WhopStoreRecord?) in
            self?.whopStore = record
            self?.whopStoreLoaded = true
        }
        watch("duels:live") { [weak self] (records: [DuelRecord]) in
            self?.liveDuels = records.map(\.duel)
        }
        watch("duels:settled") { [weak self] (records: [DuelRecord]) in
            self?.settledDuels = records.map(\.duel)
        }
        watch("products:mine", with: mine) { [weak self] (records: [ProductRecord]) in
            self?.products = records.map { $0.product(creatorName: "You") }
            if let id = self?.activeProductId, !records.contains(where: { $0._id == id }) {
                self?.activeProductId = nil
            }
        }
        watch("products:storefront") { [weak self] (records: [ProductRecord]) in
            self?.storefront = records.map { $0.product(creatorName: "Unknown") }
        }
        watch("stakes:mine", with: mine) { [weak self] (records: [StakeRecord]) in
            self?.stakes = records.compactMap(\.stake)
        }
        watch("friends:list", with: mine) { [weak self] (records: [FriendRecord]) in
            self?.friends = records.map(\.friend)
        }
        watch("orders:mine", with: mine) { [weak self] (records: [OrderRecord]) in
            self?.orders = records.map(\.order)
        }
        watch("orders:sales", with: mine) { [weak self] (records: [OrderRecord]) in
            self?.sales = records.map(\.order)
        }
    }

    func duel(id: String) -> Duel? {
        (liveDuels + settledDuels).first { $0.id == id }
    }

    func product(id: String) -> Product? {
        let inDuels = (liveDuels + settledDuels).flatMap { [$0.productA, $0.productB] }
        return (products + storefront + inDuels).first { $0.id == id }
    }

    func stake(for duelId: String) -> Stake? {
        stakes.first { $0.duelId == duelId }
    }

    func isFriend(profileId: String) -> Bool {
        friends.contains { $0.id == profileId }
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

    func renameProfile(_ displayName: String) async throws {
        if scenario != nil {
            profile?.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        do {
            try await client.mutation(
                "profiles:rename", with: ["deviceId": deviceId, "displayName": displayName]
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
                with: ["deviceId": deviceId, "prompt": prompt, "filament": filament.rawValue, "generationQuality": generationQuality.rawValue]
            )
        } catch {
            throw MeltError(Self.message(for: error))
        }
    }

    func setFilament(_ filament: Filament, productId: String) async throws {
        if scenario != nil {
            if let index = products.firstIndex(where: { $0.id == productId }) {
                products[index].filament = filament
                products[index].colorCustomized = true
            }
            return
        }
        do {
            try await client.mutation(
                "products:setFilament",
                with: ["deviceId": deviceId, "productId": productId, "filament": filament.rawValue]
            )
        } catch {
            throw MeltError(Self.message(for: error))
        }
    }

    func resetAppearance(productId: String) async throws {
        guard let product = product(id: productId) else { throw MeltError("This design couldn't be found") }
        if scenario != nil {
            if let index = products.firstIndex(where: { $0.id == productId }) { products[index].colorCustomized = false }
            return
        }
        do {
            try await client.mutation("products:setFilament", with: ["deviceId": deviceId, "productId": productId,
                                                                  "filament": product.filament.rawValue, "useOriginal": true])
        } catch { throw MeltError(Self.message(for: error)) }
    }

    func publish(productId: String, priceCents: Int) async throws -> URL? {
        if scenario != nil {
            guard let index = products.firstIndex(where: { $0.id == productId }) else { return nil }
            products[index].status = .published
            products[index].priceCents = priceCents
            storefront.insert(products[index], at: 0)
            return nil
        }
        do {
            let result: WhopPublishRecord = try await client.action(
                "whop:publishProduct",
                with: ["deviceId": deviceId, "productId": productId, "priceCents": Double(priceCents)]
            )
            guard let url = URL(string: result.listingUrl) else { throw MeltError("Whop returned an invalid listing link") }
            return url
        } catch {
            throw MeltError(Self.message(for: error))
        }
    }

    func saveStarter(filament: Filament) async throws -> String {
        guard let profile else { throw MeltError("Connect to save your design") }
        if let activeProductId { return activeProductId }
        if scenario != nil {
            var starter = Product.starter
            starter = Product(id: "local-\(UUID().uuidString)", name: starter.name, prompt: starter.prompt,
                              creatorId: profile.id, creatorName: profile.displayName, status: .ready,
                              filament: filament, priceCents: starter.priceCents, salesCount: 0, starterKey: "friday-home", colorCustomized: creatorColorCustomized)
            products.insert(starter, at: 0)
            activeProductId = starter.id
            return starter.id
        }
        do {
            let id: String = try await client.mutation("products:createStarter", with: ["deviceId": deviceId, "filament": filament.rawValue, "starterKey": "friday-home", "colorCustomized": creatorColorCustomized])
            activeProductId = id
            return id
        } catch { throw MeltError(Self.message(for: error)) }
    }

    func edit(_ product: Product) {
        activeProductId = product.id
        creatorPrompt = product.prompt
        creatorFilament = product.filament
        selectedTab = .create
    }

    func checkout(productId: String) async throws -> CheckoutResult {
        if scenario != nil {
            guard let product = product(id: productId), let profile,
                  product.status == .published || (product.status == .ready && product.creatorId == profile.id) else {
                throw MeltError("This design isn't available to order")
            }
            let order = Order(id: "local-\(UUID().uuidString)", productId: product.id, productName: product.name,
                              buyerName: profile.displayName, creatorName: product.creatorName,
                              filament: product.filament, amountCents: product.priceCents, status: .paid, fulfillment: .queued)
            orders.insert(order, at: 0)
            return CheckoutResult(orderId: order.id, purchaseURL: nil)
        }
        do {
            let result: CheckoutRecord = try await client.action("whop:createCheckout", with: ["deviceId": deviceId, "productId": productId])
            return CheckoutResult(orderId: result.orderId, purchaseURL: result.purchaseUrl.flatMap(URL.init(string:)))
        } catch { throw MeltError(Self.message(for: error)) }
    }

    func connect(profileId: String) async throws {
        if scenario != nil {
            guard !isFriend(profileId: profileId),
                  let product = storefront.first(where: { $0.creatorId == profileId }) else { return }
            friends.append(Friend(id: profileId, displayName: product.creatorName, products: [product]))
            return
        }
        do {
            let _: String = try await client.mutation(
                "friends:connect", with: ["deviceId": deviceId, "profileId": profileId]
            )
        } catch {
            throw MeltError(Self.message(for: error))
        }
    }

    func createDuel(productId: String, opponentProductId: String) async throws -> String {
        if scenario != nil {
            guard let mine = products.first(where: { $0.id == productId }),
                  let theirs = storefront.first(where: { $0.id == opponentProductId }) else {
                throw MeltError("Pick two published products")
            }
            let duel = Duel(
                id: "local-\(UUID().uuidString)", productA: mine, productB: theirs,
                theme: "New challenge", endsAt: .now.addingTimeInterval(24 * 3600),
                isLive: true, salesA: 0, salesB: 0, poolA: 0, poolB: 0
            )
            liveDuels.insert(duel, at: 0)
            return duel.id
        }
        do {
            return try await client.mutation(
                "duels:challenge",
                with: ["deviceId": deviceId, "productId": productId, "opponentProductId": opponentProductId]
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
                once.resume(with: .failure(MeltError("Friday couldn't reach its backend. Check your connection and try again.")))
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
            phase = .failed("Check your connection and try again.")
            return
        }
        let world = scenario == .empty ? Fixtures.empty() : Fixtures.demo()
        profile = world.profile
        products = world.products
        storefront = world.storefront
        liveDuels = world.liveDuels
        settledDuels = world.settledDuels
        stakes = world.stakes
        friends = world.friends
        orders = world.orders
        sales = world.sales
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
