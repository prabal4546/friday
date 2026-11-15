import ConvexMobile
import Foundation

struct ProfileRecord: Decodable {
    let _id: String
    let displayName: String
    @ConvexFloat var credits: Double
    @ConvexFloat var wins: Double
    @ConvexFloat var earningsCents: Double

    var profile: Profile {
        Profile(
            id: _id, displayName: displayName, credits: Int(credits), wins: Int(wins),
            earningsCents: Int(earningsCents)
        )
    }
}

struct ProductRecord: Decodable {
    let _id: String
    let name: String
    let prompt: String
    let creatorId: String
    let creatorName: String?
    let status: String
    let filament: String
    @ConvexFloat var priceCents: Double
    @ConvexFloat var salesCount: Double
    let printNote: String?
    let failureReason: String?
    let usdzUrl: String?

    func product(creatorName fallback: String) -> Product {
        Product(
            id: _id, name: name, prompt: prompt, creatorId: creatorId,
            creatorName: creatorName ?? fallback,
            status: Product.Status(rawValue: status) ?? .failed,
            filament: Filament(rawValue: filament) ?? .bone,
            priceCents: Int(priceCents), salesCount: Int(salesCount),
            printNote: printNote, failureReason: failureReason,
            usdzURL: usdzUrl.flatMap(URL.init(string:))
        )
    }
}

struct DuelRecord: Decodable {
    let _id: String
    let productA: ProductRecord
    let productB: ProductRecord
    let theme: String?
    let status: String
    let winner: String?
    @ConvexFloat var endsAt: Double
    @ConvexFloat var salesA: Double
    @ConvexFloat var salesB: Double
    @ConvexFloat var poolA: Double
    @ConvexFloat var poolB: Double

    var duel: Duel {
        Duel(
            id: _id, productA: productA.product(creatorName: "Unknown"),
            productB: productB.product(creatorName: "Unknown"), theme: theme,
            endsAt: Date(timeIntervalSince1970: endsAt / 1000), isLive: status == "live",
            salesA: Int(salesA), salesB: Int(salesB), poolA: Int(poolA), poolB: Int(poolB),
            winner: winner.flatMap(Side.init(rawValue:))
        )
    }
}

struct StakeRecord: Decodable {
    let duelId: String
    let side: String
    @ConvexFloat var amount: Double
    @OptionalConvexFloat var payout: Double?

    var stake: Stake? {
        guard let side = Side(rawValue: side) else { return nil }
        return Stake(duelId: duelId, side: side, amount: Int(amount), payout: payout.map { Int($0) })
    }
}
