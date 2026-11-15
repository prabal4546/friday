const TOLERANCE_SECONDS = 5 * 60;

export async function signStandardWebhook(secret: string, id: string, timestamp: string, body: string) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, encoder.encode(`${id}.${timestamp}.${body}`));
  let binary = "";
  for (const byte of new Uint8Array(digest)) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function timingSafeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function verifyStandardWebhook(args: {
  secret: string;
  id: string | null;
  timestamp: string | null;
  signature: string | null;
  body: string;
  nowMs: number;
}) {
  if (args.id === null || args.timestamp === null || args.signature === null) return false;
  const seconds = Number(args.timestamp);
  if (!Number.isFinite(seconds) || Math.abs(args.nowMs / 1000 - seconds) > TOLERANCE_SECONDS) {
    return false;
  }
  const expected = await signStandardWebhook(args.secret, args.id, args.timestamp, args.body);
  return args.signature.split(" ").some((candidate) => {
    const [version, value] = candidate.split(",");
    return version === "v1" && value !== undefined && timingSafeEqual(value, expected);
  });
}
