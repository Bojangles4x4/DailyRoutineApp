'use strict';

const assert = require('assert');
const { createClient, CloudConflictError } = require('../sync-cloud.js');

function storage() {
  const values = new Map();
  return {
    getItem: key => values.has(key) ? values.get(key) : null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: key => values.delete(key)
  };
}

function response(status, payload) {
  return { ok: status >= 200 && status < 300, status, text: async () => payload === null ? '' : JSON.stringify(payload) };
}

const tests = [];
function test(name, run) { tests.push({ name, run }); }

test('requests an existing-owner email link without exposing a secret key', async () => {
  const calls = [];
  const client = createClient({ url: 'https://example.supabase.co', publishableKey: 'publishable', storage: storage(), fetchImpl: async (url, options) => { calls.push({ url, options }); return response(200, {}); } });
  await client.requestEmailLink('TAYLOR@example.com', false, 'https://example.com/return');
  assert.strictEqual(calls[0].url, 'https://example.supabase.co/auth/v1/otp?redirect_to=https%3A%2F%2Fexample.com%2Freturn');
  assert.deepStrictEqual(JSON.parse(calls[0].options.body), { email: 'taylor@example.com', create_user: false });
  assert.strictEqual(calls[0].options.headers.apikey, 'publishable');
  assert.strictEqual(calls[0].options.headers.Authorization, undefined);
});

test('signs the owner in directly with the saved password', async () => {
  let submitted = null;
  const client = createClient({ url: 'https://example.supabase.co', publishableKey: 'publishable', storage: storage(), fetchImpl: async (_url, options) => {
    submitted = JSON.parse(options.body);
    return response(200, { access_token: 'access', refresh_token: 'refresh', user: { id: 'owner-1' } });
  } });
  const session = await client.signInWithPassword('OWNER@example.com', 'saved-password');
  assert.deepStrictEqual(submitted, { email: 'owner@example.com', password: 'saved-password' });
  assert.strictEqual(session.user.id, 'owner-1');
});

test('consumes and removes an implicit magic-link session fragment', async () => {
  const store = storage();
  let replacedWith = '';
  const client = createClient({ url: 'https://example.supabase.co', publishableKey: 'publishable', storage: store, fetchImpl: async () => response(200, { id: 'owner-1', email: 'owner@example.com' }) });
  const session = await client.consumeAuthRedirect(
    { hash: '#access_token=access&refresh_token=refresh&expires_in=3600', pathname: '/app/', search: '' },
    { replaceState: (_state, _title, path) => { replacedWith = path; } }
  );
  assert.strictEqual(session.user.id, 'owner-1');
  assert.strictEqual(replacedWith, '/app/');
  assert.strictEqual(client.readSession().access_token, 'access');
});

test('verifies and stores an expiring owner session', async () => {
  const store = storage();
  const client = createClient({ url: 'https://example.supabase.co', publishableKey: 'publishable', storage: store, fetchImpl: async () => response(200, { access_token: 'access', refresh_token: 'refresh', expires_in: 3600, user: { id: 'owner-1', email: 'taylor@example.com' } }) });
  const session = await client.verifyEmailCode('taylor@example.com', '12345678');
  assert.strictEqual(session.user.id, 'owner-1');
  assert.ok(session.expires_at > Math.floor(Date.now() / 1000));
  assert.strictEqual(client.readSession().access_token, 'access');
});

test('reads the owner document with the signed-in token', async () => {
  let authorization = '';
  const client = createClient({ url: 'https://example.supabase.co', publishableKey: 'publishable', storage: storage(), fetchImpl: async (_url, options) => { authorization = options.headers.Authorization; return response(200, [{ owner_id: 'owner-1', revision: 2, document: { notes: [] } }]); } });
  const row = await client.fetchRoutine({ access_token: 'access', user: { id: 'owner-1' } });
  assert.strictEqual(row.revision, 2);
  assert.strictEqual(authorization, 'Bearer access');
});

test('deletes only the signed-in owner document', async () => {
  let requestUrl = '';
  let requestOptions = null;
  const client = createClient({ url: 'https://example.supabase.co', publishableKey: 'publishable', storage: storage(), fetchImpl: async (url, options) => {
    requestUrl = url;
    requestOptions = options;
    return response(204, null);
  } });
  await client.deleteRoutine({ access_token: 'access', user: { id: 'owner-1' } });
  assert.ok(requestUrl.endsWith('/rest/v1/routine_documents?owner_id=eq.owner-1'));
  assert.strictEqual(requestOptions.method, 'DELETE');
  assert.strictEqual(requestOptions.headers.Authorization, 'Bearer access');
  assert.strictEqual(requestOptions.headers.Prefer, 'return=minimal');
});

test('updates only the expected revision', async () => {
  let requestUrl = '';
  const client = createClient({ url: 'https://example.supabase.co', publishableKey: 'publishable', storage: storage(), fetchImpl: async (url) => { requestUrl = url; return response(200, [{ revision: 4 }]); } });
  const row = await client.pushRoutine({ session: { access_token: 'access', user: { id: 'owner-1' } }, document: { notes: [] }, expectedRevision: 3, deviceId: 'device-1' });
  assert.strictEqual(row.revision, 4);
  assert.ok(requestUrl.includes('owner_id=eq.owner-1'));
  assert.ok(requestUrl.includes('revision=eq.3'));
});

test('reports an optimistic revision conflict when no row updates', async () => {
  const client = createClient({ url: 'https://example.supabase.co', publishableKey: 'publishable', storage: storage(), fetchImpl: async () => response(200, []) });
  await assert.rejects(
    () => client.pushRoutine({ session: { access_token: 'access', user: { id: 'owner-1' } }, document: {}, expectedRevision: 2, deviceId: 'device-1' }),
    error => error instanceof CloudConflictError
  );
});

(async () => {
  for (const { name, run } of tests) {
    try { await run(); }
    catch (error) { error.message = `${name}: ${error.message}`; throw error; }
  }
  console.log(`Private sync cloud transport: ${tests.length} tests passed.`);
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
