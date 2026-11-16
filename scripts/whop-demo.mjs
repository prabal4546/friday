// Operator-only sandbox setup. Credentials are never printed.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
const deployment = readFileSync('.env.local', 'utf8').match(/^CONVEX_DEPLOYMENT=([^\s#]+)/m)?.[1];
if (deployment !== 'dev:wry-skunk-692') throw new Error('This script only supports dev:wry-skunk-692');
const cli = args => execFileSync('./node_modules/.bin/convex', args, { encoding: 'utf8', timeout: 60_000 }).trim();
if (cli(['env', 'get', 'WHOP_ENVIRONMENT']) !== 'sandbox') throw new Error('Sandbox mode is required');
const key = cli(['env', 'get', 'WHOP_API_KEY']);
const call = async (path, body, idem) => {
  const response = await fetch(`https://sandbox-api.whop.com/api/v1/${path}`, {
    method: body === undefined ? 'GET' : 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', 'Api-Version-Date': '2026-11-13-1', ...(idem ? { 'Idempotency-Key': idem } : {}) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(30_000),
  });
  const json = await response.json();
  if (!response.ok) throw new Error(`${path}: HTTP ${response.status}: ${json.error?.message ?? 'request failed'}`);
  return json;
};
const [command, ...args] = process.argv.slice(2);
if (command === 'inspect') {
  const accounts = await call('accounts');
  console.log(JSON.stringify(accounts.data.map(a => ({ id: a.id, name: a.title, route: a.route })), null, 2));
  for (const a of accounts.data) {
    const hooks = await call(`webhooks?account_id=${a.id}`);
    console.log(JSON.stringify(hooks.data.map(h => ({ account: a.id, id: h.id, url: h.url, enabled: h.enabled, paymentEvents: h.events.includes('payment.succeeded') })), null, 2));
  }
} else if (command === 'create-second-store') {
  const email = args[0];
  if (!email) throw new Error('Usage: create-second-store DEMO_OWNER_EMAIL');
  const a = await call('accounts', { title: 'Friday Store B', country: 'US', email, external_id: 'melt-hackathon-demo-b', send_customer_emails: false }, 'melt-hackathon-demo-store-b-v2');
  console.log(JSON.stringify({ id: a.id, name: a.title }));
} else if (command === 'assign') {
  const [profileId, accountId, secretEnv] = args;
  if (!profileId || !accountId || !/^WHOP_[A-Z0-9_]+$/.test(secretEnv ?? '')) throw new Error('Usage: assign PROFILE_ID ACCOUNT_ID WHOP_WEBHOOK_SECRET_ENV');
  const a = await call(`accounts/${accountId}`);
  const url = `https://wry-skunk-692.convex.site/webhooks/whop?account=${accountId}`;
  const hooks = await call(`webhooks?account_id=${accountId}`);
  let hook = hooks.data.find(h => h.url === url);
  if (!hook) hook = await call('webhooks', { resource_id: accountId, url, events: ['payment.succeeded'], enabled: true, api_version_date: '2026-11-13-1', title: 'Friday sandbox orders' }, `melt-webhook-${accountId}`);
  if (!hook.webhook_secret) hook = await call(`webhooks/${hook.id}`);
  if (hook.webhook_secret) cli(['env', 'set', secretEnv, hook.webhook_secret]);
  else if (!cli(['env', 'get', secretEnv])) throw new Error('Whop only returns a new signing secret once; configure the named env var before assigning another profile');
  cli(['run', 'whopData:assignStore', JSON.stringify({ profileId, accountId, name: a.title, apiKeyEnv: 'WHOP_API_KEY', webhookSecretEnv: secretEnv })]);
  console.log(JSON.stringify({ profileId, accountId, name: a.title, webhookId: hook.id, webhookUrl: url }));
} else if (command === 'test-webhook') {
  console.log(JSON.stringify(await call(`webhooks/${args[0]}/test`, { event: 'payment.succeeded' })));
} else if (command === 'deliveries') {
  console.log(JSON.stringify(await call(`webhooks/${args[0]}/deliveries?first=10`), (k, v) => /secret|token|email|phone|body|headers/i.test(k) ? '[REDACTED]' : v, 2));
} else throw new Error('Use inspect, create-second-store, assign, test-webhook, or deliveries');
