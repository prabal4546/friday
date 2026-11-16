import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { action } from "./_generated/server";
import { requiredString, sandboxKey, sandboxUrl, uploadThumbnail, whopRequest } from "./lib/whopApi";

export const publishProduct = action({
  args: { deviceId: v.string(), productId: v.id("products"), priceCents: v.number() },
  returns: v.object({ listingUrl: v.string() }),
  handler: async (ctx, args): Promise<{ listingUrl: string }> => {
    const { store } = await ctx.runQuery(internal.whopData.context, { deviceId: args.deviceId, productId: args.productId, publishing: true });
    const key = sandboxKey(store.apiKeyEnv);
    const listing = await ctx.runMutation(internal.whopData.beginPublish, { ...args, accountId: store.accountId });
    let imageId = listing.imageId;
    if (listing.thumbnailUrl && !imageId) {
      imageId = await uploadThumbnail(key, listing.thumbnailUrl, listing._id);
      await ctx.runMutation(internal.whopData.saveProgress, { listingId: listing._id, imageId });
    }
    let productId = listing.whopProductId;
    if (!productId) {
      const product = await whopRequest(key, "products", {
        account_id: listing.accountId, title: listing.name.slice(0, 80), description: listing.description,
        visibility: "hidden", collect_shipping_address: true, custom_cta: "order_now", send_welcome_message: false,
        metadata: { meltProductId: args.productId },
      }, `melt-product-v2-${listing._id}`);
      productId = requiredString(product.id, "product ID");
      await ctx.runMutation(internal.whopData.saveProgress, { listingId: listing._id, whopProductId: productId });
    }
    if (!listing.whopVariantId) {
      const variant = await whopRequest(key, "variants", {
        account_id: listing.accountId, product_id: productId, title: `${listing.filament} print`.slice(0, 30),
        billing_type: "one_time", initial_price: listing.priceCents / 100, currency: "usd", visibility: "visible",
        unlimited_stock: true, release_method: "buy_now",
      }, `melt-variant-${listing._id}`);
      const variantId = requiredString(variant.id, "variant ID");
      await ctx.runMutation(internal.whopData.saveProgress, { listingId: listing._id, whopVariantId: variantId });
    }
    if (imageId) {
      const image = await whopRequest(key, `files/${imageId}`);
      if (image.upload_status !== "ready") throw new ConvexError("Whop is still processing the thumbnail. Please retry publishing in a moment.");
    }
    // Store visibility is separate from Whop's App Store review/publish endpoint.
    const product = await whopRequest(key, `products/${productId}`, { visibility: "visible", ...(imageId ? { gallery_images: [{ id: imageId }] } : {}) }, `melt-visible-${listing._id}-${imageId ?? "no-image"}`, "PATCH");
    const route = requiredString(product.route, "product route");
    const account = await whopRequest(key, `accounts/${listing.accountId}`);
    const storeRoute = requiredString(account.route, "store route");
    const listingUrl = sandboxUrl(`https://sandbox.whop.com/${encodeURIComponent(storeRoute)}/products/${encodeURIComponent(route)}/`);
    await ctx.runMutation(internal.whopData.saveProgress, { listingId: listing._id, listingUrl });
    return { listingUrl: await ctx.runMutation(internal.whopData.finishPublish, { listingId: listing._id }) };
  },
});

export const createCheckout = action({
  args: { deviceId: v.string(), productId: v.id("products") },
  returns: v.object({ orderId: v.id("orders"), purchaseUrl: v.union(v.string(), v.null()), demo: v.boolean() }),
  handler: async (ctx, args): Promise<{ orderId: Id<"orders">; purchaseUrl: string | null; demo: boolean }> => {
    if (process.env.WHOP_ENVIRONMENT !== "sandbox") throw new ConvexError("Checkout is unavailable. Whop sandbox mode must be configured.");
    const { store, product, listing } = await ctx.runQuery(internal.whopData.context, { ...args, publishing: false });
    const key = sandboxKey(store.apiKeyEnv);
    const order = await ctx.runMutation(internal.orders.createPending, { ...args, whopAccountId: store.accountId });
    try {
      const checkout = await whopRequest(key, "checkout_configurations", {
        account_id: store.accountId,
        ...(product.whopListingUrl && listing?.whopVariantId
          ? { variant_id: listing.whopVariantId }
          : { variant: { title: order.productName.slice(0, 30), billing_type: "one_time", initial_price: order.amountCents / 100, currency: "usd", visibility: "hidden" } }),
        metadata: { productId: args.productId, creatorId: order.creatorId, orderId: order.orderId },
      }, order.orderId);
      const checkoutId = requiredString(checkout.id, "checkout ID");
      const purchaseUrl = sandboxUrl(checkout.purchase_url);
      await ctx.runMutation(internal.orders.attachCheckout, { orderId: order.orderId, whopCheckoutId: checkoutId, purchaseUrl });
      return { orderId: order.orderId, purchaseUrl, demo: false };
    } catch (error) {
      const reason = error instanceof Error ? error.message : "Whop checkout failed. Please retry.";
      await ctx.runMutation(internal.orders.markFailed, { orderId: order.orderId, reason });
      throw error;
    }
  },
});
