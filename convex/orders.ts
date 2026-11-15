import { ConvexError, v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { internalMutation, mutation, query, type MutationCtx, type QueryCtx } from "./_generated/server";
import { liveDuelFor } from "./duels";
import { profileByDevice, requireProfile } from "./profiles";

async function insertPending(ctx: MutationCtx, deviceId: string, productId: Id<"products">) {
  const buyer = await requireProfile(ctx, deviceId);
  const product = await ctx.db.get(productId);
  if (product === null || product.status !== "published") throw new ConvexError("This product is not for sale");
  if (product.creatorId === buyer._id) throw new ConvexError("You already own this design");
  const orderId = await ctx.db.insert("orders", {
    productId: product._id,
    buyerId: buyer._id,
    creatorId: product.creatorId,
    filament: product.filament,
    amountCents: product.priceCents,
    status: "pending",
    fulfillment: "none",
  });
  return { orderId, product };
}

async function applyPayment(ctx: MutationCtx, order: Doc<"orders">, whopPaymentId: string) {
  if (order.status !== "pending") return "duplicate" as const;
  const now = Date.now();
  await ctx.db.patch(order._id, {
    status: "paid",
    fulfillment: "queued",
    whopPaymentId,
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
      entry.side === "a" ? { salesA: entry.duel.salesA + 1 } : { salesB: entry.duel.salesB + 1 },
    );
  }
  return "paid" as const;
}

async function summary(ctx: QueryCtx, order: Doc<"orders">) {
  const [product, buyer, creator] = await Promise.all([
    ctx.db.get(order.productId),
    ctx.db.get(order.buyerId),
    ctx.db.get(order.creatorId),
  ]);
  return {
    _id: order._id,
    productId: order.productId,
    productName: product?.name ?? "Deleted product",
    buyerName: buyer?.displayName ?? "Unknown",
    creatorName: creator?.displayName ?? "Unknown",
    filament: order.filament,
    amountCents: order.amountCents,
    status: order.status,
    fulfillment: order.fulfillment,
    purchaseUrl: order.purchaseUrl,
    paidAt: order.paidAt,
    slantOrderId: order.slantOrderId,
    slantQuoteCents: order.slantQuoteCents,
  };
}

export const createPending = internalMutation({
  args: { deviceId: v.string(), productId: v.id("products") },
  handler: async (ctx, args) => {
    const { orderId, product } = await insertPending(ctx, args.deviceId, args.productId);
    return { orderId, creatorId: product.creatorId, productName: product.name, amountCents: product.priceCents };
  },
});

export const createDemoPaid = internalMutation({
  args: { deviceId: v.string(), productId: v.id("products") },
  handler: async (ctx, args) => {
    const { orderId } = await insertPending(ctx, args.deviceId, args.productId);
    const order = await ctx.db.get(orderId);
    if (order !== null) await applyPayment(ctx, order, `demo:${orderId}`);
    return orderId;
  },
});

export const attachCheckout = internalMutation({
  args: { orderId: v.id("orders"), whopCheckoutId: v.string(), purchaseUrl: v.string() },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.orderId, { whopCheckoutId: args.whopCheckoutId, purchaseUrl: args.purchaseUrl });
  },
});

export const markFailed = internalMutation({
  args: { orderId: v.id("orders"), reason: v.string() },
  handler: async (ctx, args) => {
    const order = await ctx.db.get(args.orderId);
    if (order !== null && order.status === "pending") {
      await ctx.db.patch(order._id, { status: "failed", failureReason: args.reason });
    }
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
    return await applyPayment(ctx, order, args.whopPaymentId);
  },
});

export const advanceFulfillment = mutation({
  args: { deviceId: v.string(), orderId: v.id("orders") },
  handler: async (ctx, args) => {
    const creator = await requireProfile(ctx, args.deviceId);
    const order = await ctx.db.get(args.orderId);
    if (order === null || order.creatorId !== creator._id) throw new ConvexError("Only the creator can fulfill this order");
    if (order.status !== "paid") throw new ConvexError("Payment has not cleared");
    if (order.fulfillment === "queued") {
      const product = await ctx.db.get(order.productId);
      const quote = (product?.printCostCents ?? 560) + 450;
      await ctx.db.patch(order._id, {
        fulfillment: "submitted",
        slantQuoteCents: quote,
        slantOrderId: `draft:${order._id}`,
      });
      return "submitted" as const;
    }
    if (order.fulfillment === "submitted") {
      await ctx.db.patch(order._id, { fulfillment: "printing" });
      return "printing" as const;
    }
    return order.fulfillment;
  },
});

export const mine = query({
  args: { deviceId: v.string() },
  handler: async (ctx, args) => {
    const profile = await profileByDevice(ctx, args.deviceId);
    if (profile === null) return [];
    const orders = await ctx.db
      .query("orders")
      .withIndex("by_buyer", (q) => q.eq("buyerId", profile._id))
      .order("desc")
      .take(50);
    return await Promise.all(orders.map((order) => summary(ctx, order)));
  },
});

export const sales = query({
  args: { deviceId: v.string() },
  handler: async (ctx, args) => {
    const profile = await profileByDevice(ctx, args.deviceId);
    if (profile === null) return [];
    const orders = await ctx.db
      .query("orders")
      .withIndex("by_creator", (q) => q.eq("creatorId", profile._id))
      .order("desc")
      .take(50);
    return await Promise.all(orders.map((order) => summary(ctx, order)));
  },
});

export const get = query({
  args: { orderId: v.id("orders") },
  handler: async (ctx, args) => await ctx.db.get(args.orderId),
});
