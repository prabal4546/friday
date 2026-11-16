import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, internalQuery, mutation, query, type QueryCtx } from "./_generated/server";
import { profileByDevice, requireProfile } from "./profiles";
import schema, { generationQuality, generationStage, starterKey } from "./schema";
import { catalogKey } from "./lib/catalog";
import { GENERATION_ENDPOINTS } from "./lib/generationConfig";

export async function productSummary(ctx: QueryCtx, product: Doc<"products">) {
  const creator = await ctx.db.get(product.creatorId);
  return {
    _id: product._id,
    name: product.name,
    prompt: product.prompt,
    status: product.status,
    printNote: product.printNote,
    filament: product.filament,
    priceCents: product.priceCents,
    thumbnailUrl: product.thumbnailUrl,
    usdzUrl: product.usdzUrl,
    starterKey: product.starterKey,
    catalogKey: product.catalogKey,
    colorCustomized: product.colorCustomized,
    generationQuality: product.generationQuality,
    generationStage: product.generationStage,
    generationRequestedAt: product.generationRequestedAt,
    generationFinishedAt: product.generationFinishedAt,
    failureReason: product.failureReason,
    salesCount: product.salesCount,
    whopListingUrl: product.whopListingUrl,
    whopPublishPriceCents: product.whopPublishPriceCents,
    creatorId: product.creatorId,
    creatorName: creator?.displayName ?? "Unknown",
  };
}

export const mine = query({
  args: { deviceId: v.string() },
  returns: v.array(schema.doc("products")),
  handler: async (ctx, args) => {
    const profile = await profileByDevice(ctx, args.deviceId);
    if (profile === null) return [];
    return await ctx.db
      .query("products")
      .withIndex("by_creator", (q) => q.eq("creatorId", profile._id))
      .order("desc")
      .take(100);
  },
});

export const storefront = query({
  args: {},
  returns: v.array(v.object({
    _id: v.id("products"), name: v.string(), prompt: v.string(), status: v.union(v.literal("generating"), v.literal("ready"), v.literal("published"), v.literal("failed")),
    printNote: v.optional(v.string()), filament: v.string(), priceCents: v.number(), thumbnailUrl: v.optional(v.string()),
    catalogKey: v.optional(catalogKey), usdzUrl: v.optional(v.string()), starterKey: v.optional(starterKey), colorCustomized: v.optional(v.boolean()), failureReason: v.optional(v.string()),
    generationQuality: v.optional(generationQuality), generationStage: v.optional(generationStage),
    generationRequestedAt: v.optional(v.number()), generationFinishedAt: v.optional(v.number()),
    whopListingUrl: v.optional(v.string()), whopPublishPriceCents: v.optional(v.number()),
    salesCount: v.number(), creatorId: v.id("profiles"), creatorName: v.string(),
  })),
  handler: async (ctx) => {
    const products = await ctx.db
      .query("products")
      .withIndex("by_status", (q) => q.eq("status", "published"))
      .order("desc")
      .take(50);
    return await Promise.all(products.map((product) => productSummary(ctx, product)));
  },
});

export const get = query({
  args: { productId: v.id("products") },
  returns: v.union(schema.doc("products"), v.null()),
  handler: async (ctx, args) => await ctx.db.get(args.productId),
});

export const publish = mutation({
  args: { deviceId: v.string(), productId: v.id("products"), priceCents: v.number() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const profile = await requireProfile(ctx, args.deviceId);
    const product = await ctx.db.get(args.productId);
    if (product === null || product.creatorId !== profile._id) {
      throw new ConvexError("Only the creator can publish this product");
    }
    if (product.whopPublishPriceCents !== undefined) throw new ConvexError("Resume publishing through Whop");
    if (product.status !== "ready") throw new ConvexError("Only a ready draft can be published");
    if (!Number.isInteger(args.priceCents) || args.priceCents < 500 || args.priceCents > 50_000) {
      throw new ConvexError("Choose a price from $5 to $500");
    }
    await ctx.db.patch(product._id, { status: "published", priceCents: args.priceCents });
  },
});

export const create = mutation({
  args: { deviceId: v.string(), prompt: v.string(), filament: v.string(), generationQuality: v.optional(generationQuality) },
  returns: v.id("products"),
  handler: async (ctx, args) => {
    const profile = await requireProfile(ctx, args.deviceId);
    const prompt = args.prompt.trim();
    if (prompt.length === 0 || prompt.length > 400) {
      throw new ConvexError("Describe your product in 1 to 400 characters");
    }
    if (!process.env.FAL_KEY) throw new ConvexError("Generation is unavailable. Please try again later.");
    const productId = await ctx.db.insert("products", {
      creatorId: profile._id,
      name: prompt.slice(0, 40),
      prompt,
      status: "generating",
      generationQuality: args.generationQuality ?? "detailed",
      generationEndpoint: GENERATION_ENDPOINTS[args.generationQuality ?? "detailed"],
      generationStage: "submitting",
      generationRequestedAt: Date.now(),
      filament: args.filament,
      priceCents: 1500,
      printability: "pending",
      salesCount: 0,
    });
    await ctx.scheduler.runAfter(0, internal.generation.start, { productId });
    return productId;
  },
});

export const finishStandIn = internalMutation({
  args: { productId: v.id("products") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const product = await ctx.db.get(args.productId);
    if (product === null || product.status !== "generating") return;
    await ctx.db.patch(product._id, { status: "ready", printability: "ok", printCostCents: 560 });
  },
});

export const setFilament = mutation({
  args: { deviceId: v.string(), productId: v.id("products"), filament: v.string(), useOriginal: v.optional(v.boolean()) },
  returns: v.null(),
  handler: async (ctx, args) => {
    const profile = await requireProfile(ctx, args.deviceId);
    const product = await ctx.db.get(args.productId);
    if (product === null || product.creatorId !== profile._id) {
      throw new ConvexError("Only the creator can change this product");
    }
    if (product.whopPublishPriceCents !== undefined) throw new ConvexError("This design is already being published to Whop");
    if (product.status !== "ready") throw new ConvexError("Only a draft can change color");
    await ctx.db.patch(product._id, { filament: args.filament, colorCustomized: args.useOriginal !== true });
  },
});

export const byFalRequest = internalQuery({
  args: { requestId: v.string() },
  returns: v.union(schema.doc("products"), v.null()),
  handler: async (ctx, args) =>
    await ctx.db
      .query("products")
      .withIndex("by_falRequestId", (q) => q.eq("falRequestId", args.requestId))
      .first(),
});

export const attachFalRequest = internalMutation({
  args: {
    productId: v.id("products"),
    falRequestId: v.string(),
    falStatusUrl: v.string(),
    falResponseUrl: v.string(),
  },
  returns: v.null(),
  handler: async (ctx, { productId, ...request }) => {
    const product = await ctx.db.get(productId);
    if (product === null || product.status !== "generating" || product.falRequestId !== undefined) return;
    await ctx.db.patch(productId, { ...request, generationStage: "queued" });
  },
});

export const finishGeneration = internalMutation({
  args: {
    productId: v.id("products"),
    usdzUrl: v.string(),
    stlUrl: v.optional(v.string()),
    thumbnailUrl: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, { productId, ...files }) => {
    const product = await ctx.db.get(productId);
    if (product === null || product.status !== "generating") return;
    await ctx.db.patch(productId, {
      ...files,
      status: "ready",
      generationStage: undefined,
      printPreparationFinishedAt: Date.now(),
      generationFinishedAt: Date.now(),
      printCostCents: 560,
      ...(files.stlUrl === undefined
        ? { printability: "warning" as const, printNote: "The print file could not be prepared from this model" }
        : { printability: "ok" as const }),
    });
  },
});

export const failGeneration = internalMutation({
  args: { productId: v.id("products"), reason: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const product = await ctx.db.get(args.productId);
    if (product === null || product.status !== "generating" || product.previewReadyAt !== undefined) return;
    await ctx.db.patch(args.productId, { status: "failed", generationStage: undefined, generationFinishedAt: Date.now(), failureReason: args.reason });
  },
});

export const createStarter = mutation({
  args: { deviceId: v.string(), filament: v.string(), starterKey: v.optional(starterKey), colorCustomized: v.optional(v.boolean()) },
  returns: v.id("products"),
  handler: async (ctx, args) => {
    const profile = await requireProfile(ctx, args.deviceId);
    const colors = ["bone", "tangerine", "matcha", "grape", "sky", "sunflower", "caramel", "lava"];
    if (!colors.includes(args.filament)) throw new ConvexError("Choose an available color");
    return await ctx.db.insert("products", {
      creatorId: profile._id,
      name: "Polka-dot man keychain",
      prompt: "A polka-dot man keychain",
      status: "ready",
      filament: args.filament,
      priceCents: 1500,
      printability: "pending",
      starterKey: args.starterKey ?? "polka-man",
      colorCustomized: args.colorCustomized ?? false,
      salesCount: 0,
    });
  },
});

// Atomically claim submission so duplicate scheduler delivery never creates another paid job.
export const claimSubmission = internalMutation({
  args: { productId: v.id("products") },
  returns: v.boolean(),
  handler: async (ctx, { productId }) => {
    const product = await ctx.db.get(productId);
    if (product === null || product.status !== "generating" || product.submittedAt !== undefined || product.falRequestId !== undefined) return false;
    await ctx.db.patch(productId, { submittedAt: Date.now(), generationStage: "submitting" });
    return true;
  },
});

export const updateGenerationStage = internalMutation({
  args: { productId: v.id("products"), stage: v.union(v.literal("queued"), v.literal("generating")) },
  returns: v.null(),
  handler: async (ctx, { productId, stage }) => {
    const product = await ctx.db.get(productId);
    if (product === null || product.status !== "generating" || product.previewReadyAt !== undefined) return;
    // Out-of-order queue responses cannot regress an active job back to queued.
    if (stage === "queued" && product.generationStage === "generating") return;
    if (product.generationStage === stage) return;
    await ctx.db.patch(productId, { generationStage: stage,
      ...(stage === "generating" && product.providerStartedAt === undefined ? { providerStartedAt: Date.now() } : {}),
    });
  },
});

// The transaction is the completion claim. Only its winner schedules print preparation.
export const attachPreview = internalMutation({
  args: { productId: v.id("products"), usdzUrl: v.string(), objUrl: v.optional(v.string()), thumbnailUrl: v.optional(v.string()) },
  returns: v.boolean(),
  handler: async (ctx, { productId, usdzUrl, objUrl, thumbnailUrl }) => {
    const product = await ctx.db.get(productId);
    if (product === null || product.status !== "generating" || product.previewReadyAt !== undefined) return false;
    const now = Date.now();
    await ctx.db.patch(productId, { usdzUrl, thumbnailUrl, providerCompletedAt: product.providerCompletedAt ?? now, previewReadyAt: now, generationStage: "preparingPrint" });
    await ctx.scheduler.runAfter(0, internal.generation.preparePrint, { productId, objUrl });
    return true;
  },
});

export const claimPrintPreparation = internalMutation({
  args: { productId: v.id("products") },
  returns: v.boolean(),
  handler: async (ctx, { productId }) => {
    const product = await ctx.db.get(productId);
    if (product === null || product.status !== "generating" || product.previewReadyAt === undefined || product.printPreparationStartedAt !== undefined) return false;
    await ctx.db.patch(productId, { printPreparationStartedAt: Date.now() });
    return true;
  },
});

// This is the time completion was observed, not a vendor-supplied inference timestamp.
export const observeProviderCompletion = internalMutation({
  args: { productId: v.id("products") }, returns: v.null(),
  handler: async (ctx, { productId }) => {
    const product = await ctx.db.get(productId);
    if (product?.status === "generating" && product.providerCompletedAt === undefined) {
      await ctx.db.patch(productId, { providerCompletedAt: Date.now() });
    }
    return null;
  },
});
