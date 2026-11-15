# Hackathon log

- **Project:** Melt
- **Event:** Consumer Mobile Hackathon
- **What it does:** Native SwiftUI iOS app where creators describe a 3D-printable product, sell it through Whop, and duel other creators on sales while everyone else stakes demo credits on the winner.
- **Live app:** not deployed
- **Repo:** private
- **Frontend:** Other (native SwiftUI iOS app, not distributed yet)
- **Convex deployment:** https://wry-skunk-692.convex.cloud
- **Components:** none
- **Convex features:** schema, tables, indexes, queries, mutations, actions, HTTP actions, scheduled functions, realtime queries
- **Auth:** none
- **AI models:** none
- **Started:** 2026-11-15T22:06:44Z
- **Last updated:** 2026-11-15T22:50:14Z

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

### 2026-11-15 - 707f332
Rebuilt the app as a three-tab SwiftUI shell, Arena, Create, and Library, with
duel detail, staking, a RealityKit preview made from primitive shapes, and
loading, empty, and failed states. In this commit it ran on built-in fixtures,
not on Convex. Added UI tests that drive the flow on a simulator and a Revyl
build profile (`Melt/ArenaView.swift`, `Melt/Fixtures.swift`,
`MeltUITests/MeltUITests.swift`, `.revyl/config.yaml`).

### 2026-11-15 - working tree
Replaced the fixtures with live Convex data. The app ensures a device profile,
then subscribes to the profile, live and settled duels, the user's designs, and
stakes, so a stake from another client or a settled duel shows up without a
refresh. Create inserts a generating design that a scheduled mutation turns into
a draft after three seconds, a stand-in until model generation is built. Added a
reset for the demo seed. Convex features: realtime queries, mutations, scheduled
functions (`Melt/MeltStore.swift`, `Melt/ConvexRecords.swift`,
`convex/products.ts`, `convex/seed.ts`).
