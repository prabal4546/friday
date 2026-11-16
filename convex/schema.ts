import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { catalogKey } from "./lib/catalog";

export const starterKey = v.union(v.literal("polka-man"), v.literal("friday-home"));

export const generationQuality = v.union(v.literal("fast"), v.literal("detailed"));
export const generationStage = v.union(v.literal("submitting"), v.literal("queued"), v.literal("generating"), v.literal("preparingPrint"));

export const side = v.union(v.literal("a"), v.literal("b"));

export default defineSchema({
  whopStores: defineTable({
    profileId: v.id("profiles"),
    accountId: v.string(),
    name: v.string(),
    apiKeyEnv: v.string(),
    webhookSecretEnv: v.string(),
  }).index("by_profileId", ["profileId"]).index("by_accountId", ["accountId"]),

  // Immutable request snapshot and resumable external IDs. Never returned to clients.
  whopListings: defineTable({
    productId: v.id("products"),
    accountId: v.string(),
    name: v.string(),
    description: v.string(),
    filament: v.string(),
    thumbnailUrl: v.optional(v.string()),
    priceCents: v.number(),
    imageId: v.optional(v.string()),
    whopProductId: v.optional(v.string()),
    whopVariantId: v.optional(v.string()),
    listingUrl: v.optional(v.string()),
  }).index("by_productId", ["productId"]),

  profiles: defineTable({
    deviceId: v.string(),
    displayName: v.string(),
    credits: v.number(),
    wins: v.number(),
    earningsCents: v.number(),
  }).index("by_deviceId", ["deviceId"]),

  friendships: defineTable({
    profileAId: v.id("profiles"),
    profileBId: v.id("profiles"),
  })
    .index("by_pair", ["profileAId", "profileBId"])
    .index("by_profileA", ["profileAId"])
    .index("by_profileB", ["profileBId"]),

  products: defineTable({
    creatorId: v.id("profiles"),
    name: v.string(),
    prompt: v.string(),
    status: v.union(
      v.literal("generating"),
      v.literal("ready"),
      v.literal("published"),
      v.literal("failed"),
    ),
    filament: v.string(),
    priceCents: v.number(),
    printCostCents: v.optional(v.number()),
    printability: v.union(v.literal("pending"), v.literal("ok"), v.literal("warning")),
    printNote: v.optional(v.string()),
    thumbnailUrl: v.optional(v.string()),
    usdzUrl: v.optional(v.string()),
    starterKey: v.optional(starterKey),
    catalogKey: v.optional(catalogKey),
    colorCustomized: v.optional(v.boolean()),
    stlUrl: v.optional(v.string()),
    generationQuality: v.optional(generationQuality),
    generationEndpoint: v.optional(v.string()),
    generationStage: v.optional(generationStage),
    generationRequestedAt: v.optional(v.number()),
    submittedAt: v.optional(v.number()),
    providerStartedAt: v.optional(v.number()),
    providerCompletedAt: v.optional(v.number()),
    previewReadyAt: v.optional(v.number()),
    printPreparationStartedAt: v.optional(v.number()),
    printPreparationFinishedAt: v.optional(v.number()),
    generationFinishedAt: v.optional(v.number()),
    falRequestId: v.optional(v.string()),
    falStatusUrl: v.optional(v.string()),
    falResponseUrl: v.optional(v.string()),
    failureReason: v.optional(v.string()),
    salesCount: v.number(),
    whopListingUrl: v.optional(v.string()),
    whopPublishPriceCents: v.optional(v.number()),
  })
    .index("by_creator", ["creatorId"])
    .index("by_status", ["status"])
    .index("by_falRequestId", ["falRequestId"]),

  duels: defineTable({
    productAId: v.id("products"),
    productBId: v.id("products"),
    theme: v.optional(v.string()),
    endsAt: v.number(),
    status: v.union(v.literal("live"), v.literal("settled")),
    salesA: v.number(),
    salesB: v.number(),
    poolA: v.number(),
    poolB: v.number(),
    winner: v.optional(v.union(side, v.literal("tie"))),
  })
    .index("by_status_endsAt", ["status", "endsAt"])
    .index("by_productA_status", ["productAId", "status"])
    .index("by_productB_status", ["productBId", "status"]),

  stakes: defineTable({
    duelId: v.id("duels"),
    profileId: v.id("profiles"),
    side,
    amount: v.number(),
    payout: v.optional(v.number()),
  })
    .index("by_duel_profile", ["duelId", "profileId"])
    .index("by_profile", ["profileId"]),

  orders: defineTable({
    productId: v.id("products"),
    buyerId: v.id("profiles"),
    creatorId: v.id("profiles"),
    filament: v.string(),
    amountCents: v.number(),
    status: v.union(v.literal("pending"), v.literal("paid"), v.literal("failed")),
    fulfillment: v.union(
      v.literal("none"),
      v.literal("queued"),
      v.literal("submitted"),
      v.literal("printing"),
    ),
    whopCheckoutId: v.optional(v.string()),
    whopAccountId: v.optional(v.string()),
    purchaseUrl: v.optional(v.string()),
    whopPaymentId: v.optional(v.string()),
    paidAt: v.optional(v.number()),
    failureReason: v.optional(v.string()),
    slantOrderId: v.optional(v.string()),
    slantQuoteCents: v.optional(v.number()),
  })
    .index("by_buyer", ["buyerId"])
    .index("by_creator", ["creatorId"])
    .index("by_whopCheckoutId", ["whopCheckoutId"])
    .index("by_whopPaymentId", ["whopPaymentId"]),

  transactions: defineTable({
    profileId: v.id("profiles"),
    kind: v.union(
      v.literal("grant"),
      v.literal("stake"),
      v.literal("payout"),
      v.literal("refund"),
      v.literal("sale"),
    ),
    unit: v.union(v.literal("credits"), v.literal("cents")),
    amount: v.number(),
    duelId: v.optional(v.id("duels")),
    orderId: v.optional(v.id("orders")),
  }).index("by_profile", ["profileId"]),
});
