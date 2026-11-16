import { ConvexError, v } from "convex/values";
import type { Id } from "./_generated/dataModel";
import { mutation, query, type QueryCtx } from "./_generated/server";
import { productSummary } from "./products";
import { profileByDevice, requireProfile } from "./profiles";

function ordered(a: Id<"profiles">, b: Id<"profiles">) {
  return a < b ? ([a, b] as const) : ([b, a] as const);
}

export async function areFriends(ctx: QueryCtx, a: Id<"profiles">, b: Id<"profiles">) {
  const [profileAId, profileBId] = ordered(a, b);
  return (
    (await ctx.db
      .query("friendships")
      .withIndex("by_pair", (q) => q.eq("profileAId", profileAId).eq("profileBId", profileBId))
      .unique()) !== null
  );
}

export const connect = mutation({
  args: { deviceId: v.string(), profileId: v.id("profiles") },
  handler: async (ctx, args) => {
    const me = await requireProfile(ctx, args.deviceId);
    if (me._id === args.profileId) throw new ConvexError("You cannot connect with yourself");
    if ((await ctx.db.get(args.profileId)) === null) throw new ConvexError("That creator no longer exists");
    const [profileAId, profileBId] = ordered(me._id, args.profileId);
    const existing = await ctx.db
      .query("friendships")
      .withIndex("by_pair", (q) => q.eq("profileAId", profileAId).eq("profileBId", profileBId))
      .unique();
    if (existing !== null) return existing._id;
    return await ctx.db.insert("friendships", { profileAId, profileBId });
  },
});

export const list = query({
  args: { deviceId: v.string() },
  handler: async (ctx, args) => {
    const me = await profileByDevice(ctx, args.deviceId);
    if (me === null) return [];
    const [asA, asB] = await Promise.all([
      ctx.db
        .query("friendships")
        .withIndex("by_profileA", (q) => q.eq("profileAId", me._id))
        .take(50),
      ctx.db
        .query("friendships")
        .withIndex("by_profileB", (q) => q.eq("profileBId", me._id))
        .take(50),
    ]);
    const friendIds = [...asA.map((row) => row.profileBId), ...asB.map((row) => row.profileAId)];
    return await Promise.all(
      friendIds.map(async (profileId) => {
        const profile = await ctx.db.get(profileId);
        const products = await ctx.db
          .query("products")
          .withIndex("by_creator", (q) => q.eq("creatorId", profileId))
          .order("desc")
          .take(20);
        return {
          profileId,
          displayName: profile?.displayName ?? "Unknown",
          products: await Promise.all(
            products.filter((product) => product.status === "published").map((product) => productSummary(ctx, product)),
          ),
        };
      }),
    );
  },
});
