import { v } from "convex/values";
import { api, internal } from "./_generated/api";
import { internalAction } from "./_generated/server";
import { objToBinaryStl } from "./lib/stl";

const FAL_MODEL = "fal-ai/meshy/v7.1/text-to-3d";
const POLL_MS = 10 * 1000;
const MAX_POLLS = 60;

function fileUrl(value: unknown, key: string) {
  if (typeof value !== "object" || value === null) return undefined;
  const file = (value as Record<string, unknown>)[key];
  if (typeof file !== "object" || file === null) return undefined;
  const url = (file as Record<string, unknown>).url;
  return typeof url === "string" ? url : undefined;
}

export const start = internalAction({
  args: { productId: v.id("products") },
  handler: async (ctx, args) => {
    const key = process.env.FAL_KEY;
    const product = await ctx.runQuery(api.products.get, args);
    if (key === undefined || product === null || product.status !== "generating") return null;

    const webhook = encodeURIComponent(`${process.env.CONVEX_SITE_URL}/webhooks/fal`);
    const response = await fetch(`https://queue.fal.run/${FAL_MODEL}?fal_webhook=${webhook}`, {
      method: "POST",
      headers: { Authorization: `Key ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        prompt: product.prompt,
        mode: "preview",
        topology: "triangle",
        target_polycount: 20000,
      }),
    });
    const queued: unknown = response.ok ? await response.json() : null;
    const { request_id, status_url, response_url } = (queued ?? {}) as Record<string, unknown>;
    if (
      typeof request_id !== "string" ||
      typeof status_url !== "string" ||
      typeof response_url !== "string" ||
      !status_url.startsWith("https://queue.fal.run/") ||
      !response_url.startsWith("https://queue.fal.run/")
    ) {
      await ctx.runMutation(internal.products.failGeneration, {
        productId: args.productId,
        reason: `The model service refused the request (status ${response.status})`,
      });
      return null;
    }
    await ctx.runMutation(internal.products.attachFalRequest, {
      productId: args.productId,
      falRequestId: request_id,
      falStatusUrl: status_url,
      falResponseUrl: response_url,
    });
    await ctx.scheduler.runAfter(POLL_MS, internal.generation.poll, { productId: args.productId, attempt: 1 });
    return null;
  },
});

export const poll = internalAction({
  args: { productId: v.id("products"), attempt: v.number() },
  handler: async (ctx, args) => {
    const key = process.env.FAL_KEY;
    const product = await ctx.runQuery(api.products.get, { productId: args.productId });
    if (
      key === undefined ||
      product === null ||
      product.status !== "generating" ||
      product.falStatusUrl === undefined ||
      product.falResponseUrl === undefined
    ) {
      return null;
    }
    const headers = { Authorization: `Key ${key}` };
    const fail = (reason: string) =>
      ctx.runMutation(internal.products.failGeneration, { productId: args.productId, reason });

    const statusResponse = await fetch(product.falStatusUrl, { headers });
    const status: unknown = statusResponse.ok ? await statusResponse.json() : null;
    if ((status as Record<string, unknown> | null)?.status !== "COMPLETED") {
      if (args.attempt >= MAX_POLLS) {
        await fail("The model service timed out");
      } else {
        await ctx.scheduler.runAfter(POLL_MS, internal.generation.poll, {
          productId: args.productId,
          attempt: args.attempt + 1,
        });
      }
      return null;
    }

    const resultResponse = await fetch(product.falResponseUrl, { headers });
    const result: unknown = resultResponse.ok ? await resultResponse.json() : null;
    const models = (result as Record<string, unknown> | null)?.model_urls;
    const usdzUrl = fileUrl(models, "usdz");
    if (usdzUrl === undefined) {
      await fail("The model service could not make this design");
      return null;
    }

    let stlUrl: string | undefined;
    const objUrl = fileUrl(models, "obj");
    if (objUrl !== undefined) {
      try {
        const stl = objToBinaryStl(await (await fetch(objUrl)).text());
        const storageId = await ctx.storage.store(new Blob([stl], { type: "model/stl" }));
        stlUrl = (await ctx.storage.getUrl(storageId)) ?? undefined;
      } catch (error) {
        console.error("Could not prepare the STL print file", error);
      }
    }
    await ctx.runMutation(internal.products.finishGeneration, {
      productId: args.productId,
      usdzUrl,
      stlUrl,
      thumbnailUrl: fileUrl(result, "thumbnail"),
    });
    return null;
  },
});
