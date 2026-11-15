/// <reference types="vite/client" />
import { unwrapWebhook } from "@whop/sdk/helpers";
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { signStandardWebhook, verifyStandardWebhook } from "./lib/standardWebhooks";
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

test("checkout refuses to run without a Whop key and records a failed Whop call", async () => {
  const { t, foxVsDuck } = await seeded();
  const args = { deviceId: "phone-2", productId: foxVsDuck.productA._id };
  await expect(t.action(api.whop.createCheckout, args)).rejects.toThrow("WHOP_API_KEY");

  vi.stubEnv("WHOP_API_KEY", "test-key");
  vi.stubGlobal("fetch", vi.fn(async () => new Response("nope", { status: 401 })));
  await expect(t.action(api.whop.createCheckout, args)).rejects.toThrow("status 401");
  const orders = await t.query(api.orders.mine, { deviceId: "phone-2" });
  expect(orders.map((order) => order.status)).toEqual(["failed"]);
});
