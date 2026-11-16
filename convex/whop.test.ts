/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "./**/*.js", "!./**/*.test.ts", "!./**/*.d.ts"]);
afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });
async function setup() {
  vi.stubEnv("WHOP_ENVIRONMENT", "sandbox");
  vi.stubEnv("WHOP_STORE_A", "key-a"); vi.stubEnv("WHOP_STORE_B", "key-b");
  const t = convexTest(schema, modules);
  const a = await t.mutation(api.profiles.ensure, { deviceId: "a" });
  const b = await t.mutation(api.profiles.ensure, { deviceId: "b" });
  for (const [profileId, suffix] of [[a, "A"], [b, "B"]] as const) {
    await t.mutation(internal.whopData.assignStore, { profileId, accountId: `biz_${suffix}`, name: `Store ${suffix}`, apiKeyEnv: `WHOP_STORE_${suffix}`, webhookSecretEnv: `WHOP_WEBHOOK_${suffix}` });
  }
  const productId = await t.mutation(api.products.createStarter, { deviceId: "a", filament: "sky" });
  return { t, productId, a, b };
}
function provider() {
  const calls: { path: string; body: Record<string, unknown>; key: string | null; idem: string | null }[] = [];
  const fetchMock = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
    const path = String(url).split("/api/v1/")[1];
    const body = JSON.parse(String(init?.body ?? "{}"));
    const headers = new Headers(init?.headers);
    calls.push({ path, body, key: headers.get("Authorization"), idem: headers.get("Idempotency-Key") });
    if (path?.startsWith("accounts/")) return Response.json({ route: "demo-store" });
    if (path === "products") return Response.json({ id: `prod_${body.account_id}`, route: "melt-design" });
    if (path === "variants") return Response.json({ id: `plan_${body.account_id}` });
    if (path?.startsWith("products/")) return Response.json({ id: path.split("/")[1], route: "melt-design" });
    if (path === "checkout_configurations") return Response.json({ id: "ch_demo", purchase_url: "https://sandbox.whop.com/checkout/ch_demo/" });
    throw new Error(`Unexpected request ${path}`);
  });
  vi.stubGlobal("fetch", fetchMock);
  return { calls, fetchMock };
}

test("publishes to each assigned store, persists links, and checks out against the seller's variant", async () => {
  const { t, productId } = await setup(); const { calls } = provider();
  const result = await t.action(api.whop.publishProduct, { deviceId: "a", productId, priceCents: 1800 });
  expect(result.listingUrl).toBe("https://sandbox.whop.com/demo-store/products/melt-design/");
  expect(calls[0]).toMatchObject({ key: "Bearer key-a", body: { account_id: "biz_A", visibility: "hidden", description: expect.stringContaining("sky") } });
  expect(calls[1].body).toMatchObject({ product_id: "prod_biz_A", initial_price: 18, currency: "usd", billing_type: "one_time" });
  expect(calls[2]).toMatchObject({ path: "products/prod_biz_A", body: { visibility: "visible" } });
  expect(await t.query(api.products.get, { productId })).toMatchObject({ status: "published", priceCents: 1800, whopListingUrl: result.listingUrl });
  await t.action(api.whop.createCheckout, { deviceId: "b", productId });
  expect(calls[4]).toMatchObject({ key: "Bearer key-a", body: { account_id: "biz_A", variant_id: "plan_biz_A" } });
  expect(calls[4].body).not.toHaveProperty("variant");
  const second = await t.mutation(api.products.createStarter, { deviceId: "b", filament: "bone" });
  await t.action(api.whop.publishProduct, { deviceId: "b", productId: second, priceCents: 1200 });
  expect(calls[5]).toMatchObject({ key: "Bearer key-b", body: { account_id: "biz_B" } });
  expect(await t.query(api.whopData.myStore, { deviceId: "a" })).toEqual({ name: "Store A", accountId: "biz_A" });
});

test("resumes after a variant failure without recreating the external product", async () => {
  const { t, productId } = await setup(); const { calls, fetchMock } = provider();
  fetchMock.mockImplementationOnce(async () => Response.json({ id: "prod_partial" }))
    .mockImplementationOnce(async () => new Response("failure", { status: 503 }));
  const args = { deviceId: "a", productId, priceCents: 1800 };
  await expect(t.action(api.whop.publishProduct, args)).rejects.toThrow("503");
  expect(await t.query(api.products.get, { productId })).toMatchObject({ status: "ready" });
  await expect(t.action(api.whop.publishProduct, { ...args, priceCents: 2000 })).rejects.toThrow("original price");
  await expect(t.mutation(api.products.setFilament, { deviceId: "a", productId, filament: "bone" })).rejects.toThrow("already being published");
  await t.action(api.whop.publishProduct, args);
  expect(calls.map(c => c.path)).toEqual(["variants", "products/prod_partial", "accounts/biz_A"]);
  await t.action(api.whop.publishProduct, args);
  expect(calls.filter(c => c.path === "variants")).toHaveLength(1);
});

test("concurrent attempts use the same external idempotency keys and immutable snapshot", async () => {
  const { t, productId } = await setup(); const { calls } = provider();
  const args = { deviceId: "a", productId, priceCents: 1800 };
  await Promise.all([t.action(api.whop.publishProduct, args), t.action(api.whop.publishProduct, args)]);
  for (const path of ["products", "variants", "products/prod_biz_A"]) {
    const requests = calls.filter(c => c.path === path);
    expect(new Set(requests.map(c => c.idem)).size).toBe(1);
    expect(new Set(requests.map(c => JSON.stringify(c.body))).size).toBe(1);
  }
});

test("missing assignment, credentials, wrong owner, bad prices, and production do not publish", async () => {
  const { t, productId } = await setup(); const { calls } = provider();
  const args = { deviceId: "a", productId, priceCents: 1800 };
  await expect(t.action(api.whop.publishProduct, { ...args, deviceId: "b" })).rejects.toThrow("Only the creator");
  for (const priceCents of [499, 50001, 1500.5]) await expect(t.action(api.whop.publishProduct, { ...args, priceCents })).rejects.toThrow("$5 to $500");
  vi.stubEnv("WHOP_ENVIRONMENT", "production");
  await expect(t.action(api.whop.publishProduct, args)).rejects.toThrow("sandbox");
  vi.stubEnv("WHOP_ENVIRONMENT", "sandbox"); vi.stubEnv("WHOP_STORE_A", undefined);
  await expect(t.action(api.whop.publishProduct, args)).rejects.toThrow("credentials");
  await t.mutation(api.profiles.ensure, { deviceId: "unassigned" });
  const unassigned = await t.mutation(api.products.createStarter, { deviceId: "unassigned", filament: "bone" });
  await expect(t.action(api.whop.publishProduct, { ...args, deviceId: "unassigned", productId: unassigned })).rejects.toThrow("assigned");
  await expect(t.action(api.whop.createCheckout, { deviceId: "unassigned", productId: unassigned })).rejects.toThrow("assigned");
  expect(calls).toHaveLength(0);
});

test("personal draft checkout never publishes and transport failures mark the order failed", async () => {
  const { t, productId } = await setup(); const { calls, fetchMock } = provider();
  await t.action(api.whop.createCheckout, { deviceId: "a", productId });
  expect(calls).toHaveLength(1);
  expect(calls[0].body).toMatchObject({ account_id: "biz_A", variant: { visibility: "hidden", initial_price: 15 } });
  expect(await t.query(api.products.get, { productId })).toMatchObject({ status: "ready" });
  fetchMock.mockRejectedValueOnce(new Error("network failed"));
  await expect(t.action(api.whop.createCheckout, { deviceId: "a", productId })).rejects.toThrow("could not be reached");
  expect((await t.query(api.orders.mine, { deviceId: "a" }))[0].status).toBe("failed");
});

test("payments must match the stored seller account and checkout; late confirmed payments can recover", async () => {
  const { t, productId } = await setup(); provider();
  const checkout = await t.action(api.whop.createCheckout, { deviceId: "a", productId });
  const args = { orderId: checkout.orderId, whopPaymentId: "pay_demo", accountId: "biz_B" };
  await expect(t.mutation(internal.orders.markPaid, args)).rejects.toThrow("account");
  await expect(t.mutation(internal.orders.markPaid, { ...args, accountId: "biz_A", whopCheckoutId: "ch_wrong" })).rejects.toThrow("checkout");
  await t.mutation(internal.orders.markFailed, { orderId: checkout.orderId, reason: "Response was lost" });
  expect(await t.mutation(internal.orders.markPaid, { ...args, accountId: "biz_A" })).toBe("paid");
  expect(await t.mutation(internal.orders.markPaid, { ...args, accountId: "biz_A" })).toBe("duplicate");
});

test("legacy Melt listings can be explicitly exported without bulk changes", async () => {
  const { t, productId } = await setup(); provider();
  await t.mutation(api.products.publish, { deviceId: "a", productId, priceCents: 1700 });
  await t.action(api.whop.publishProduct, { deviceId: "a", productId, priceCents: 1700 });
  expect(await t.query(api.products.get, { productId })).toMatchObject({ status: "published", priceCents: 1700, whopListingUrl: expect.any(String) });
});

test("thumbnail processing is retryable and the image is attached before store visibility", async () => {
  const { t, productId } = await setup(); const { calls, fetchMock } = provider();
  await t.run(async ctx => { await ctx.db.patch(productId, { thumbnailUrl: "https://example.com/design.png" }); });
  const original = fetchMock.getMockImplementation()!;
  let ready = false; let uploads = 0; let fileCreates = 0;
  fetchMock.mockImplementation(async (url, init) => {
    if (String(url) === "https://example.com/design.png") return new Response(new Uint8Array([1, 2, 3]), { headers: { "Content-Type": "image/png" } });
    if (String(url).endsWith("/files")) { fileCreates++; return Response.json({ id: "file_demo", upload_status: "pending", upload_url: "https://upload.example.com/image", upload_headers: { "Content-Type": "image/png" } }); }
    if (String(url) === "https://upload.example.com/image") { uploads++; expect(new Headers(init?.headers).has("Authorization")).toBe(false); return new Response(null, { status: 200 }); }
    if (String(url).endsWith("/files/file_demo")) return Response.json({ upload_status: ready ? "ready" : "processing" });
    return original(url, init);
  });
  const args = { deviceId: "a", productId, priceCents: 1800 };
  await expect(t.action(api.whop.publishProduct, args)).rejects.toThrow("still processing");
  expect(calls.map(c => c.path)).toEqual(["products", "variants"]);
  expect(calls[0].body).not.toHaveProperty("gallery_images");
  expect((await t.query(api.products.get, { productId }))?.status).toBe("ready");
  ready = true;
  await t.action(api.whop.publishProduct, args);
  expect(fileCreates).toBe(1); expect(uploads).toBe(1);
  expect(calls.filter(c => c.path === "products")).toHaveLength(1);
  expect(calls[2].body).toMatchObject({ visibility: "visible", gallery_images: [{ id: "file_demo" }] });
});
