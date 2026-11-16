import { v } from "convex/values";

export const catalogKey = v.union(
  v.literal("twisted-hex-vase"), v.literal("capybara-planter"),
  v.literal("ghost-night-light"), v.literal("fox-desk-buddy"),
  v.literal("top-hat-duck"), v.literal("hex-bins"), v.literal("egg-cup"),
);

export const CATALOG = {
  "twisted-hex-vase": { name: "Twisted hex vase", prompt: "A hexagonal vase with a slow twist" },
  "capybara-planter": { name: "Sleepy capybara planter", prompt: "A desk planter shaped like a sleepy capybara" },
  "ghost-night-light": { name: "Ghost night light", prompt: "A ghost night light with a wavy hem" },
  "fox-desk-buddy": { name: "Fox desk buddy", prompt: "A fox that holds my earbuds" },
  "top-hat-duck": { name: "Duck in a top hat", prompt: "A duck in a top hat for my desk" },
  "hex-bins": { name: "Stackable hex bins", prompt: "Two hexagonal bins that stack" },
  "egg-cup": { name: "Egg cup", prompt: "An egg cup with a wide foot" },
} as const;
