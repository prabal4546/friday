import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, mutation, query, type QueryCtx } from "./_generated/server";
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

export const get = query({
  args: { productId: v.id("products") },
  handler: async (ctx, args) => await ctx.db.get(args.productId),
});

export const publish = mutation({
  args: { deviceId: v.string(), productId: v.id("products") },
  handler: async (ctx, args) => {
    const profile = await requireProfile(ctx, args.deviceId);
    const product = await ctx.db.get(args.productId);
    if (product === null || product.creatorId !== profile._id) {
      throw new ConvexError("Only the creator can publish this product");
    }
    if (product.status !== "ready") throw new ConvexError("Only a ready draft can be published");
    await ctx.db.patch(product._id, { status: "published" });
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
    await ctx.scheduler.runAfter(3000, internal.products.finishStandIn, { productId });
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
