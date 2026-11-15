import ConvexMobile
import Foundation

struct Profile: Decodable {
    let displayName: String
    @ConvexFloat var credits: Double
    @ConvexFloat var wins: Double
    @ConvexFloat var earningsCents: Double
}

struct ProductSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let creatorName: String
    @ConvexFloat var priceCents: Double
    @ConvexFloat var salesCount: Double

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, creatorName, priceCents, salesCount
    }
}

struct Duel: Decodable, Identifiable {
    let id: String
    let productA: ProductSummary
    let productB: ProductSummary
    @ConvexFloat var endsAt: Double
    @ConvexFloat var salesA: Double
    @ConvexFloat var salesB: Double
    @ConvexFloat var poolA: Double
    @ConvexFloat var poolB: Double

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case productA, productB, endsAt, salesA, salesB, poolA, poolB
    }
}

struct Product: Decodable, Identifiable {
    let id: String
    let name: String
    let status: String
    let filament: String
    @ConvexFloat var priceCents: Double
    @ConvexFloat var salesCount: Double

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, status, filament, priceCents, salesCount
    }
}

struct Checkout: Decodable {
    let orderId: String
    let purchaseUrl: String
}
