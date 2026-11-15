import Foundation

enum Fixtures {
    enum Scenario: String {
        case demo, empty, error
    }

    struct World {
        var profile: Profile
        var products: [Product] = []
        var storefront: [Product] = []
        var liveDuels: [Duel] = []
        var settledDuels: [Duel] = []
        var stakes: [Stake] = []
        var orders: [Order] = []
        var sales: [Order] = []
    }

    static func empty() -> World {
        World(profile: Profile(id: "You", displayName: "You", credits: 1250, wins: 0, earningsCents: 0))
    }

    static func demo(now: Date = .now) -> World {
        func published(
            _ id: String, _ name: String, _ prompt: String, by creator: String,
            _ filament: Filament, _ priceCents: Int, sold: Int
        ) -> Product {
            Product(
                id: id, name: name, prompt: prompt, creatorId: creator, creatorName: creator,
                status: .published, filament: filament, priceCents: priceCents, salesCount: sold
            )
        }
        func draft(
            _ id: String, _ name: String, _ prompt: String, _ status: Product.Status,
            _ filament: Filament, _ priceCents: Int, printNote: String? = nil, failureReason: String? = nil
        ) -> Product {
            Product(
                id: id, name: name, prompt: prompt, creatorId: "You", creatorName: "You",
                status: status, filament: filament, priceCents: priceCents, salesCount: 0,
                printNote: printNote, failureReason: failureReason
            )
        }

        let vase = published("vase", "Twisted hex vase", "A hexagonal vase with a slow twist", by: "You", .sky, 2200, sold: 31)
        let capybara = published("capybara", "Sleepy capybara planter", "A desk planter shaped like a sleepy capybara", by: "You", .caramel, 1800, sold: 14)
        let ghost = published("ghost", "Ghost night light", "A ghost night light with a wavy hem", by: "Priya Raman", .bone, 1400, sold: 30)
        let fox = published("fox", "Fox desk buddy", "A fox that holds my earbuds", by: "Tomás Herrera", .tangerine, 1500, sold: 30)
        let duck = published("duck", "Duck in a top hat", "A duck in a top hat for my desk", by: "Wen Liu", .sunflower, 1700, sold: 21)
        let bins = published("bins", "Stackable hex bins", "Two hexagonal bins that stack", by: "Kwame Mensah", .matcha, 900, sold: 0)
        let egg = published("egg", "Egg cup", "An egg cup with a wide foot", by: "Aoife Byrne", .sky, 1100, sold: 0)

        func duel(
            _ id: String, _ a: Product, _ b: Product, hours: Double, live: Bool,
            sales: (Int, Int), pools: (Int, Int)
        ) -> Duel {
            Duel(
                id: id, productA: a, productB: b, theme: live ? "Desk buddies" : nil,
                endsAt: now.addingTimeInterval(hours * 3600), isLive: live,
                salesA: sales.0, salesB: sales.1, poolA: pools.0, poolB: pools.1,
                winner: live ? nil : (sales.0 > sales.1 ? .a : .b)
            )
        }

        return World(
            profile: Profile(id: "You", displayName: "You", credits: 1250, wins: 1, earningsCents: 59950),
            products: [
                draft(
                    "dragon", "Tiny dragon that guards my charging cable",
                    "A tiny dragon that guards my charging cable and judges anyone who unplugs it",
                    .generating, .matcha, 1500
                ),
                draft("rocket", "Rocket pen cup", "A retro rocket that holds pens on my desk", .ready, .lava, 1600),
                capybara,
                draft(
                    "coasters", "Honeycomb coaster set", "A set of honeycomb coasters that lock together",
                    .failed, .sunflower, 1200, failureReason: "The model service timed out"
                ),
                draft(
                    "lamp", "Mushroom lamp shade", "A mushroom shaped shade for a small desk lamp",
                    .ready, .grape, 1900,
                    printNote: "The cap overhang needs supports, which adds $1.20 per print"
                ),
                vase,
            ],
            storefront: [ghost, fox, duck, bins, egg, capybara, vase],
            liveDuels: [
                duel("live-1", capybara, ghost, hours: 5.69, live: true, sales: (14, 11), pools: (3200, 2450)),
                duel("live-2", fox, duck, hours: 11.09, live: true, sales: (8, 9), pools: (1100, 1900)),
                duel("live-3", bins, egg, hours: 23.87, live: true, sales: (0, 0), pools: (0, 0)),
            ],
            settledDuels: [
                duel("settled-1", vase, fox, hours: -20, live: false, sales: (31, 22), pools: (12400, 8650)),
                duel("settled-2", duck, ghost, hours: -72, live: false, sales: (12, 19), pools: (2100, 4300)),
            ],
            stakes: [
                Stake(duelId: "settled-1", side: .a, amount: 200, payout: 340),
                Stake(duelId: "settled-2", side: .a, amount: 100, payout: 0),
            ],
            orders: [
                Order(
                    id: "order-bought", productId: ghost.id, productName: ghost.name,
                    buyerName: "You", creatorName: ghost.creatorName, filament: ghost.filament,
                    amountCents: ghost.priceCents, status: .paid, fulfillment: .printing
                )
            ],
            sales: [
                Order(
                    id: "order-sale", productId: vase.id, productName: vase.name,
                    buyerName: "Priya Raman", creatorName: "You", filament: vase.filament,
                    amountCents: vase.priceCents, status: .paid, fulfillment: .queued
                )
            ]
        )
    }
}
