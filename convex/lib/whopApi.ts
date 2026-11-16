import { ConvexError } from "convex/values";

export const WHOP_API = "https://sandbox-api.whop.com/api/v1";
export const WHOP_VERSION = "2026-11-13-1";

export function sandboxKey(envName: string) {
  if (process.env.WHOP_ENVIRONMENT !== "sandbox") throw new ConvexError("Checkout is unavailable. Whop sandbox mode must be configured.");
  const key = process.env[envName];
  if (!key) throw new ConvexError("Checkout is unavailable. The demo store credentials need setup.");
  return key;
}

export function record(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

export function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || !value) throw new ConvexError(`Whop returned an invalid ${field}. Please retry.`);
  return value;
}

export async function whopRequest(key: string, path: string, body?: unknown, idempotencyKey?: string, method = body === undefined ? "GET" : "POST") {
  let response: Response;
  try {
    response = await fetch(`${WHOP_API}/${path}`, {
      method, headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "Api-Version-Date": WHOP_VERSION,
        ...(idempotencyKey ? { "Idempotency-Key": idempotencyKey } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(30_000),
    });
  } catch { throw new ConvexError("Whop could not be reached. Please retry."); }
  if (!response.ok) {
    // Do not forward provider bodies, which can echo credentials or customer data.
    throw new ConvexError(`Whop request failed with status ${response.status}. ${response.status === 401 || response.status === 403 ? "Check the demo store credentials and permissions." : "Please retry."}`);
  }
  try { return record(await response.json()); }
  catch { throw new ConvexError("Whop returned an unreadable response. Please retry."); }
}

export function sandboxUrl(value: unknown): string {
  const url = new URL(requiredString(value, "URL"));
  if (url.protocol !== "https:" || url.hostname !== "sandbox.whop.com") throw new ConvexError("Whop did not return a sandbox URL");
  return url.href;
}

export async function uploadThumbnail(key: string, url: string, id: string): Promise<string> {
  const source = new URL(url);
  if (source.protocol !== "https:") throw new ConvexError("The design thumbnail must use HTTPS");
  const image = await fetch(source, { signal: AbortSignal.timeout(20_000) });
  if (!image.ok) throw new ConvexError("The design thumbnail could not be loaded. Please retry.");
  const type = image.headers.get("content-type")?.split(";")[0] ?? "";
  if (!["image/png", "image/jpeg", "image/webp"].includes(type)) throw new ConvexError("The design thumbnail must be PNG, JPEG, or WebP");
  const bytes = await image.arrayBuffer();
  if (bytes.byteLength > 10 * 1024 * 1024) throw new ConvexError("The design thumbnail is too large");
  const file = await whopRequest(key, "files", { filename: `friday-${id}.${type.split("/")[1]}`, visibility: "public", byte_size: bytes.byteLength }, `melt-image-${id}`);
  const fileId = requiredString(file.id, "file ID");
  if (file.upload_status !== "ready") {
    const uploadUrl = new URL(requiredString(file.upload_url, "upload URL"));
    if (uploadUrl.protocol !== "https:") throw new ConvexError("Whop returned an invalid upload destination");
    const headers = new Headers();
    for (const [name, value] of Object.entries(record(file.upload_headers))) if (typeof value === "string") headers.set(name, value);
    const uploaded = await fetch(uploadUrl, { method: "PUT", headers, body: bytes, signal: AbortSignal.timeout(30_000) });
    if (!uploaded.ok) throw new ConvexError("The thumbnail upload failed. Please retry.");
  }
  return fileId;
}
