import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, internalQuery, mutation, query, type QueryCtx } from "./_generated/server";
import { profileByDevice, requireProfile } from "./profiles";

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
    salesCount: product.salesCount,
    creatorId: product.creatorId,
    creatorName: creator?.displayName ?? "Unknown",
  };
}

export const mine = query({
  args: { deviceId: v.string() },
  handler: async (ctx, args) => {
    const profile = await profileByDevice(ctx, args.deviceId);
    if (profile === null) return [];
    return await ctx.db
      .query("products")
      .withIndex("by_creator", (q) => q.eq("creatorId", profile._id))
      .order("desc")
      .collect();
  },
});

export const storefront = query({
  args: {},
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
  handler: async (ctx, args) => await ctx.db.get(args.productId),
});

export const publish = mutation({
  args: { deviceId: v.string(), productId: v.id("products"), priceCents: v.number() },
  handler: async (ctx, args) => {
    const profile = await requireProfile(ctx, args.deviceId);
    const product = await ctx.db.get(args.productId);
    if (product === null || product.creatorId !== profile._id) {
      throw new ConvexError("Only the creator can publish this product");
    }
    if (product.status !== "ready") throw new ConvexError("Only a ready draft can be published");
    if (!Number.isInteger(args.priceCents) || args.priceCents < 500 || args.priceCents > 50_000) {
      throw new ConvexError("Choose a price from $5 to $500");
    }
    await ctx.db.patch(product._id, { status: "published", priceCents: args.priceCents });
  },
});

export const create = mutation({
  args: { deviceId: v.string(), prompt: v.string(), filament: v.string() },
  handler: async (ctx, args) => {
    const profile = await requireProfile(ctx, args.deviceId);
    const prompt = args.prompt.trim();
    if (prompt.length === 0 || prompt.length > 400) {
      throw new ConvexError("Describe your product in 1 to 400 characters");
    }
    const productId = await ctx.db.insert("products", {
      creatorId: profile._id,
      name: prompt.slice(0, 40),
      prompt,
      status: "generating",
      filament: args.filament,
      priceCents: 1500,
      printability: "pending",
      salesCount: 0,
    });
    if (process.env.FAL_KEY === undefined) {
      await ctx.scheduler.runAfter(3000, internal.products.finishStandIn, { productId });
    } else {
      await ctx.scheduler.runAfter(0, internal.generation.start, { productId });
    }
    return productId;
  },
});

export const finishStandIn = internalMutation({
  args: { productId: v.id("products") },
  handler: async (ctx, args) => {
    const product = await ctx.db.get(args.productId);
    if (product === null || product.status !== "generating") return;
    await ctx.db.patch(product._id, { status: "ready", printability: "ok", printCostCents: 560 });
  },
});

export const setFilament = mutation({
  args: { deviceId: v.string(), productId: v.id("products"), filament: v.string() },
  handler: async (ctx, args) => {
    const profile = await requireProfile(ctx, args.deviceId);
    const product = await ctx.db.get(args.productId);
    if (product === null || product.creatorId !== profile._id) {
      throw new ConvexError("Only the creator can change this product");
    }
    if (product.status !== "ready") throw new ConvexError("Only a draft can change color");
    await ctx.db.patch(product._id, { filament: args.filament });
  },
});

export const byFalRequest = internalQuery({
  args: { requestId: v.string() },
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
  handler: async (ctx, { productId, ...request }) => {
    await ctx.db.patch(productId, request);
  },
});

export const finishGeneration = internalMutation({
  args: {
    productId: v.id("products"),
    usdzUrl: v.string(),
    stlUrl: v.optional(v.string()),
    thumbnailUrl: v.optional(v.string()),
  },
  handler: async (ctx, { productId, ...files }) => {
    const product = await ctx.db.get(productId);
    if (product === null || product.status !== "generating") return;
    await ctx.db.patch(productId, {
      ...files,
      status: "ready",
      printCostCents: 560,
      ...(files.stlUrl === undefined
        ? { printability: "warning" as const, printNote: "The print file could not be prepared from this model" }
        : { printability: "ok" as const }),
    });
  },
});

export const failGeneration = internalMutation({
  args: { productId: v.id("products"), reason: v.string() },
  handler: async (ctx, args) => {
    const product = await ctx.db.get(args.productId);
    if (product === null || product.status !== "generating") return;
    await ctx.db.patch(args.productId, { status: "failed", failureReason: args.reason });
  },
});
