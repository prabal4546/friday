# Melt

Melt is a native SwiftUI iOS app for the Consumer Mobile Hackathon: describe a product, get a 3D-printable model, sell it through Whop, and duel other creators on sales while everyone else stakes demo credits on the winner.

This repository currently holds the infrastructure the app is built on: the Convex backend, the Whop sandbox payment boundary, an unstyled iOS shell that proves the wiring, and the Revyl build config.

## Layout

| Path | What it is |
| --- | --- |
| `convex/` | Backend: schema, queries, mutations, the Whop checkout action, and HTTP webhooks |
| `convex/seed.ts` | Deterministic demo world (6 creators, 11 products, 3 live and 2 settled duels) |
| `convex/melt.test.ts` | Backend tests, run with `pnpm test` |
| `Melt/` | SwiftUI shell app sources |
| `project.yml`, `Melt.xcodeproj` | XcodeGen spec and the project it generates (both committed) |
| `Config/Melt.xcconfig` | The Convex deployment URL the app connects to |
| `.revyl/config.yaml` | Revyl build recipe for the simulator app |

## Backend

Requires Node 22 or newer and pnpm.

```sh
pnpm install
pnpm test
```

To run against a local backend with no Convex account:

```sh
CONVEX_AGENT_MODE=anonymous pnpm dev     # serves http://127.0.0.1:3210, keep it running
CONVEX_AGENT_MODE=anonymous pnpm seed    # in a second terminal, safe to repeat
```

To use a cloud deployment, which Whop webhooks and TestFlight builds need, run `pnpm exec convex login` once, then `pnpm dev` and `pnpm seed` without the `CONVEX_AGENT_MODE` prefix. Put the deployment's `https://<name>.convex.cloud` URL in `Config/Melt.xcconfig`.

### Identity

There is no sign-in. The app stores a random device ID in the Keychain and passes it to every function. `profiles:ensure` creates a profile with 1,250 demo credits; the first device that calls it with `claimSeed: true` takes over the seeded "You" profile and its products.

### Environment variables

These live on the Convex deployment only. They never go in the repository or the app.

| Name | Purpose |
| --- | --- |
| `WHOP_API_KEY` | Company API key from the Whop sandbox dashboard, used by `whop:createCheckout` |
| `WHOP_WEBHOOK_SECRET` | The `ws_...` secret of the webhook that points at this deployment |
| `WHOP_ENVIRONMENT` | Optional. Anything other than `production` uses the Whop sandbox API |

```sh
pnpm exec convex env set WHOP_API_KEY
pnpm exec convex env set WHOP_WEBHOOK_SECRET
```

## Whop sandbox

1. Create an API key at sandbox.whop.com/dashboard/developer and set it as `WHOP_API_KEY`.
2. Add a webhook for the `payment.succeeded` event that points at `https://<name>.convex.site/webhooks/whop`, and set its secret as `WHOP_WEBHOOK_SECRET`.

`whop:createCheckout` records a pending order, then creates a one-time checkout whose metadata carries `productId`, `creatorId`, and `orderId`. The webhook verifies the Standard Webhooks signature, marks the order paid exactly once, and counts the sale toward the product's live duel. A paid order stops at fulfillment `queued`; nothing is sent to a print service.

## iOS app

Requires Xcode with an iOS Simulator runtime. Open `Melt.xcodeproj`, or build from the command line:

```sh
xcodebuild -project Melt.xcodeproj -scheme Melt -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build ARCHS=arm64
```

The app reads `CONVEX_DEPLOYMENT_URL` from `Config/Melt.xcconfig`. In an xcconfig file `//` starts a comment, so the URL is written as `http:/$()/127.0.0.1:3210`.

After editing `project.yml`, regenerate the project with `xcodegen generate` and commit the result.

## Agent tooling

`npx convex ai-files install` wrote the Convex guidelines (`convex/_generated/ai/guidelines.md`), the Convex agent skills (`.agents/skills`, copied to `.claude/skills` for Claude Code), and the Convex sections of `AGENTS.md` and `CLAUDE.md`. Run it again to refresh them.

The Convex hackathon skill in `.agents/skills/convex-hackathon-skill` keeps `hackathon.md`, the public build log, current. Ask your coding agent to update the hackathon log after a work session.

## Revyl

```sh
revyl auth login
revyl app create --name "Melt iOS" --platform ios   # put the ID in build.profiles.development.ios.app_id
revyl config validate
revyl build --profile development --platform ios
```

Revyl's cloud simulators cannot reach a backend on your machine, so point `Config/Melt.xcconfig` at a cloud Convex deployment before building there.
