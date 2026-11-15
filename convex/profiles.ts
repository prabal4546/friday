import { ConvexError, v } from "convex/values";
import { mutation, query, type QueryCtx } from "./_generated/server";

export const STARTING_CREDITS = 1250;
export const SEED_DEMO_DEVICE = "seed:you";

export async function profileByDevice(ctx: QueryCtx, deviceId: string) {
  return await ctx.db
    .query("profiles")
    .withIndex("by_deviceId", (q) => q.eq("deviceId", deviceId))
    .unique();
}

export async function requireProfile(ctx: QueryCtx, deviceId: string) {
  const profile = await profileByDevice(ctx, deviceId);
  if (profile === null) throw new ConvexError("Unknown device: call profiles:ensure first");
  return profile;
}

export const ensure = mutation({
  args: {
    deviceId: v.string(),
    displayName: v.optional(v.string()),
    claimSeed: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const existing = await profileByDevice(ctx, args.deviceId);
    if (existing !== null) return existing._id;
    if (args.claimSeed) {
      const seeded = await profileByDevice(ctx, SEED_DEMO_DEVICE);
      if (seeded !== null) {
        await ctx.db.patch(seeded._id, { deviceId: args.deviceId });
        return seeded._id;
      }
    }
    const profileId = await ctx.db.insert("profiles", {
      deviceId: args.deviceId,
      displayName: args.displayName ?? "You",
      credits: STARTING_CREDITS,
      wins: 0,
      earningsCents: 0,
    });
    await ctx.db.insert("transactions", {
      profileId,
      kind: "grant",
      unit: "credits",
      amount: STARTING_CREDITS,
    });
    return profileId;
  },
});

export const me = query({
  args: { deviceId: v.string() },
  handler: async (ctx, args) => await profileByDevice(ctx, args.deviceId),
});
