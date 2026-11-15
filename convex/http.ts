import { httpRouter } from "convex/server";
import { internal } from "./_generated/api";
import { httpAction } from "./_generated/server";
import { verifyStandardWebhook } from "./lib/standardWebhooks";

const http = httpRouter();

http.route({
  path: "/webhooks/whop",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    const secret = process.env.WHOP_WEBHOOK_SECRET;
    if (secret === undefined) {
      return new Response("WHOP_WEBHOOK_SECRET is not set on this deployment", { status: 503 });
    }
    const body = await request.text();
    const verified = await verifyStandardWebhook({
      secret,
      id: request.headers.get("webhook-id"),
      timestamp: request.headers.get("webhook-timestamp"),
      signature: request.headers.get("webhook-signature"),
      body,
      nowMs: Date.now(),
    });
    if (!verified) return new Response("Invalid webhook signature", { status: 401 });

    let event: unknown;
    try {
      event = JSON.parse(body);
    } catch {
      return new Response("Expected a JSON body", { status: 400 });
    }
    const root = typeof event === "object" && event !== null ? (event as Record<string, unknown>) : null;
    const data =
      typeof root?.data === "object" && root.data !== null ? (root.data as Record<string, unknown>) : null;
    if (root?.type === "payment.succeeded") {
      if (typeof data?.id !== "string") return new Response("Missing payment id", { status: 400 });
      const metadata =
        typeof data.metadata === "object" && data.metadata !== null
          ? (data.metadata as Record<string, unknown>)
          : {};
      await ctx.runMutation(internal.orders.markPaid, {
        whopPaymentId: data.id,
        orderId: typeof metadata.orderId === "string" ? metadata.orderId : undefined,
        whopCheckoutId:
          typeof data.checkout_configuration_id === "string" ? data.checkout_configuration_id : undefined,
      });
    }
    return new Response(null, { status: 200 });
  }),
});

http.route({
  path: "/webhooks/fal",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return new Response("Expected a JSON body", { status: 400 });
    }
    const requestId = (body as Record<string, unknown> | null)?.request_id;
    if (typeof requestId !== "string") return new Response("Missing request_id", { status: 400 });
    const product = await ctx.runQuery(internal.products.byFalRequest, { requestId });
    if (product !== null && product.status === "generating") {
      await ctx.scheduler.runAfter(0, internal.generation.poll, { productId: product._id, attempt: 1 });
    }
    return new Response(null, { status: 200 });
  }),
});

export default http;
