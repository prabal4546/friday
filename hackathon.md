# Hackathon log

- **Project:** Melt
- **Event:** Consumer Mobile Hackathon
- **What it does:** Native SwiftUI iOS app where creators describe a 3D-printable product, sell it through Whop, and duel other creators on sales while everyone else stakes demo credits on the winner.
- **Live app:** not deployed
- **Repo:** private
- **Frontend:** Other (native SwiftUI iOS app, not distributed yet)
- **Convex deployment:** not deployed
- **Components:** none
- **Convex features:** schema, tables, indexes, queries, mutations, actions, HTTP actions, scheduled functions, realtime queries
- **Auth:** none
- **AI models:** none
- **Started:** 2026-11-15T22:06:44Z
- **Last updated:** 2026-11-15T22:24:46Z

## Log

### 2026-11-15 - 8328019
Set up profiles, products, sales duels, demo-credit stakes, orders, and a
repeatable demo seed. A scheduled mutation settles each duel and pays the
winning side. A server-side action creates a Whop sandbox checkout, and a signed
webhook marks the order paid once and counts the sale toward the live duel. A
first SwiftUI shell subscribes to live duels through the Convex Swift client.
Model generation is not built yet. Convex features: schema, indexes, queries,
mutations, actions, HTTP actions, scheduled functions, realtime queries
(`convex/schema.ts`, `convex/duels.ts`, `convex/stakes.ts`, `convex/whop.ts`,
`convex/http.ts`, `Melt/MeltStore.swift`).
