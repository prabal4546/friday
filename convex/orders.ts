import { ConvexError, v } from "convex/values";
import { internalMutation, query } from "./_generated/server";
import { liveDuelFor } from "./duels";
import { profileByDevice, requireProfile } from "./profiles";

export const createPending = internalMutation({
  args: { deviceId: v.string(), productId: v.id("products") },
  handler: async (ctx, args) => {
    const buyer = await requireProfile(ctx, args.deviceId);
    const product = await ctx.db.get(args.productId);
    if (product === null || product.status !== "published") {
      throw new ConvexError("This product is not for sale");
    }
    const orderId = await ctx.db.insert("orders", {
      productId: product._id,
      buyerId: buyer._id,
      creatorId: product.creatorId,
      filament: product.filament,
      amountCents: product.priceCents,
      status: "pending",
      fulfillment: "none",
    });
    return {
      orderId,
      creatorId: product.creatorId,
      productName: product.name,
      amountCents: product.priceCents,
    };
  },
});

export const attachCheckout = internalMutation({
  args: { orderId: v.id("orders"), whopCheckoutId: v.string(), purchaseUrl: v.string() },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.orderId, {
      whopCheckoutId: args.whopCheckoutId,
      purchaseUrl: args.purchaseUrl,
    });
  },
});

export const markFailed = internalMutation({
  args: { orderId: v.id("orders"), reason: v.string() },
  handler: async (ctx, args) => {
    const order = await ctx.db.get(args.orderId);
    if (order === null || order.status !== "pending") return;
    await ctx.db.patch(order._id, { status: "failed", failureReason: args.reason });
  },
});

export const markPaid = internalMutation({
  args: {
    whopPaymentId: v.string(),
    orderId: v.optional(v.string()),
    whopCheckoutId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const seen = await ctx.db
      .query("orders")
      .withIndex("by_whopPaymentId", (q) => q.eq("whopPaymentId", args.whopPaymentId))
      .first();
    if (seen !== null) return "duplicate" as const;

    const orderId = args.orderId === undefined ? null : ctx.db.normalizeId("orders", args.orderId);
    let order = orderId === null ? null : await ctx.db.get(orderId);
    if (order === null && args.whopCheckoutId !== undefined) {
      order = await ctx.db
        .query("orders")
        .withIndex("by_whopCheckoutId", (q) => q.eq("whopCheckoutId", args.whopCheckoutId))
        .first();
    }
    if (order === null) return "unknown_order" as const;
    if (order.status !== "pending") return "duplicate" as const;

    const now = Date.now();
    await ctx.db.patch(order._id, {
      status: "paid",
      fulfillment: "queued",
      whopPaymentId: args.whopPaymentId,
      paidAt: now,
    });
    const product = await ctx.db.get(order.productId);
    if (product !== null) await ctx.db.patch(product._id, { salesCount: product.salesCount + 1 });

    const earned = order.amountCents - (product?.printCostCents ?? 0);
    const creator = await ctx.db.get(order.creatorId);
    if (creator !== null) {
      await ctx.db.patch(creator._id, { earningsCents: creator.earningsCents + earned });
      await ctx.db.insert("transactions", {
        profileId: creator._id,
        kind: "sale",
        unit: "cents",
        amount: earned,
        orderId: order._id,
      });
    }

    const entry = await liveDuelFor(ctx, order.productId);
    if (entry !== null && entry.duel.endsAt > now) {
      await ctx.db.patch(
        entry.duel._id,
        entry.side === "a"
          ? { salesA: entry.duel.salesA + 1 }
          : { salesB: entry.duel.salesB + 1 },
      );
    }
    return "paid" as const;
  },
});

export const mine = query({
  args: { deviceId: v.string() },
  handler: async (ctx, args) => {
    const profile = await profileByDevice(ctx, args.deviceId);
    if (profile === null) return [];
    return await ctx.db
      .query("orders")
      .withIndex("by_buyer", (q) => q.eq("buyerId", profile._id))
      .order("desc")
      .collect();
  },
});

export const get = query({
  args: { orderId: v.id("orders") },
  handler: async (ctx, args) => await ctx.db.get(args.orderId),
});
