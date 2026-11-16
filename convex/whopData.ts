import { ConvexError, v } from "convex/values";
import { internalMutation, internalQuery, query } from "./_generated/server";
import { requireProfile } from "./profiles";
import schema from "./schema";

export const myStore = query({
  args: { deviceId: v.string() },
  returns: v.union(v.object({ name: v.string(), accountId: v.string() }), v.null()),
  handler: async (ctx, { deviceId }) => {
    const profile = await requireProfile(ctx, deviceId);
    const store = await ctx.db.query("whopStores").withIndex("by_profileId", q => q.eq("profileId", profile._id)).unique();
    return store ? { name: store.name, accountId: store.accountId } : null;
  },
});

// Operator-only setup. Credentials stay in deployment env vars, never in client records.
export const assignStore = internalMutation({
  args: { profileId: v.id("profiles"), accountId: v.string(), name: v.string(), apiKeyEnv: v.string(), webhookSecretEnv: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    if (!await ctx.db.get(args.profileId)) throw new ConvexError("Profile not found");
    if (!/^biz_[A-Za-z0-9]+$/.test(args.accountId) || !/^WHOP_[A-Z0-9_]+$/.test(args.apiKeyEnv) || !/^WHOP_[A-Z0-9_]+$/.test(args.webhookSecretEnv)) {
      throw new ConvexError("Use a Whop account ID and WHOP_ environment variable names");
    }
    const existing = await ctx.db.query("whopStores").withIndex("by_profileId", q => q.eq("profileId", args.profileId)).unique();
    if (existing && existing.accountId !== args.accountId) throw new ConvexError("A demo profile cannot switch stores after assignment");
    if (existing) await ctx.db.patch(existing._id, args);
    else await ctx.db.insert("whopStores", args);
    return null;
  },
});

export const storeForAccount = internalQuery({
  args: { accountId: v.string() }, returns: v.union(schema.doc("whopStores"), v.null()),
  handler: async (ctx, { accountId }) => await ctx.db.query("whopStores").withIndex("by_accountId", q => q.eq("accountId", accountId)).first(),
});

export const context = internalQuery({
  args: { deviceId: v.string(), productId: v.id("products"), publishing: v.boolean() },
  returns: v.object({ product: schema.doc("products"), store: schema.doc("whopStores"), listing: v.union(schema.doc("whopListings"), v.null()) }),
  handler: async (ctx, { deviceId, productId, publishing }) => {
    const profile = await requireProfile(ctx, deviceId);
    const product = await ctx.db.get(productId);
    if (!product || (publishing && product.creatorId !== profile._id)) throw new ConvexError("Only the creator can publish this product");
    if (product.status !== "published" && !(product.status === "ready" && product.creatorId === profile._id)) throw new ConvexError("This design is not available");
    const store = await ctx.db.query("whopStores").withIndex("by_profileId", q => q.eq("profileId", product.creatorId)).unique();
    if (!store) throw new ConvexError("This creator needs a demo Whop store assigned. Ask the demo organizer to set it up.");
    const listing = await ctx.db.query("whopListings").withIndex("by_productId", q => q.eq("productId", productId)).unique();
    return { product, store, listing };
  },
});

export const beginPublish = internalMutation({
  args: { deviceId: v.string(), productId: v.id("products"), priceCents: v.number(), accountId: v.string() },
  returns: schema.doc("whopListings"),
  handler: async (ctx, args) => {
    const profile = await requireProfile(ctx, args.deviceId);
    const product = await ctx.db.get(args.productId);
    if (!product || product.creatorId !== profile._id) throw new ConvexError("Only the creator can publish this product");
    if (product.status !== "ready" && product.status !== "published") throw new ConvexError("Only a ready design can be published");
    if (!Number.isInteger(args.priceCents) || args.priceCents < 500 || args.priceCents > 50_000) throw new ConvexError("Choose a price from $5 to $500");
    const existing = await ctx.db.query("whopListings").withIndex("by_productId", q => q.eq("productId", args.productId)).unique();
    if (existing) {
      if (existing.priceCents !== args.priceCents || existing.accountId !== args.accountId) throw new ConvexError("Resume publishing at the original price and store");
      return existing;
    }
    const id = await ctx.db.insert("whopListings", {
      productId: args.productId, accountId: args.accountId, name: product.name,
      description: `${product.prompt}\n\nColor: ${product.filament}. A custom 3D print from Friday.`,
      filament: product.filament, thumbnailUrl: product.thumbnailUrl, priceCents: args.priceCents,
    });
    await ctx.db.patch(product._id, { whopPublishPriceCents: args.priceCents });
    return (await ctx.db.get(id))!;
  },
});

export const saveProgress = internalMutation({
  args: { listingId: v.id("whopListings"), imageId: v.optional(v.string()), whopProductId: v.optional(v.string()), whopVariantId: v.optional(v.string()), listingUrl: v.optional(v.string()) },
  returns: v.null(),
  handler: async (ctx, { listingId, ...fields }) => {
    // Only patch supplied values: concurrent retries must never erase saved progress.
    const patch = Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== undefined));
    await ctx.db.patch(listingId, patch);
    return null;
  },
});

export const finishPublish = internalMutation({
  args: { listingId: v.id("whopListings") }, returns: v.string(),
  handler: async (ctx, { listingId }) => {
    const listing = await ctx.db.get(listingId);
    if (!listing?.whopProductId || !listing.whopVariantId || !listing.listingUrl) throw new ConvexError("Whop listing is not ready yet");
    await ctx.db.patch(listing.productId, { status: "published", priceCents: listing.priceCents, whopListingUrl: listing.listingUrl });
    return listing.listingUrl;
  },
});
