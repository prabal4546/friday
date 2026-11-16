import { v } from "convex/values";
import { api, internal } from "./_generated/api";
import { internalAction } from "./_generated/server";
import { GENERATION_ENDPOINTS, generationInput } from "./lib/generationConfig";
import { objToBinaryStl } from "./lib/stl";

const POLL_MS = 10_000;
const MAX_POLLS = 60;

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null ? value as Record<string, unknown> : null;
}
function fileUrl(value: unknown, key: string) {
  const url = record(record(value)?.[key])?.url;
  return typeof url === "string" && url.startsWith("https://") ? url : undefined;
}
function transient(status: number) { return status === 408 || status === 429 || status >= 500; }

export const start = internalAction({
  args: { productId: v.id("products") },
  returns: v.null(),
  handler: async (ctx, { productId }) => {
    const key = process.env.FAL_KEY;
    const product = await ctx.runQuery(api.products.get, { productId });
    if (!key || product === null || product.status !== "generating") return null;
    if (!await ctx.runMutation(internal.products.claimSubmission, { productId })) return null;
    const quality = product.generationQuality ?? "detailed";
    const endpoint = product.generationEndpoint ?? GENERATION_ENDPOINTS[quality];
    const webhook = encodeURIComponent(`${process.env.CONVEX_SITE_URL}/webhooks/fal`);
    try {
      // Never retry submission: a lost response may still represent a billed provider job.
      const response = await fetch(`https://queue.fal.run/${endpoint}?fal_webhook=${webhook}`, {
        method: "POST", headers: { Authorization: `Key ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify(generationInput(product.prompt, quality)), signal: AbortSignal.timeout(60_000),
      });
      const queued = record(response.ok ? await response.json() : null);
      const requestId = queued?.request_id, statusUrl = queued?.status_url, responseUrl = queued?.response_url;
      if (typeof requestId !== "string" || typeof statusUrl !== "string" || typeof responseUrl !== "string" ||
          !statusUrl.startsWith("https://queue.fal.run/") || !responseUrl.startsWith("https://queue.fal.run/")) {
        await ctx.runMutation(internal.products.failGeneration, { productId, reason: `The model service refused the request (status ${response.status})` });
        return null;
      }
      await ctx.runMutation(internal.products.attachFalRequest, { productId, falRequestId: requestId, falStatusUrl: statusUrl, falResponseUrl: responseUrl });
      await ctx.scheduler.runAfter(POLL_MS, internal.generation.poll, { productId, attempt: 1 });
    } catch (error) {
      console.error("Generation submission failed", error);
      await ctx.runMutation(internal.products.failGeneration, { productId, reason: "Couldn't submit the model. Please try again." });
    }
    return null;
  },
});

export const poll = internalAction({
  args: { productId: v.id("products"), attempt: v.number() },
  returns: v.null(),
  handler: async (ctx, { productId, attempt }) => {
    const key = process.env.FAL_KEY;
    const product = await ctx.runQuery(api.products.get, { productId });
    if (!key || product === null || product.status !== "generating" || product.previewReadyAt !== undefined ||
        !product.falStatusUrl || !product.falResponseUrl) return null;
    const headers = { Authorization: `Key ${key}` };
    const fail = (reason: string) => ctx.runMutation(internal.products.failGeneration, { productId, reason });
    const retry = async () => {
      if (attempt >= MAX_POLLS) await fail("The model service timed out");
      else await ctx.scheduler.runAfter(POLL_MS, internal.generation.poll, { productId, attempt: attempt + 1 });
    };
    try {
      const response = await fetch(product.falStatusUrl, { headers, signal: AbortSignal.timeout(30_000) });
      if (!response.ok) {
        if (transient(response.status)) await retry();
        else await fail("Couldn't retrieve this generation from the model service.");
        return null;
      }
      const status = record(await response.json());
      if (status?.status === "FAILED" || status?.status === "ERROR") {
        await fail("The model service couldn't generate this design.");
        return null;
      }
      if (status?.status !== "COMPLETED") {
        if (status?.status === "IN_QUEUE" || status?.status === "IN_PROGRESS") {
          await ctx.runMutation(internal.products.updateGenerationStage, { productId, stage: status.status === "IN_QUEUE" ? "queued" : "generating" });
        }
        await retry();
        return null;
      }
      await ctx.runMutation(internal.products.observeProviderCompletion, { productId });
      const resultResponse = await fetch(product.falResponseUrl, { headers, signal: AbortSignal.timeout(30_000) });
      if (!resultResponse.ok) {
        if (transient(resultResponse.status)) await retry();
        else await fail("The model service couldn't generate this design.");
        return null;
      }
      const result = record(await resultResponse.json());
      const usdzUrl = fileUrl(result?.model_urls, "usdz");
      if (!usdzUrl) {
        await fail("The model service could not make this design");
        return null;
      }
      await ctx.runMutation(internal.products.attachPreview, {
        productId, usdzUrl, objUrl: fileUrl(result?.model_urls, "obj"), thumbnailUrl: fileUrl(result, "thumbnail"),
      });
    } catch (error) {
      console.error("Generation status temporarily unavailable", error);
      await retry();
    }
    return null;
  },
});

export const preparePrint = internalAction({
  args: { productId: v.id("products"), objUrl: v.optional(v.string()) },
  returns: v.null(),
  handler: async (ctx, { productId, objUrl }) => {
    if (!await ctx.runMutation(internal.products.claimPrintPreparation, { productId })) return null;
    const product = await ctx.runQuery(api.products.get, { productId });
    if (!product?.usdzUrl) return null;
    let stlUrl: string | undefined;
    if (objUrl) {
      try {
        const response = await fetch(objUrl, { signal: AbortSignal.timeout(60_000) });
        if (!response.ok) throw new Error(`OBJ download failed: ${response.status}`);
        const stl = objToBinaryStl(await response.text());
        const storageId = await ctx.storage.store(new Blob([stl], { type: "model/stl" }));
        stlUrl = (await ctx.storage.getUrl(storageId)) ?? undefined;
      } catch (error) { console.error("Could not prepare the STL print file", error); }
    }
    await ctx.runMutation(internal.products.finishGeneration, { productId, usdzUrl: product.usdzUrl, thumbnailUrl: product.thumbnailUrl, stlUrl });
    return null;
  },
});
