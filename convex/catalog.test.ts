/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import { CATALOG } from "./lib/catalog";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "./**/*.js", "!./**/*.test.ts", "!./**/*.d.ts"]);

async function legacyWorld() {
  const t = convexTest(schema, modules);
  await t.mutation(internal.seed.run, {});
  // Seed ownership can already have been claimed by a real device.
  await t.mutation(api.profiles.ensure, { deviceId: "catalog-test", claimSeed: true });
  const seeded = await t.query(api.products.storefront, {});
  const entries = seeded.map(p => ({ productId: p._id, catalogKey: p.catalogKey! }));
  await t.run(async ctx => {
    for (const p of entries) await ctx.db.patch(p.productId, { catalogKey: undefined });
  });
  return { t, entries };
}

test("all seeded shop and challenge products carry their explicit catalog identity", async () => {
  const t = convexTest(schema, modules);
  await t.mutation(internal.seed.run, {});
  const shop = await t.query(api.products.storefront, {});
  expect(shop.map(p => p.catalogKey).sort()).toEqual(Object.keys(CATALOG).sort());
  const duels = [...await t.query(api.duels.live, {}), ...await t.query(api.duels.settled, {})];
  for (const p of [...shop, ...duels.flatMap(d => [d.productA, d.productB])]) {
    expect(p).toMatchObject(CATALOG[p.catalogKey!]);
    expect(p.usdzUrl).toBeUndefined();
  }
});

test("repair changes only catalogKey and is idempotent after seed ownership is claimed", async () => {
  const { t, entries } = await legacyWorld();
  const before = await t.run(async ctx => ({
    products: await Promise.all(entries.map(p => ctx.db.get(p.productId))),
    duels: await ctx.db.query("duels").take(20),
    orders: await ctx.db.query("orders").take(20),
  }));
  expect(await t.mutation(internal.seed.repairCatalog, { products: entries })).toEqual({ updated: 7, skipped: 0 });
  expect(await t.mutation(internal.seed.repairCatalog, { products: entries })).toEqual({ updated: 0, skipped: 7 });
  const after = await t.run(async ctx => ({
    products: await Promise.all(entries.map(p => ctx.db.get(p.productId))),
    duels: await ctx.db.query("duels").take(20),
    orders: await ctx.db.query("orders").take(20),
  }));
  expect(after).toEqual({ ...before, products: before.products.map((p, i) => ({ ...p, catalogKey: entries[i].catalogKey })) });
});

test("repair skips existing media and identifiers", async () => {
  const { t, entries } = await legacyWorld();
  await t.run(async ctx => {
    await ctx.db.patch(entries[0].productId, { usdzUrl: "https://example.com/model.usdz" });
    await ctx.db.patch(entries[1].productId, { thumbnailUrl: "https://example.com/thumbnail.png" });
    await ctx.db.patch(entries[2].productId, { stlUrl: "https://example.com/model.stl" });
    await ctx.db.patch(entries[3].productId, { starterKey: "polka-man" });
    await ctx.db.patch(entries[4].productId, { catalogKey: entries[5].catalogKey });
  });
  const before = await t.run(ctx => Promise.all(entries.slice(0, 5).map(p => ctx.db.get(p.productId))));
  expect(await t.mutation(internal.seed.repairCatalog, { products: entries })).toEqual({ updated: 2, skipped: 5 });
  expect(await t.run(ctx => Promise.all(entries.slice(0, 5).map(p => ctx.db.get(p.productId))))).toEqual(before);
});

test.each(["name", "prompt", "status"] as const)("repair rejects incorrect %s and rolls the batch back", async field => {
  const { t, entries } = await legacyWorld();
  await t.run(async ctx => { await ctx.db.patch(entries[1].productId,
    field === "status" ? { status: "generating" } : { [field]: "A user-created design" }); });
  await expect(t.mutation(internal.seed.repairCatalog, { products: entries })).rejects.toThrow("does not match");
  expect((await t.query(api.products.get, { productId: entries[0].productId }))!.catalogKey).toBeUndefined();
});

test("repair rejects duplicate IDs and invalid catalog keys", async () => {
  const { t, entries } = await legacyWorld();
  await expect(t.mutation(internal.seed.repairCatalog, { products: [entries[0], entries[0]] })).rejects.toThrow("distinct");
  await expect(t.mutation(internal.seed.repairCatalog, {
    // @ts-expect-error Deliberately exercise the deployed validator.
    products: [{ productId: entries[0].productId, catalogKey: "unknown" }],
  })).rejects.toThrow();
});
