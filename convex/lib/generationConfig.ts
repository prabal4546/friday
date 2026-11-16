export type GenerationQuality = "fast" | "detailed";

export const GENERATION_ENDPOINTS = {
  fast: "meshy/t2/text-to-3d",
  detailed: "fal-ai/meshy/v7.1/text-to-3d",
} as const;

export function generationInput(prompt: string, quality: GenerationQuality) {
  if (quality === "fast") {
    return {
      prompt, mode: "preview", target_polycount: 4000,
      enable_prompt_expansion: false, enable_rigging: false,
      enable_animation: false, enable_pbr: false,
    };
  }
  return { prompt, mode: "preview", topology: "triangle", target_polycount: 20000 };
}
