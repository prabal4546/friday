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

    const event = JSON.parse(body);
    if (event.type === "payment.succeeded") {
      const metadata = event.data.metadata ?? {};
      await ctx.runMutation(internal.orders.markPaid, {
        whopPaymentId: event.data.id,
        orderId: typeof metadata.orderId === "string" ? metadata.orderId : undefined,
        whopCheckoutId: event.data.checkout_configuration_id ?? undefined,
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
