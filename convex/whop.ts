import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { action } from "./_generated/server";

const API_VERSION_DATE = "2026-11-13-1";

export const createCheckout = action({
  args: { deviceId: v.string(), productId: v.id("products") },
  handler: async (
    ctx,
    args,
  ): Promise<{ orderId: Id<"orders">; purchaseUrl: string | null; demo: boolean }> => {
    const apiKey = process.env.WHOP_API_KEY;
    if (apiKey === undefined) {
      const orderId = await ctx.runMutation(internal.orders.createDemoPaid, args);
      return { orderId, purchaseUrl: null, demo: true };
    }
    if (process.env.WHOP_ENVIRONMENT === "production") {
      throw new ConvexError("Production Whop checkout is disabled for this demo");
    }
    const baseUrl = "https://sandbox-api.whop.com/api/v1";

    const order = await ctx.runMutation(internal.orders.createPending, args);
    const response = await fetch(`${baseUrl}/checkout_configurations`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "Api-Version-Date": API_VERSION_DATE,
        "Idempotency-Key": order.orderId,
      },
      body: JSON.stringify({
        variant: {
          title: order.productName,
          billing_type: "one_time",
          initial_price: order.amountCents / 100,
          currency: "usd",
        },
        metadata: {
          productId: args.productId,
          creatorId: order.creatorId,
          orderId: order.orderId,
        },
      }),
    });
    const checkout: { id?: string; purchase_url?: string | null } = response.ok
      ? await response.json()
      : {};
    if (typeof checkout.id !== "string" || typeof checkout.purchase_url !== "string") {
      const reason = `Whop checkout request failed with status ${response.status}`;
      await ctx.runMutation(internal.orders.markFailed, { orderId: order.orderId, reason });
      throw new ConvexError(reason);
    }
    await ctx.runMutation(internal.orders.attachCheckout, {
      orderId: order.orderId,
      whopCheckoutId: checkout.id,
      purchaseUrl: checkout.purchase_url,
    });
    return { orderId: order.orderId, purchaseUrl: checkout.purchase_url, demo: false };
  },
});
