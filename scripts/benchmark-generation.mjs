// Six submissions maximum. Persist intent BEFORE each paid call; never resubmit a lost response.
// Re-run to resume polling existing jobs. Results/assets go to ignored build/generation-benchmark.
import { ConvexHttpClient } from 'convex/browser';
import { makeFunctionReference } from 'convex/server';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
const directory = new URL('../build/generation-benchmark/', import.meta.url);
await mkdir(directory, { recursive: true });
const file = new URL('results.json', directory);
const client = new ConvexHttpClient('https://wry-skunk-692.convex.cloud');
const prompts = [
  ['keychain', 'A polka-dot man keychain: a small connected humanoid figure with raised circular polka dots, two arms, two legs, and an open attachment loop above its head. Flat back, rounded edges, solid printable shape.'],
  ['phone-stand', 'A desktop phone stand with a wide stable base, an angled back support, and a raised front retaining lip to hold a phone upright. Open charging cable slot centered in the front lip. One connected solid printable object.'],
  ['fox-holder', 'A fox-shaped earbud holder: a seated fox with pointed ears and a curled tail forming a wide stable base, with a clearly open oval recess in its back to hold an earbud charging case. One connected solid printable object.'],
];
let state;
try { state = JSON.parse(await readFile(file, 'utf8')); }
catch (error) { if (error.code !== 'ENOENT') throw error; state = { deployment: 'dev:wry-skunk-692', deviceId: `benchmark-${randomUUID()}`, jobs: prompts.flatMap(([name, prompt]) => ['fast', 'detailed'].map(quality => ({ name, prompt, quality }))) }; }
const save = () => writeFile(file, JSON.stringify(state, null, 2));
await save();
await client.mutation(makeFunctionReference('profiles:ensure'), { deviceId: state.deviceId, displayName: 'Generation benchmark' });
for (const job of state.jobs) {
  if (!job.productId && job.submissionAttemptedAt) {
    const mine = await client.query(makeFunctionReference('products:mine'), { deviceId: state.deviceId });
    job.productId = mine.find(p => p.prompt === job.prompt && p.generationQuality === job.quality)?._id;
    if (!job.productId) throw new Error('Ambiguous prior submission. Inspect deployment; do not repeat the paid request.');
  }
  if (!job.productId) {
    job.submissionAttemptedAt = Date.now(); await save();
    job.productId = await client.mutation(makeFunctionReference('products:create'), { deviceId: state.deviceId, prompt: job.prompt, filament: 'bone', generationQuality: job.quality });
    await save(); console.log('Submitted', job.name, job.quality, job.productId);
  }
  let previousStage;
  const deadline = Date.now() + 15 * 60_000;
  while (!job.result || job.result.status === 'generating') {
    try {
      job.result = await client.query(makeFunctionReference('products:get'), { productId: job.productId });
      await save();
      if (job.result.generationStage !== previousStage) { previousStage = job.result.generationStage; console.log(job.name, job.quality, previousStage ?? job.result.status); }
      if (job.result.status !== 'generating') break;
    } catch (error) { console.log('Read failed; retrying read only:', error.message); }
    if (Date.now() > deadline) throw new Error('Observation timed out. Resume this script to keep watching; no generation will be repeated.');
    await new Promise(resolve => setTimeout(resolve, 3000));
  }
  const p = job.result;
  job.previewSeconds = p.previewReadyAt ? (p.previewReadyAt - p.generationRequestedAt) / 1000 : null;
  job.readySeconds = p.generationFinishedAt ? (p.generationFinishedAt - p.generationRequestedAt) / 1000 : null;
  for (const [field, extension] of [['usdzUrl', 'usdz'], ['thumbnailUrl', 'png']]) {
    if (!p[field]) continue;
    try { const response = await fetch(p[field]); if (!response.ok) throw new Error(`HTTP ${response.status}`); await writeFile(new URL(`${job.name}-${job.quality}.${extension}`, directory), Buffer.from(await response.arrayBuffer())); }
    catch (error) { console.log('Asset download failed', job.name, extension, error.message); }
  }
  await save(); console.log('Finished', job.name, job.quality, JSON.stringify({ status: p.status, previewSeconds: job.previewSeconds, readySeconds: job.readySeconds }));
}
console.log('All six requests observed. Inspect geometry and compare medians before changing the default.');
