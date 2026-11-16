import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import { internalMutation, mutation, query, type QueryCtx } from "./_generated/server";
import { productSummary } from "./products";
import { requireProfile } from "./profiles";
import { areFriends } from "./friends";

export const DUEL_MS = 24 * 60 * 60 * 1000;

async function withProducts(ctx: QueryCtx, duel: Doc<"duels">) {
  const [a, b] = await Promise.all([ctx.db.get(duel.productAId), ctx.db.get(duel.productBId)]);
  if (a === null || b === null) throw new ConvexError("Duel references a missing product");
  return {
    ...duel,
    productA: await productSummary(ctx, a),
    productB: await productSummary(ctx, b),
  };
}

export async function liveDuelFor(ctx: QueryCtx, productId: Id<"products">) {
  const asA = await ctx.db
    .query("duels")
    .withIndex("by_productA_status", (q) => q.eq("productAId", productId).eq("status", "live"))
    .first();
  if (asA !== null) return { duel: asA, side: "a" as const };
  const asB = await ctx.db
    .query("duels")
    .withIndex("by_productB_status", (q) => q.eq("productBId", productId).eq("status", "live"))
    .first();
  return asB === null ? null : { duel: asB, side: "b" as const };
}

export const live = query({
  args: {},
  handler: async (ctx) => {
    const duels = await ctx.db
      .query("duels")
      .withIndex("by_status_endsAt", (q) => q.eq("status", "live"))
      .collect();
    return await Promise.all(duels.map((duel) => withProducts(ctx, duel)));
  },
});

export const settled = query({
  args: {},
  handler: async (ctx) => {
    const duels = await ctx.db
      .query("duels")
      .withIndex("by_status_endsAt", (q) => q.eq("status", "settled"))
      .order("desc")
      .take(20);
    return await Promise.all(duels.map((duel) => withProducts(ctx, duel)));
  },
});

export const get = query({
  args: { duelId: v.id("duels") },
  handler: async (ctx, args) => {
    const duel = await ctx.db.get(args.duelId);
    return duel === null ? null : await withProducts(ctx, duel);
  },
});

export const challenge = mutation({
  args: {
    deviceId: v.string(),
    productId: v.id("products"),
    opponentProductId: v.id("products"),
  },
  handler: async (ctx, args) => {
    const profile = await requireProfile(ctx, args.deviceId);
    const [mine, theirs] = await Promise.all([
      ctx.db.get(args.productId),
      ctx.db.get(args.opponentProductId),
    ]);
    if (mine === null || mine.creatorId !== profile._id) {
      throw new ConvexError("You can only challenge with your own product");
    }
    if (theirs === null || theirs.creatorId === profile._id) {
      throw new ConvexError("Pick a product from another creator");
    }
    if (!(await areFriends(ctx, profile._id, theirs.creatorId))) {
      throw new ConvexError("Connect with this creator before starting a duel");
    }
    if (mine.status !== "published" || theirs.status !== "published") {
      throw new ConvexError("Both products must be published");
    }
    if ((await liveDuelFor(ctx, mine._id)) !== null || (await liveDuelFor(ctx, theirs._id)) !== null) {
      throw new ConvexError("One of these products is already in a live duel");
    }
    const endsAt = Date.now() + DUEL_MS;
    const duelId = await ctx.db.insert("duels", {
      productAId: mine._id,
      productBId: theirs._id,
      endsAt,
      status: "live",
      salesA: 0,
      salesB: 0,
      poolA: 0,
      poolB: 0,
    });
    await ctx.scheduler.runAt(endsAt, internal.duels.settle, { duelId });
    return duelId;
  },
});

export const settle = internalMutation({
  args: { duelId: v.id("duels") },
  handler: async (ctx, args) => {
    const duel = await ctx.db.get(args.duelId);
    if (duel === null || duel.status !== "live") return;
    const winner = duel.salesA === duel.salesB ? "tie" : duel.salesA > duel.salesB ? "a" : "b";
    const winningPool = winner === "a" ? duel.poolA : duel.poolB;
    const losingPool = winner === "a" ? duel.poolB : duel.poolA;
    const refundAll = winner === "tie" || winningPool === 0;
    const stakes = await ctx.db
      .query("stakes")
      .withIndex("by_duel_profile", (q) => q.eq("duelId", duel._id))
      .collect();
    for (const stake of stakes) {
      const payout = refundAll
        ? stake.amount
        : stake.side === winner
          ? stake.amount + Math.floor((stake.amount * losingPool) / winningPool)
          : 0;
      await ctx.db.patch(stake._id, { payout });
      if (payout === 0) continue;
      const profile = await ctx.db.get(stake.profileId);
      if (profile === null) continue;
      await ctx.db.patch(profile._id, { credits: profile.credits + payout });
      await ctx.db.insert("transactions", {
        profileId: profile._id,
        kind: refundAll ? "refund" : "payout",
        unit: "credits",
        amount: payout,
        duelId: duel._id,
      });
    }
    if (winner !== "tie") {
      const product = await ctx.db.get(winner === "a" ? duel.productAId : duel.productBId);
      const creator = product === null ? null : await ctx.db.get(product.creatorId);
      if (creator !== null) await ctx.db.patch(creator._id, { wins: creator.wins + 1 });
    }
    await ctx.db.patch(duel._id, { status: "settled", winner });
  },
});
