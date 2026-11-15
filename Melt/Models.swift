import SwiftUI

enum Side: String, CaseIterable {
    case a, b
}

enum Filament: String, CaseIterable, Identifiable {
    case sky, grape, sunflower, caramel, lava, matcha, bone, tangerine

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .sky: Color(red: 0.42, green: 0.71, blue: 0.93)
        case .grape: Color(red: 0.49, green: 0.34, blue: 0.76)
        case .sunflower: Color(red: 0.97, green: 0.78, blue: 0.22)
        case .caramel: Color(red: 0.76, green: 0.53, blue: 0.30)
        case .lava: Color(red: 0.86, green: 0.24, blue: 0.18)
        case .matcha: Color(red: 0.55, green: 0.71, blue: 0.40)
        case .bone: Color(red: 0.90, green: 0.86, blue: 0.76)
        case .tangerine: Color(red: 0.96, green: 0.55, blue: 0.20)
        }
    }
}

struct Profile: Equatable {
    let id: String
    var displayName: String
    var credits: Int
    var wins: Int
    var earningsCents: Int
}

struct Product: Identifiable, Hashable {
    enum Status: String {
        case generating, ready, published, failed

        var label: String {
            switch self {
            case .generating: "Generating"
            case .ready: "Draft"
            case .published: "Published"
            case .failed: "Failed"
            }
        }
    }

    let id: String
    var name: String
    var prompt: String
    var creatorId: String
    var creatorName: String
    var status: Status
    var filament: Filament
    var priceCents: Int
    var salesCount: Int
    var printNote: String?
    var failureReason: String?
    var usdzURL: URL?
}

struct Duel: Identifiable, Hashable {
    let id: String
    var productA: Product
    var productB: Product
    var theme: String?
    var endsAt: Date
    var isLive: Bool
    var salesA: Int
    var salesB: Int
    var poolA: Int
    var poolB: Int
    var winner: Side?

    func product(_ side: Side) -> Product {
        side == .a ? productA : productB
    }
}

struct Stake: Hashable {
    let duelId: String
    let side: Side
    let amount: Int
    var payout: Int?
}

struct Friend: Identifiable, Hashable {
    let id: String
    var displayName: String
    var products: [Product]
}

struct Order: Identifiable, Hashable {
    enum PaymentStatus: String {
        case pending, paid, failed
    }

    enum Fulfillment: String {
        case none, queued, submitted, printing

        var label: String {
            switch self {
            case .none: "Awaiting payment"
            case .queued: "Paid"
            case .submitted: "Submitted"
            case .printing: "Printing"
            }
        }
    }

    let id: String
    let productId: String
    var productName: String
    var buyerName: String
    var creatorName: String
    var filament: Filament
    var amountCents: Int
    var status: PaymentStatus
    var fulfillment: Fulfillment
    var purchaseURL: URL?
    var slantQuoteCents: Int?
    var slantOrderId: String?
}

struct MeltError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

func dollars(_ cents: Int) -> String {
    (Decimal(cents) / 100).formatted(.currency(code: "USD"))
}
