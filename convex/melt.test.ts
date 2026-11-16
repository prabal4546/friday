/// <reference types="vite/client" />
import { unwrapWebhook } from "@whop/sdk/helpers";
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { signStandardWebhook, verifyStandardWebhook } from "./lib/standardWebhooks";
import { objToBinaryStl } from "./lib/stl";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "./**/*.js", "!./**/*.test.ts", "!./**/*.d.ts"]);
const SECRET = "ws_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

async function seeded() {
  const t = convexTest(schema, modules);
  await t.mutation(internal.seed.run, {});
  await t.mutation(api.profiles.ensure, { deviceId: "phone-1", claimSeed: true });
  await t.mutation(api.profiles.ensure, { deviceId: "phone-2", displayName: "Judge" });
  const live = await t.query(api.duels.live, {});
  const foxVsDuck = live.find((duel) => duel.productA.name === "Fox desk buddy")!;
  return { t, live, foxVsDuck };
}

async function signedRequest(body: string, secret = SECRET, timestamp = Math.floor(Date.now() / 1000)) {
  const id = "msg_test";
  return {
    method: "POST",
    headers: {
      "webhook-id": id,
      "webhook-timestamp": String(timestamp),
      "webhook-signature": "v1," + (await signStandardWebhook(secret, id, String(timestamp), body)),
    },
    body,
  };
}

test("seed is idempotent and the demo profile is claimable once", async () => {
  const { t, live } = await seeded();
  expect(await t.mutation(internal.seed.run, {})).toBe("already seeded");
  expect(live).toHaveLength(3);
  const mine = await t.query(api.products.mine, { deviceId: "phone-1" });
  expect(mine).toHaveLength(6);
  expect(await t.query(api.products.mine, { deviceId: "phone-2" })).toHaveLength(0);
});

test("a stake debits credits, grows the pool, and allows one position per duel", async () => {
  const { t, foxVsDuck } = await seeded();
  await t.mutation(api.stakes.place, { deviceId: "phone-2", duelId: foxVsDuck._id, side: "a", amount: 100 });
  expect((await t.query(api.profiles.me, { deviceId: "phone-2" }))!.credits).toBe(1150);
  expect((await t.query(api.duels.get, { duelId: foxVsDuck._id }))!.poolA).toBe(1200);
  await expect(
    t.mutation(api.stakes.place, { deviceId: "phone-2", duelId: foxVsDuck._id, side: "b", amount: 50 }),
  ).rejects.toThrow("already backed");
  await expect(
    t.mutation(api.stakes.place, { deviceId: "phone-1", duelId: foxVsDuck._id, side: "a", amount: 5000 }),
  ).rejects.toThrow("Not enough credits");
});

test("settling pays winners from the losing pool exactly once", async () => {
  const { t, foxVsDuck } = await seeded();
  await t.mutation(api.stakes.place, { deviceId: "phone-2", duelId: foxVsDuck._id, side: "b", amount: 100 });
  await t.mutation(internal.duels.settle, { duelId: foxVsDuck._id });
  await t.mutation(internal.duels.settle, { duelId: foxVsDuck._id });
  const duel = (await t.query(api.duels.get, { duelId: foxVsDuck._id }))!;
  expect(duel.status).toBe("settled");
  expect(duel.winner).toBe("b");
  expect((await t.query(api.profiles.me, { deviceId: "phone-2" }))!.credits).toBe(1150 + 100 + 55);
});

test("the Whop signer matches the official SDK verifier and rejects tampering", async () => {
  const body = JSON.stringify({ type: "payment.succeeded", data: { id: "pay_1" } });
  const request = await signedRequest(body);
  expect(unwrapWebhook<{ type: string }>(body, { headers: request.headers, key: SECRET }).type).toBe(
    "payment.succeeded",
  );
  const check = (overrides: Partial<Parameters<typeof verifyStandardWebhook>[0]>) =>
    verifyStandardWebhook({
      secret: SECRET,
      id: request.headers["webhook-id"],
      timestamp: request.headers["webhook-timestamp"],
      signature: request.headers["webhook-signature"],
      body,
      nowMs: Date.now(),
      ...overrides,
    });
  expect(await check({})).toBe(true);
  expect(await check({ body: body.replace("pay_1", "pay_2") })).toBe(false);
  expect(await check({ secret: "ws_wrong" })).toBe(false);
  expect(await check({ nowMs: Date.now() + 6 * 60 * 1000 })).toBe(false);
  expect(await check({ signature: null })).toBe(false);
});

test("checkout carries productId, creatorId, and orderId, and a signed payment is applied once", async () => {
  const { t, foxVsDuck } = await seeded();
  vi.stubEnv("WHOP_API_KEY", "test-key");
  vi.stubEnv("WHOP_WEBHOOK_SECRET", SECRET);
  const fetchMock = vi.fn(async () =>
    Response.json({ id: "ch_test", purchase_url: "https://sandbox.whop.com/checkout/ch_test" }),
  );
  vi.stubGlobal("fetch", fetchMock);

  const fox = foxVsDuck.productA;
  const checkout = await t.action(api.whop.createCheckout, { deviceId: "phone-2", productId: fox._id });
  expect(checkout.purchaseUrl).toBe("https://sandbox.whop.com/checkout/ch_test");
  const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
  expect(url).toBe("https://sandbox-api.whop.com/api/v1/checkout_configurations");
  expect(new Headers(init.headers).get("Idempotency-Key")).toBe(checkout.orderId);
  const sent = JSON.parse(init.body as string);
  expect(sent.metadata).toEqual({ productId: fox._id, creatorId: fox.creatorId, orderId: checkout.orderId });
  expect(sent.variant).toMatchObject({ billing_type: "one_time", initial_price: 15, currency: "usd" });

  const body = JSON.stringify({
    type: "payment.succeeded",
    data: { id: "pay_test", checkout_configuration_id: "ch_test", metadata: sent.metadata },
  });
  expect((await t.fetch("/webhooks/whop", await signedRequest(body, "ws_wrong"))).status).toBe(401);
  expect((await t.query(api.orders.get, { orderId: checkout.orderId }))!.status).toBe("pending");

  expect((await t.fetch("/webhooks/whop", await signedRequest(body))).status).toBe(200);
  expect((await t.fetch("/webhooks/whop", await signedRequest(body))).status).toBe(200);

  const order = (await t.query(api.orders.get, { orderId: checkout.orderId }))!;
  expect(order).toMatchObject({ status: "paid", fulfillment: "queued", whopPaymentId: "pay_test" });
  const duel = (await t.query(api.duels.get, { duelId: foxVsDuck._id }))!;
  expect(duel.salesA).toBe(foxVsDuck.salesA + 1);
  expect(duel.productA.salesCount).toBe(fox.salesCount + 1);
});

test("production Whop checkout remains disabled", async () => {
  const { t, foxVsDuck } = await seeded();
  vi.stubEnv("WHOP_API_KEY", "test-key");
  vi.stubEnv("WHOP_ENVIRONMENT", "production");
  const fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);

  await expect(
    t.action(api.whop.createCheckout, { deviceId: "phone-2", productId: foxVsDuck.productA._id }),
  ).rejects.toThrow("Production Whop checkout is disabled");
  expect(fetchMock).not.toHaveBeenCalled();
  expect(await t.query(api.orders.mine, { deviceId: "phone-2" })).toEqual([]);
});

test("publish, demo checkout, creator earnings, and draft fulfillment work without external keys", async () => {
  const { t, foxVsDuck } = await seeded();
  const rocket = (await t.query(api.products.mine, { deviceId: "phone-1" })).find(
    (product) => product.name === "Rocket pen cup",
  )!;
  await t.mutation(api.products.publish, { deviceId: "phone-1", productId: rocket._id, priceCents: 2000 });
  expect((await t.query(api.products.storefront, {})).some((product) => product._id === rocket._id)).toBe(true);

  const buyerProductId = await t.mutation(api.products.create, {
    deviceId: "phone-2",
    prompt: "A judge's tiny trophy",
    filament: "sunflower",
  });
  await t.mutation(internal.products.finishStandIn, { productId: buyerProductId });
  await t.mutation(api.products.publish, { deviceId: "phone-2", productId: buyerProductId, priceCents: 1200 });
  const buyer = (await t.query(api.profiles.me, { deviceId: "phone-2" }))!;
  await t.mutation(api.friends.connect, { deviceId: "phone-1", profileId: buyer._id });
  const buyerFriend = (await t.query(api.friends.list, { deviceId: "phone-1" })).find(
    (friend) => friend.profileId === buyer._id,
  )!;
  expect(buyerFriend.products[0]._id).toBe(buyerProductId);
  const duelId = await t.mutation(api.duels.challenge, {
    deviceId: "phone-1",
    productId: rocket._id,
    opponentProductId: buyerProductId,
  });
  await t.mutation(api.stakes.place, { deviceId: "phone-2", duelId, side: "b", amount: 100 });

  const checkout = await t.action(api.whop.createCheckout, { deviceId: "phone-2", productId: rocket._id });
  expect(checkout).toMatchObject({ demo: true, purchaseUrl: null });
  expect((await t.query(api.orders.mine, { deviceId: "phone-2" }))[0]).toMatchObject({
    productName: "Rocket pen cup",
    status: "paid",
    fulfillment: "queued",
  });
  expect((await t.query(api.profiles.me, { deviceId: "phone-1" }))!.earningsCents).toBe(59950 + 1480);
  expect((await t.query(api.duels.get, { duelId }))!.salesA).toBe(1);

  expect(
    await t.mutation(api.orders.advanceFulfillment, { deviceId: "phone-1", orderId: checkout.orderId }),
  ).toBe("submitted");
  let sale = (await t.query(api.orders.sales, { deviceId: "phone-1" }))[0];
  expect(sale).toMatchObject({ fulfillment: "submitted", slantQuoteCents: 970 });
  expect(sale.slantOrderId).toMatch(/^draft:/);
  expect(
    await t.mutation(api.orders.advanceFulfillment, { deviceId: "phone-1", orderId: checkout.orderId }),
  ).toBe("printing");
  sale = (await t.query(api.orders.sales, { deviceId: "phone-1" }))[0];
  expect(sale.fulfillment).toBe("printing");

  vi.stubEnv("WHOP_API_KEY", "test-key");
  vi.stubGlobal("fetch", vi.fn(async () => new Response("nope", { status: 401 })));
  await expect(
    t.action(api.whop.createCheckout, { deviceId: "phone-2", productId: foxVsDuck.productA._id }),
  ).rejects.toThrow("status 401");
  const orders = await t.query(api.orders.mine, { deviceId: "phone-2" });
  expect(orders.map((order) => order.status).sort()).toEqual(["failed", "paid"]);
});

test("a new design starts generating and the stand-in turns it into a draft", async () => {
  vi.useFakeTimers();
  const { t } = await seeded();
  const args = { deviceId: "phone-2", prompt: "  A tiny rocket for my desk  ", filament: "lava" };
  const productId = await t.mutation(api.products.create, args);
  expect((await t.query(api.products.get, { productId }))!).toMatchObject({
    status: "generating",
    name: "A tiny rocket for my desk",
  });
  vi.advanceTimersByTime(3001);
  await t.finishInProgressScheduledFunctions();
  expect((await t.query(api.products.get, { productId }))!.status).toBe("ready");
  await expect(t.mutation(api.products.create, { ...args, prompt: "   " })).rejects.toThrow("1 to 400");
});

test("reset rebuilds the demo world so the seeded profile can be claimed again", async () => {
  const { t, foxVsDuck } = await seeded();
  await t.mutation(api.stakes.place, { deviceId: "phone-1", duelId: foxVsDuck._id, side: "a", amount: 100 });
  expect(await t.mutation(internal.seed.reset, {})).toBe("reset");
  expect(await t.query(api.profiles.me, { deviceId: "phone-1" })).toBeNull();
  expect(await t.query(api.duels.live, {})).toHaveLength(3);
  await t.mutation(api.profiles.ensure, { deviceId: "phone-3", claimSeed: true });
  expect(await t.query(api.products.mine, { deviceId: "phone-3" })).toHaveLength(6);
  expect((await t.query(api.profiles.me, { deviceId: "phone-3" }))!.credits).toBe(1250);
});

const SQUARE_OBJ = "v 0 0 0\nv 2 0 0\nv 2 4 0\nv 0 4 0\nf 1/1/1 2/2/1 3/3/1 4/4/1\n";

test("an OBJ becomes a binary STL that stands upright and is 80 mm at its longest", () => {
  const stl = new DataView(objToBinaryStl(SQUARE_OBJ));
  expect(stl.byteLength).toBe(84 + 2 * 50);
  expect(stl.getUint32(80, true)).toBe(2);
  const heights = [0, 1, 2].map((corner) => stl.getFloat32(84 + 12 + corner * 12 + 8, true));
  expect(Math.max(...heights)).toBeCloseTo(80);
  expect(() => objToBinaryStl("v 0 0 0\n")).toThrow("no usable faces");
});

test("with a fal key a design is queued, finished from the polled result, and keeps an STL", async () => {
  vi.useFakeTimers();
  const { t } = await seeded();
  vi.stubEnv("FAL_KEY", "test-key");
  const queue = "https://queue.fal.run/fal-ai/meshy/requests/req_1";
  const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
    if (init?.method === "POST") {
      return Response.json({ request_id: "req_1", status_url: queue + "/status", response_url: queue });
    }
    if (url === queue + "/status") return Response.json({ status: "COMPLETED" });
    if (url === queue) {
      return Response.json({
        model_urls: {
          usdz: { url: "https://v3b.fal.media/files/model.usdz" },
          obj: { url: "https://v3b.fal.media/files/model.obj" },
        },
        thumbnail: { url: "https://v3b.fal.media/files/preview.png" },
      });
    }
    return new Response(SQUARE_OBJ);
  });
  vi.stubGlobal("fetch", fetchMock);

  const productId = await t.mutation(api.products.create, {
    deviceId: "phone-2",
    prompt: "A fox that holds my earbuds",
    filament: "tangerine",
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const [submitUrl, submit] = fetchMock.mock.calls[0] as [string, RequestInit];
  expect(submitUrl).toContain("https://queue.fal.run/fal-ai/meshy/v7.1/text-to-3d?fal_webhook=");
  expect(JSON.parse(submit.body as string)).toMatchObject({ prompt: "A fox that holds my earbuds", mode: "preview" });
  const product = (await t.query(api.products.get, { productId }))!;
  expect(product).toMatchObject({
    status: "ready",
    printability: "ok",
    falRequestId: "req_1",
    usdzUrl: "https://v3b.fal.media/files/model.usdz",
    thumbnailUrl: "https://v3b.fal.media/files/preview.png",
  });
  expect(product.stlUrl).toBeTypeOf("string");

  const hook = (body: string) => t.fetch("/webhooks/fal", { method: "POST", body });
  expect((await hook(JSON.stringify({ request_id: "req_1" }))).status).toBe(200);
  expect((await hook(JSON.stringify({ request_id: "unknown" }))).status).toBe(200);
  expect((await hook("not json")).status).toBe(400);
});

test("a refused fal request marks the design failed", async () => {
  vi.useFakeTimers();
  const { t } = await seeded();
  vi.stubEnv("FAL_KEY", "test-key");
  vi.stubGlobal("fetch", vi.fn(async () => new Response("nope", { status: 401 })));
  const productId = await t.mutation(api.products.create, { deviceId: "phone-2", prompt: "A fox", filament: "sky" });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  expect((await t.query(api.products.get, { productId }))!).toMatchObject({
    status: "failed",
    failureReason: "The model service refused the request (status 401)",
  });
});
