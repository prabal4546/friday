# Melt

Melt is a native SwiftUI iOS app for the Consumer Mobile Hackathon: describe a product, get a 3D-printable model, sell it through Whop, and duel other creators on sales while everyone else stakes demo credits on the winner.

This repository holds the Convex backend, the SwiftUI app, the Whop sandbox payment boundary, and the Revyl build config. Browsing, staking, generating and publishing a design, checkout, creator earnings, and demo print fulfillment work today.

## Layout

| Path | What it is |
| --- | --- |
| `convex/` | Backend: schema, queries, mutations, the Whop checkout action, and HTTP webhooks |
| `convex/generation.ts` | Model generation through fal: queue the job, poll it, keep the USDZ link and an STL |
| `convex/lib/stl.ts` | Converts fal's OBJ into the binary STL a printer needs |
| `convex/seed.ts` | Deterministic demo world (6 creators, 11 products, 3 live and 2 settled duels) |
| `convex/melt.test.ts` | Backend tests, run with `pnpm test` |
| `Melt/` | SwiftUI app sources |
| `MeltUITests/` | UI tests that drive the app on a simulator |
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
# serves http://127.0.0.1:3210 and points .env.local at it; keep it running
CONVEX_AGENT_MODE=anonymous CONVEX_DEPLOYMENT=anonymous:anonymous-agent pnpm dev
# in a second terminal, safe to repeat
CONVEX_AGENT_MODE=anonymous pnpm seed
```

The app's default backend is the cloud dev deployment `https://wry-skunk-692.convex.cloud`, set in `Config/Melt.xcconfig`. To push backend changes to it, run `pnpm exec convex login` once, then `pnpm dev`. If the CLI was last used with the local backend, point it back at the cloud first:

```sh
pnpm exec convex dev --once --configure existing --team prabaljit-walia --project melt --dev-deployment cloud
```

`pnpm exec convex run seed:reset` wipes the deployment and rebuilds the demo world. Run it before a demo so the next device to open the app takes over the seeded "You" profile.

### Identity

There is no sign-in. The app stores a random device ID in the Keychain and passes it to every function. `profiles:ensure` creates a profile with 1,250 demo credits; the first device that calls it with `claimSeed: true` takes over the seeded "You" profile and its products.

### Environment variables

These live on the Convex deployment only. They never go in the repository or the app.

| Name | Purpose |
| --- | --- |
| `FAL_KEY` | fal API key for model generation. Without it, new designs get a stand-in shape |
| `WHOP_API_KEY` | Company API key from the Whop sandbox dashboard, used by `whop:createCheckout` |
| `WHOP_WEBHOOK_SECRET` | The `ws_...` secret of the webhook that points at this deployment |
| `WHOP_ENVIRONMENT` | Optional. Anything other than `production` uses the Whop sandbox API |

Each command prompts for the value, so it stays out of your shell history. `pnpm exec convex env list` shows what is set.

```sh
pnpm exec convex env set FAL_KEY
pnpm exec convex env set WHOP_API_KEY
pnpm exec convex env set WHOP_WEBHOOK_SECRET
```

## Model generation

`products:create` adds a design with the status `generating`. What happens next depends on `FAL_KEY`:

- **Key set.** `generation:start` queues the prompt on fal's Meshy 7.1 text-to-3D model (`fal-ai/meshy/v7.1/text-to-3d`, preview mode, about $0.80 a model). fal calls `/webhooks/fal` when the job ends, and a poll every 10 seconds for up to 10 minutes covers a missed callback. The finished design keeps fal's USDZ link for the in-app preview. fal returns no STL, so the OBJ is converted to a binary STL (Z up, longest side 80 mm) and kept in Convex file storage for printing. If the conversion fails the design is still usable and carries a printability warning. A refused, failed, or timed-out job marks the design failed with a reason.
- **No key.** A scheduled mutation turns the design into a draft after three seconds with no model file, so the whole flow stays usable.

In the app, a design's page downloads the USDZ once, caches it in the app's Caches folder, and shows it on a RealityKit turntable you can drag to orbit, pause, and recolor with the filament picker. When a design has no model, or the file can't be loaded, the turntable shows a stand-in shape and says so.

## Whop sandbox

1. Create an API key at sandbox.whop.com/dashboard/developer and set it as `WHOP_API_KEY`.
2. Add a webhook for the `payment.succeeded` event that points at `https://<name>.convex.site/webhooks/whop`, and set its secret as `WHOP_WEBHOOK_SECRET`.

`whop:createCheckout` records a pending order, then creates a one-time checkout whose metadata carries `productId`, `creatorId`, and `orderId`. The webhook verifies the Standard Webhooks signature, marks the order paid exactly once, and counts the sale toward the product's live duel. A paid order stops at fulfillment `queued`; nothing is sent to a print service.

The Shop tab lists every published design. A buyer opens one and taps Buy; with `WHOP_API_KEY` set, Melt opens Whop's hosted sandbox checkout. The payment webhook is the only path that marks that order paid. Without a key, the same button makes an explicitly labelled demo payment so the two-person judge flow remains runnable.

Paid orders appear live on both devices: the buyer sees the order in Library, while the creator sees the sale and earnings. The creator can advance it through **Paid → Submitted → Printing**. Submitted creates a local Slant draft ID and quote; the app never calls a production print endpoint.

To prove the no-key flow from the CLI after seeding, use two distinct device IDs:

```sh
pnpm exec convex run profiles:ensure '{"deviceId":"seller","claimSeed":true}'
pnpm exec convex run profiles:ensure '{"deviceId":"buyer","displayName":"Judge Buyer"}'
pnpm exec convex run products:storefront '{}'
pnpm exec convex run orders:mine '{"deviceId":"buyer"}'
pnpm exec convex run orders:sales '{"deviceId":"seller"}'
```

## iOS app

Requires Xcode with an iOS 18 or newer Simulator runtime. The app has four tabs, Arena, Shop, Create, and Library, and shows live data from the Convex deployment in `Config/Melt.xcconfig`: stakes, published products, orders, earnings, fulfillment, new designs, and settled duels from any client appear without a refresh.

Open `Melt.xcodeproj` in Xcode, pick an iPhone simulator, and press Run. Or from the command line:

```sh
xcodebuild -project Melt.xcodeproj -scheme Melt -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build ARCHS=arm64
open -a Simulator    # boot an iPhone from File > Open Simulator if none is running
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Melt.app
xcrun simctl launch booted com.prabaljitwalia.melt
```

Launch arguments, added to the end of the launch command:

- `-ConvexDeploymentURL http://127.0.0.1:3210` uses the local backend instead of the cloud one.
- `-MeltScenario demo` runs on built-in fixtures (`Melt/Fixtures.swift`) with no backend at all. `-MeltScenario empty` and `-MeltScenario error` show the empty and failed-to-load states.

The UI tests walk the main flow on fixtures (stake on a duel, open a product preview, recolor a design, generate a design, find it in Library) and both of those states:

```sh
xcodebuild test -project Melt.xcodeproj -scheme Melt -derivedDataPath build \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

To also run the live test, reset the seed and pass the deployment URL. It stakes on a duel and creates a design on that deployment, which is a real, billed generation when `FAL_KEY` is set:

```sh
pnpm exec convex run seed:reset
TEST_RUNNER_MELT_LIVE_URL=https://wry-skunk-692.convex.cloud xcodebuild test -project Melt.xcodeproj \
  -scheme Melt -derivedDataPath build -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
pnpm exec convex run seed:reset
```

`testLiveModel` checks a real model in the preview: it opens a ready design from the simulator's Library and fails if the stand-in shape is showing. Generate a design in the app first, wait until it leaves `generating`, and don't reset the seed in between:

```sh
TEST_RUNNER_MELT_LIVE_URL=https://wry-skunk-692.convex.cloud TEST_RUNNER_MELT_LIVE_MODEL="A tiny rocket" \
  xcodebuild test -project Melt.xcodeproj -scheme Melt -derivedDataPath build \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MeltUITests/MeltUITests/testLiveModel
```

In an xcconfig file `//` starts a comment, so the URL in `Config/Melt.xcconfig` is written as `https:/$()/wry-skunk-692.convex.cloud`.

After editing `project.yml`, regenerate the project with `xcodegen generate` and commit the result.

## Agent tooling

`npx convex ai-files install` wrote the Convex guidelines (`convex/_generated/ai/guidelines.md`), the Convex agent skills (`.agents/skills`, copied to `.claude/skills` for Claude Code), and the Convex sections of `AGENTS.md` and `CLAUDE.md`. Run it again to refresh them.

The Convex hackathon skill in `.agents/skills/convex-hackathon-skill` keeps `hackathon.md`, the public build log, current. Ask your coding agent to update the hackathon log after a work session.

## Revyl

`.revyl/config.yaml` has one `preview` profile that builds the simulator app on Revyl's cloud runners, and turns on Proof of Changes for pull requests. Proof of Changes needs the Revyl GitHub App installed on this repository.

```sh
revyl auth login
revyl build --profile preview --platform ios
revyl device start --app-id f867bd88-1e8c-447a-bb1a-c5f7744a97cc --open
```

Revyl's cloud simulators cannot reach a backend on your machine, so point `Config/Melt.xcconfig` at a cloud Convex deployment before building there.
