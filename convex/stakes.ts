import { ConvexError, v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { profileByDevice, requireProfile } from "./profiles";
import { side } from "./schema";

export const place = mutation({
  args: { deviceId: v.string(), duelId: v.id("duels"), side, amount: v.number() },
  handler: async (ctx, args) => {
    const profile = await requireProfile(ctx, args.deviceId);
    if (!Number.isInteger(args.amount) || args.amount <= 0) {
      throw new ConvexError("Stake must be a positive whole number of credits");
    }
    const duel = await ctx.db.get(args.duelId);
    if (duel === null || duel.status !== "live" || duel.endsAt <= Date.now()) {
      throw new ConvexError("This duel is no longer open");
    }
    const existing = await ctx.db
      .query("stakes")
      .withIndex("by_duel_profile", (q) => q.eq("duelId", duel._id).eq("profileId", profile._id))
      .unique();
    if (existing !== null) throw new ConvexError("You already backed a side in this duel");
    if (profile.credits < args.amount) throw new ConvexError("Not enough credits");

    await ctx.db.patch(profile._id, { credits: profile.credits - args.amount });
    await ctx.db.patch(
      duel._id,
      args.side === "a" ? { poolA: duel.poolA + args.amount } : { poolB: duel.poolB + args.amount },
    );
    const stakeId = await ctx.db.insert("stakes", {
      duelId: duel._id,
      profileId: profile._id,
      side: args.side,
      amount: args.amount,
    });
    await ctx.db.insert("transactions", {
      profileId: profile._id,
      kind: "stake",
      unit: "credits",
      amount: -args.amount,
      duelId: duel._id,
    });
    return stakeId;
  },
});

export const mine = query({
  args: { deviceId: v.string() },
  handler: async (ctx, args) => {
    const profile = await profileByDevice(ctx, args.deviceId);
    if (profile === null) return [];
    return await ctx.db
      .query("stakes")
      .withIndex("by_profile", (q) => q.eq("profileId", profile._id))
      .collect();
  },
});
