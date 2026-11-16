# Friday

Friday is a native SwiftUI app for creating small objects, ordering prints, publishing designs, and competing with friends on sales.

## App

The app opens in **Create** with the supplied textured polka-dot man keychain, bundled as `Melt/Resources/FridayHome.usdz`. Rotate it, choose a body color, edit the prompt, or save it as a draft. The original texture is selected initially; Original restores it after recoloring. Opening the app does not call a generation service.

- **Create:** preview, color, prompt, generation, ordering, and publishing.
- **Explore:** published products and 24-hour sales challenges. Credit backing lives inside challenge details.
- **My shelf:** designs, orders, and sales. Profile editing is separate.

Prompt input and generation quality persist between launches. Every launch opens the supplied model; saved designs remain in My shelf. Generated models use RealityKit and a local USDZ cache. Imported materials and textures are preserved by default. Explicit recoloring changes only the material tint; the Original control restores the source appearance. The bundled starter keeps the original GLB geometry, normals, UVs, JPEG texture and material settings. `scripts/convert-home-model.py` reproduces its USDZ from the original GLB. Older saved procedural keychains remain compatible. Customer copy uses functional labels without demo banners or promotional slogans.

Fast/Detailed is remembered between launches. Fast uses Meshy T2 preview geometry (4,000 target triangles); Detailed uses Meshy 7.1 preview geometry (20,000). Neither mode adds texturing. The six-request development comparison measured median ready times of 28.9s and 108.7s respectively. Detailed remains the default because Fast missed requested functional features. These are observed runs, not latency guarantees; prompts, timings and observations are in `scripts/generation-benchmark-results.json`.

The preview starts at 35° yaw with a camera elevated 15°, fitted to the rotated bounds. A model-shaped ground shadow and key/fill lighting reveal depth. New full-size previews make one four-second turn to 55°; drag interrupts it. Reduce Motion and grid thumbnails skip that turn, and leaving the screen or app stops motion. Horizontal rotation, bounded vertical orbit, and explicit Spin/Pause remain available. USDZ files without material bindings receive a neutral fallback; authored materials are retained.

The seven preloaded shop/challenge designs use explicit `catalogKey` values and bundled RealityKit geometry in `Melt/CatalogModel.swift`. Their compact artwork and interactive previews need no model downloads. These visual models do not supply printable STL files. Repair legacy records with the internal `seed:repairCatalog` mutation using reviewed product IDs; it updates only the catalog key and skips existing media. Never reset the database to repair previews.

## Development

Requires Node 22+, pnpm, and Xcode with an iOS 18+ simulator runtime.

```sh
pnpm install
pnpm test
pnpm typecheck
xcodebuild -project Melt.xcodeproj -scheme Melt -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build ARCHS=arm64
```

Open `Melt.xcodeproj` and run the `Melt` scheme, or install `build/Build/Products/Debug-iphonesimulator/Melt.app` with `xcrun simctl`. Regenerate the project with `xcodegen generate` after changing the source layout or `project.yml`.

`Config/Melt.xcconfig` points to the development deployment `https://wry-skunk-692.convex.cloud`. The launch argument `-ConvexDeploymentURL <url>` overrides it.

Explicit offline fixtures are available with `-MeltScenario demo`, `-MeltScenario empty`, and `-MeltScenario error`. These isolate local session preferences from the connected app and simulate generation/payment only within fixture execution. The error scenario still allows interaction with the local starter. `connected` is not a fixture scenario and cannot substitute placeholder geometry. No UI tests were run for this change.

Debug builds also support `-MeltInspectModel YES`: copy a real product JSON document to the simulator app's Documents/preview-inspection.json to inspect it through the production renderer without backend writes. `-MeltInspectReduceMotion YES` sets the debug viewer's Reduce Motion environment. Add `-MeltInspectCatalog <catalogKey>` to inspect a bundled model without backend access or demo mode. This viewer is excluded from Release builds. Omit these arguments to run the normal app.

`node scripts/benchmark-generation.mjs` submits the six paid comparison requests to development, once each. It saves intent before each submission and resumes existing jobs from `build/generation-benchmark/results.json`; it never automatically repeats an ambiguous paid submission. Do not remove that file to resume. Screenshots and downloaded comparison assets are under the ignored `build/` directory.

## Backend and integration boundaries

Convex provides profiles, products, orders, friendships, challenges, and credit backing. Existing identity is a Keychain device ID; this project does not add account authentication.

- `products:createStarter` saves an owned keychain draft without invoking fal. Its optional `starterKey` is compatible with existing products.
- `products:create` requires `FAL_KEY` and accepts optional `generationQuality: "fast" | "detailed"`. Omitted quality remains Detailed for older clients. Each new product snapshots its quality and endpoint. Missing credentials return an error instead of creating a stand-in design.
- USDZ availability is committed before OBJ-to-STL preparation. The product remains `generating` until preparation finishes, preserving ordering/publishing readiness. A failed print conversion retains the preview with the existing printability warning.
- Generation exposes submitting, queued, generating and preparing-print stages plus elapsed time, without estimated percentages. Timestamps record the initial request, submission claim, observed provider start/completion, preview availability and print preparation start/finish. Provider timestamps are observations, not exact provider execution timestamps.
- Webhooks trigger a provider-verified completion check; ten-second polling is the fallback. Submission and completion claims prevent duplicate paid requests and duplicate preparation. Transient status/result fetch failures retry the existing request. Terminal results fail promptly.
- `whop:publishProduct` exports an owned ready design (or existing Friday listing) to its assigned Whop sandbox store at a price between $5 and $500. It transfers available thumbnails, creates a one-time USD variant, makes the product visible, and returns its product-page link. `products:publish` remains the legacy Friday-only endpoint.
- Owners can order their ready or published designs. Other buyers can order published designs only. Self-orders do not increase earnings, sales counts, or challenge scores and are excluded from the seller's sales list.
- `whop:createCheckout` routes to the creator's assigned sandbox account and uses the published variant when available. Draft and legacy-listing purchases use a hidden inline variant. Payment webhooks check the seller account and update orders idempotently, including a confirmed payment whose checkout response was lost. Missing store assignments or credentials return an error before inserting an order.
- Production checkout remains disabled. No production printing or shipping endpoint is connected. Customer screens show stored order states, not delivery promises. Fulfillment simulation is an internal backend helper with no customer-facing controls.

Deployment secrets: `FAL_KEY`, `WHOP_API_KEY`, `WHOP_WEBHOOK_SECRET`, and `WHOP_ENVIRONMENT=sandbox`. Keep them on the deployment, never in the app. Whop's signed `payment.succeeded` webhook is `/webhooks/whop`; fal completion is `/webhooks/fal` with polling as a fallback.

Backend checks cover generation, publishing, ownership, personal orders, self-order accounting exclusions, ordinary sales, duplicate payments, and unavailable integrations. Do not reset seeded data to verify a UI change.

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

## Whop hackathon setup

The connected flow is **sandbox payment → confirmed Friday order**, and **publish → visible Whop store product**. Printing is manual. Direct Whop-store purchases remain in Whop; Friday order tracking applies to checkouts started in Friday. Production payments are disabled.

Demo assignments are internal `whopStores` records. Nova and the existing “You” demo profiles use TCMH; Orbit uses the secondary sandbox store. New installations show their profile ID in the publishing sheet when a store has not been assigned. No OAuth or automatic store claiming is included.

From this repository, with the development deployment selected:

```sh
node scripts/whop-demo.mjs inspect
node scripts/whop-demo.mjs assign PROFILE_ID ACCOUNT_ID WHOP_WEBHOOK_STORE_A
```

The setup script is pinned to `dev:wry-skunk-692` and sandbox mode. It registers a per-store payment webhook and stores its signing secret in the named deployment environment variable. Credentials stay server-side. Existing webhook secrets are reused when assigning another profile. Different API keys can be configured through the internal `whopData:assignStore` function's `apiKeyEnv` field.

Publishing records an immutable request snapshot and external IDs in `whopListings`. Retries retain the original price/color and resume after completed steps; a thumbnail still processing at Whop leaves the product hidden until a retry succeeds. Existing Friday listings are exported only when their owner explicitly chooses Publish to Whop. Keys for Whop requests are stable across retries.

Verification completed against real sandbox APIs: a personal-draft checkout paid with Whop's documented test card, a successful payment webhook delivery, a paid/queued Friday order, and listings in two separate sandbox stores (including a generated design's thumbnail). Sandbox test cards use `4242 4242 4242 4242`, a future expiry, and any three-digit CVC. Never use a real card for this demo.
