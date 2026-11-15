import Combine
import ConvexMobile
import Foundation

@MainActor
final class MeltStore: ObservableObject {
    @Published var profile: Profile?
    @Published var liveDuels: [Duel] = []
    @Published var products: [Product] = []
    @Published var status: String

    private let client: ConvexClient
    private let deviceId = DeviceIdentity.current()
    private var subscriptions = Set<AnyCancellable>()

    init() {
        let url = Bundle.main.object(forInfoDictionaryKey: "ConvexDeploymentURL") as? String ?? ""
        client = ConvexClient(deploymentUrl: url)
        status = "Connecting to \(url)"
    }

    func start() async {
        guard subscriptions.isEmpty else { return }
        do {
            let _: String = try await client.mutation(
                "profiles:ensure",
                with: ["deviceId": deviceId, "claimSeed": true]
            )
        } catch {
            status = "profiles:ensure failed: \(error)"
            return
        }
        status = "Connected"
        watch("profiles:me", with: ["deviceId": deviceId], into: \.profile)
        watch("duels:live", into: \.liveDuels)
        watch("products:mine", with: ["deviceId": deviceId], into: \.products)
    }

    func stake(on side: String, in duel: Duel) async {
        do {
            let _: String = try await client.mutation(
                "stakes:place",
                with: ["deviceId": deviceId, "duelId": duel.id, "side": side, "amount": 50.0]
            )
            status = "Staked 50 credits on side \(side.uppercased())"
        } catch {
            status = "stakes:place failed: \(error)"
        }
    }

    func checkout(_ product: ProductSummary) async -> URL? {
        do {
            let checkout: Checkout = try await client.action(
                "whop:createCheckout",
                with: ["deviceId": deviceId, "productId": product.id]
            )
            status = "Order \(checkout.orderId) is pending payment"
            return URL(string: checkout.purchaseUrl)
        } catch {
            status = "whop:createCheckout failed: \(error)"
            return nil
        }
    }

    private func watch<Value: Decodable>(
        _ name: String,
        with args: [String: ConvexEncodable?]? = nil,
        into keyPath: ReferenceWritableKeyPath<MeltStore, Value>
    ) {
        client.subscribe(to: name, with: args, yielding: Value.self)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.status = "\(name) failed: \(error)"
                    }
                },
                receiveValue: { [weak self] value in
                    self?[keyPath: keyPath] = value
                }
            )
            .store(in: &subscriptions)
    }
}
