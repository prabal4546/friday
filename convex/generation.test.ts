/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { GENERATION_ENDPOINTS } from "./lib/generationConfig";
import schema from "./schema";
const modules = import.meta.glob(["./**/*.ts", "./**/*.js", "!./**/*.test.ts", "!./**/*.d.ts"]);
afterEach(() => { vi.unstubAllEnvs(); vi.unstubAllGlobals(); vi.useRealTimers(); });
async function setup(quality?: "fast" | "detailed") {
  vi.useFakeTimers(); vi.stubEnv("FAL_KEY", "test");
  const t = convexTest(schema, modules);
  await t.mutation(api.profiles.ensure, { deviceId: "generation-test" });
  const productId = await t.mutation(api.products.create, { deviceId: "generation-test", prompt: "A phone stand", filament: "bone", generationQuality: quality });
  return { t, productId };
}
async function attached() {
  const state = await setup();
  await state.t.mutation(internal.products.attachFalRequest, { productId: state.productId, falRequestId: "request", falStatusUrl: "https://queue.fal.run/status", falResponseUrl: "https://queue.fal.run/result" });
  return state;
}
test.each([undefined, "fast", "detailed"] as const)("routes %s, defaults old clients to detailed and submits once", async quality => {
  const { t, productId } = await setup(quality);
  const fetcher = vi.fn().mockResolvedValue(Response.json({ request_id: "request", status_url: "https://queue.fal.run/status", response_url: "https://queue.fal.run/result" }));
  vi.stubGlobal("fetch", fetcher);
  await t.action(internal.generation.start, { productId });
  await t.action(internal.generation.start, { productId });
  expect(fetcher).toHaveBeenCalledTimes(1);
  expect(fetcher.mock.calls[0][0]).toContain(GENERATION_ENDPOINTS[quality ?? "detailed"]);
  const input = JSON.parse(fetcher.mock.calls[0][1].body);
  expect(input.mode).toBe("preview");
  expect(input.target_polycount).toBe(quality === "fast" ? 4000 : 20000);
  if (quality === "fast") expect(input).toMatchObject({ enable_prompt_expansion: false, enable_rigging: false, enable_animation: false, enable_pbr: false });
  expect(await t.query(api.products.get, { productId })).toMatchObject({ generationQuality: quality ?? "detailed", generationStage: "queued", submittedAt: expect.any(Number) });
});
test("stages cannot regress and simultaneous completion exposes one preview before one print job", async () => {
  const { t, productId } = await attached();
  await t.mutation(internal.products.updateGenerationStage, { productId, stage: "generating" });
  await t.mutation(internal.products.updateGenerationStage, { productId, stage: "queued" });
  expect((await t.query(api.products.get, { productId }))?.generationStage).toBe("generating");
  const args = { productId, usdzUrl: "https://files/model.usdz", objUrl: "https://files/model.obj" };
  expect(await t.mutation(internal.products.attachPreview, args)).toBe(true);
  expect(await t.mutation(internal.products.attachPreview, args)).toBe(false);
  await t.mutation(internal.products.failGeneration, { productId, reason: "late failure" });
  expect(await t.query(api.products.get, { productId })).toMatchObject({ status: "generating", generationStage: "preparingPrint", usdzUrl: args.usdzUrl, previewReadyAt: expect.any(Number) });
  await expect(t.mutation(api.products.publish, { deviceId: "generation-test", productId, priceCents: 1500 })).rejects.toThrow("ready draft");
  const jobs = await t.run(ctx => ctx.db.system.query("_scheduled_functions").collect());
  expect(jobs.filter(j => j.name === "generation:preparePrint")).toHaveLength(1);
});
test.each([429, 503, "network"])("transient %s retries the existing job without paid submission", async failure => {
  const { t, productId } = await attached();
  const fetcher = vi.fn();
  if (failure === "network") fetcher.mockRejectedValueOnce(new Error("offline"));
  else fetcher.mockResolvedValueOnce(new Response(null, { status: Number(failure) }));
  fetcher.mockResolvedValueOnce(Response.json({ status: "IN_PROGRESS" }));
  vi.stubGlobal("fetch", fetcher);
  await t.action(internal.generation.poll, { productId, attempt: 1 });
  expect((await t.query(api.products.get, { productId }))?.status).toBe("generating");
  await t.action(internal.generation.poll, { productId, attempt: 2 });
  expect((await t.query(api.products.get, { productId }))?.generationStage).toBe("generating");
  expect(fetcher.mock.calls.every(call => !call[1].method)).toBe(true);
  const jobs = await t.run(ctx => ctx.db.system.query("_scheduled_functions").collect());
  expect(jobs.some(j => j.name === "generation:poll")).toBe(true);
});
test.each(["FAILED", "result-error"])("terminal %s fails promptly", async status => {
  const { t, productId } = await attached();
  const fetcher = vi.fn().mockResolvedValueOnce(Response.json({ status: status === "FAILED" ? status : "COMPLETED" })).mockResolvedValueOnce(new Response(null, { status: 422 }));
  vi.stubGlobal("fetch", fetcher);
  await t.action(internal.generation.poll, { productId, attempt: 1 });
  expect((await t.query(api.products.get, { productId }))?.status).toBe("failed");
});
test("duplicate webhook/poll results schedule one print preparation and failed STL keeps the preview", async () => {
  const { t, productId } = await attached();
  const fetcher = vi.fn().mockResolvedValueOnce(Response.json({ status: "COMPLETED" }))
    .mockResolvedValueOnce(Response.json({ model_urls: { usdz: { url: "https://files/model.usdz" }, obj: { url: "https://files/model.obj" } } }))
    .mockResolvedValueOnce(new Response(null, { status: 503 }));
  vi.stubGlobal("fetch", fetcher);
  await t.action(internal.generation.poll, { productId, attempt: 1 });
  await t.action(internal.generation.poll, { productId, attempt: 2 });
  expect(fetcher).toHaveBeenCalledTimes(2);
  await t.action(internal.generation.preparePrint, { productId, objUrl: "https://files/model.obj" });
  await t.action(internal.generation.preparePrint, { productId, objUrl: "https://files/model.obj" });
  expect(fetcher).toHaveBeenCalledTimes(3);
  expect(await t.query(api.products.get, { productId })).toMatchObject({ status: "ready", printability: "warning", usdzUrl: "https://files/model.usdz", printPreparationStartedAt: expect.any(Number), printPreparationFinishedAt: expect.any(Number) });
});
test("preview is observable before STL preparation and successful preparation becomes ready", async () => {
  const { t, productId } = await attached();
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3")));
  await t.mutation(internal.products.observeProviderCompletion, { productId });
  vi.advanceTimersByTime(10);
  await t.mutation(internal.products.attachPreview, { productId, usdzUrl: "https://files/model.usdz", objUrl: "https://files/model.obj" });
  const preview = (await t.query(api.products.get, { productId }))!;
  expect(preview.status).toBe("generating");
  expect(preview.stlUrl).toBeUndefined();
  expect(preview.providerCompletedAt).toBeLessThan(preview.previewReadyAt!);
  await t.action(internal.generation.preparePrint, { productId, objUrl: "https://files/model.obj" });
  const ready = (await t.query(api.products.get, { productId }))!;
  expect(ready).toMatchObject({ status: "ready", printability: "ok", stlUrl: expect.any(String) });
  await t.mutation(internal.products.finishGeneration, { productId, usdzUrl: "https://files/duplicate.usdz" });
  expect((await t.query(api.products.get, { productId }))?.stlUrl).toBe(ready.stlUrl);
});
test("webhook only schedules a provider-verified result, including duplicate notifications", async () => {
  const { t, productId } = await attached();
  const notification = { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ request_id: "request", status: "OK", payload: { model_urls: { usdz: { url: "https://untrusted/forged.usdz" } } } }) };
  expect((await t.fetch("/webhooks/fal", notification)).status).toBe(200);
  expect((await t.fetch("/webhooks/fal", notification)).status).toBe(200);
  expect((await t.query(api.products.get, { productId }))?.usdzUrl).toBeUndefined();
  const jobs = await t.run(ctx => ctx.db.system.query("_scheduled_functions").collect());
  expect(jobs.filter(j => j.name === "generation:poll")).toHaveLength(2);
});
