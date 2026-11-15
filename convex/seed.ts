import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { internalMutation } from "./_generated/server";
import { profileByDevice, SEED_DEMO_DEVICE, STARTING_CREDITS } from "./profiles";

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;

export const run = internalMutation({
  args: {},
  handler: async (ctx) => {
    if ((await profileByDevice(ctx, "seed:priya")) !== null) return "already seeded";
    const now = Date.now();

    const profile = (deviceId: string, displayName: string, wins: number, earningsCents: number) =>
      ctx.db.insert("profiles", { deviceId, displayName, credits: STARTING_CREDITS, wins, earningsCents });
    const you = await profile(SEED_DEMO_DEVICE, "You", 1, 59950);
    const priya = await profile("seed:priya", "Priya Raman", 5, 58240);
    const tomas = await profile("seed:tomas", "Tomás Herrera", 2, 28200);
    const wen = await profile("seed:wen", "Wen Liu", 1, 22890);
    const aoife = await profile("seed:aoife", "Aoife Byrne", 0, 0);
    const kwame = await profile("seed:kwame", "Kwame Mensah", 0, 0);

    const published = (
      creatorId: Id<"profiles">,
      name: string,
      prompt: string,
      filament: string,
      priceCents: number,
      printCostCents: number,
      salesCount: number,
    ) =>
      ctx.db.insert("products", {
        creatorId,
        name,
        prompt,
        status: "published",
        filament,
        priceCents,
        printCostCents,
        printability: "ok",
        salesCount,
      });

    const vase = await published(you, "Twisted hex vase", "A hexagonal vase with a slow twist", "sky", 2200, 790, 31);
    await ctx.db.insert("products", {
      creatorId: you,
      name: "Mushroom lamp shade",
      prompt: "A mushroom shaped shade for a small desk lamp",
      status: "ready",
      filament: "grape",
      priceCents: 1900,
      printCostCents: 880,
      printability: "warning",
      printNote: "The cap overhang needs supports, which adds $1.20 per print",
      salesCount: 0,
    });
    await ctx.db.insert("products", {
      creatorId: you,
      name: "Honeycomb coaster set",
      prompt: "A set of honeycomb coasters that lock together",
      status: "failed",
      filament: "sunflower",
      priceCents: 1200,
      printability: "pending",
      failureReason: "The model service timed out",
      salesCount: 0,
    });
    const capybara = await published(you, "Sleepy capybara planter", "A desk planter shaped like a sleepy capybara", "caramel", 1800, 640, 14);
    await ctx.db.insert("products", {
      creatorId: you,
      name: "Rocket pen cup",
      prompt: "A retro rocket that holds pens on my desk",
      status: "ready",
      filament: "lava",
      priceCents: 1600,
      printCostCents: 520,
      printability: "ok",
      salesCount: 0,
    });
    await ctx.db.insert("products", {
      creatorId: you,
      name: "Tiny dragon that guards my charging cable",
      prompt: "A tiny dragon that guards my charging cable and judges anyone who unplugs it",
      status: "generating",
      filament: "matcha",
      priceCents: 1500,
      printability: "pending",
      salesCount: 0,
    });
    const ghost = await published(priya, "Ghost night light", "A ghost night light with a wavy hem", "bone", 1400, 490, 30);
    const fox = await published(tomas, "Fox desk buddy", "A fox that holds my earbuds", "tangerine", 1500, 560, 30);
    const duck = await published(wen, "Duck in a top hat", "A duck in a top hat for my desk", "sunflower", 1700, 610, 21);
    const bins = await published(kwame, "Stackable hex bins", "Two hexagonal bins that stack", "matcha", 900, 310, 0);
    const egg = await published(aoife, "Egg cup", "An egg cup with a wide foot", "sky", 1100, 380, 0);

    const liveDuel = async (
      productAId: Id<"products">,
      productBId: Id<"products">,
      endsAt: number,
      sales: [number, number],
      pools: [number, number],
    ) => {
      const duelId = await ctx.db.insert("duels", {
        productAId,
        productBId,
        theme: "Desk buddies",
        endsAt,
        status: "live",
        salesA: sales[0],
        salesB: sales[1],
        poolA: pools[0],
        poolB: pools[1],
      });
      await ctx.scheduler.runAt(endsAt, internal.duels.settle, { duelId });
    };
    await liveDuel(capybara, ghost, now + 5 * HOUR + 41 * MINUTE, [14, 11], [3200, 2450]);
    await liveDuel(fox, duck, now + 11 * HOUR + 5 * MINUTE, [8, 9], [1100, 1900]);
    await liveDuel(bins, egg, now + 23 * HOUR + 52 * MINUTE, [0, 0], [0, 0]);

    const settledDuel = async (
      productAId: Id<"products">,
      productBId: Id<"products">,
      endsAt: number,
      sales: [number, number],
      pools: [number, number],
      stake: { side: "a" | "b"; amount: number; payout: number },
    ) => {
      const duelId = await ctx.db.insert("duels", {
        productAId,
        productBId,
        endsAt,
        status: "settled",
        salesA: sales[0],
        salesB: sales[1],
        poolA: pools[0],
        poolB: pools[1],
        winner: sales[0] > sales[1] ? "a" : "b",
      });
      await ctx.db.insert("stakes", { duelId, profileId: you, ...stake });
    };
    await settledDuel(vase, fox, now - 20 * HOUR, [31, 22], [12400, 8650], { side: "a", amount: 200, payout: 340 });
    await settledDuel(duck, ghost, now - 3 * 24 * HOUR, [12, 19], [2100, 4300], { side: "a", amount: 100, payout: 0 });

    await ctx.db.insert("orders", {
      productId: ghost,
      buyerId: you,
      creatorId: priya,
      filament: "bone",
      amountCents: 1400,
      status: "paid",
      fulfillment: "printing",
      whopPaymentId: "seed:pay_1042",
      paidAt: now - 20 * HOUR,
    });
    return "seeded";
  },
});
