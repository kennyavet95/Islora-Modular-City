// EDIT PER-APP / INTEGRATION SETTINGS HERE. All app IDs and HTTPS destinations are accepted.
// Server-only file: never ship these credentials in the iOS app.
// CHECK_API_KEY and BANDA_CLICK_TOKEN are Cloudflare secrets (env), never committed here.
const SETTINGS = Object.freeze({
  WEBSITE_SUPPORT_EMAIL: 'kennyavet95@icloud.com',
  BANDA_CLICK_URL: 'https://banda-track-api.space/api/click-ios',
  // Banda documents 202 + empty body as a completed blocked click; stop retries.
  BANDA_202_IS_PERMANENT_BLOCK: true,
  CLIENT_IP_HEADER: 'X-Client-IP',
  CLIENT_IP_MAX_LENGTH: 45,
  UPSTREAM_TIMEOUT_MS: 30_000,
  MAX_RESPONSE_BYTES: 16384,
  MAX_CHECK_REQUEST_BYTES: 16384,
  MAX_ADJUST_JSON_BYTES: 8192,
  MAX_DEEPLINK_LENGTH: 4096,
  MAX_TARGET_URL_LENGTH: 4096,
  PARAMETER_LIMITS: [200, 36, 200, 4096, 4096, 64],
});
const utf8 = new TextEncoder();
class Failure extends Error { constructor(status, code) { super(code); this.status = status; } }
const json = (body, status = 200) => Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
function destination(value, env) {
  if (typeof value !== 'string' || !value || value.length > SETTINGS.MAX_TARGET_URL_LENGTH || value !== value.trim()) throw new Failure(502, 'invalid_destination');
  let url; try { url = new URL(value); } catch { throw new Failure(502, 'invalid_destination'); }
  if (url.protocol !== 'https:' || url.username || url.password || !url.hostname) throw new Failure(502, 'destination_not_allowed');
  return url.href;
}
async function readBody(response) {
  const reader = response.body?.getReader();
  if (!reader) throw new Failure(502, 'empty_response');
  const chunks = []; let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.length;
      if (size > SETTINGS.MAX_RESPONSE_BYTES) { await reader.cancel(); throw new Failure(502, 'oversized_response'); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } finally { reader.releaseLock(); }
}
async function check(request, env) {
  if (request.method !== 'POST') throw new Failure(405, 'post_required');
  const checkApiKey = env.CHECK_API_KEY;
  if (!checkApiKey) throw new Failure(503, 'check_not_configured');
  const supplied = request.headers.get('X-Check-API-Key') || '';
  const hashes = await Promise.all([checkApiKey, supplied].map(v => crypto.subtle.digest('SHA-256', utf8.encode(v))));
  const a = new Uint8Array(hashes[0]), b = new Uint8Array(hashes[1]);
  if (a.reduce((diff, value, i) => diff | (value ^ b[i]), 0)) throw new Failure(401, 'unauthorized');
  const requestBytes = await request.arrayBuffer();
  if (requestBytes.byteLength > SETTINGS.MAX_CHECK_REQUEST_BYTES) throw new Failure(413, 'request_too_large');
  let params;
  try { params = JSON.parse(new TextDecoder().decode(requestBytes)); } catch { throw new Failure(400, 'invalid_json'); }
  if (!params || typeof params !== 'object' || Array.isArray(params)) throw new Failure(400, 'invalid_parameters');
  const keys = ['appid', 'idfv', 'deviceName', 'pushToken', 'userAgent'];
  const allowedKeys = [...keys, 'appVersion', 'adjust', 'deeplink'];
  if (Object.keys(params).some(k => !allowedKeys.includes(k)) || keys.some(k => typeof params[k] !== 'string') || (params.appVersion !== undefined && typeof params.appVersion !== 'string') || (params.deeplink !== undefined && typeof params.deeplink !== 'string')) throw new Failure(400, 'invalid_parameters');
  const values = [...keys.map(k => params[k]), params.appVersion || ''], limits = SETTINGS.PARAMETER_LIMITS;
  if (values.some((v, i) => v.length > limits[i] || /[\u0000-\u001f\u007f]/.test(v))) throw new Failure(400, 'invalid_parameters');
  const [appid, idfv, deviceName, pushToken, userAgent, appVersion] = values;
  const adjust = params.adjust === undefined ? {} : params.adjust;
  if (!adjust || typeof adjust !== 'object' || Array.isArray(adjust) || new TextEncoder().encode(JSON.stringify(adjust)).byteLength > SETTINGS.MAX_ADJUST_JSON_BYTES) throw new Failure(400, 'invalid_adjust_attribution');
  const deeplink = params.deeplink || '';
  if (deeplink.length > SETTINGS.MAX_DEEPLINK_LENGTH || /[\u0000-\u001f\u007f]/.test(deeplink)) throw new Failure(400, 'invalid_parameters');
  const rawClientIp = (request.headers.get(SETTINGS.CLIENT_IP_HEADER) || '').trim();
  const clientIp = rawClientIp.length <= SETTINGS.CLIENT_IP_MAX_LENGTH && /^[0-9a-fA-F:.]+$/.test(rawClientIp) ? rawClientIp : '';
  const bandaClickToken = env.BANDA_CLICK_TOKEN;
  if (!bandaClickToken) throw new Failure(503, 'upstream_not_configured');
  const controller = new AbortController(), timer = setTimeout(() => controller.abort(), SETTINGS.UPSTREAM_TIMEOUT_MS);
  const requestId = crypto.randomUUID();
  const startedAt = Date.now();
  try {
    const response = await fetch(SETTINGS.BANDA_CLICK_URL, {
      method: 'POST', redirect: 'manual', signal: controller.signal,
      headers: { 'Content-Type': 'application/json', Accept: 'text/plain,application/json', 'X-Click-Token': bandaClickToken,
        'X-Config-Request-Id': requestId, 'Idempotency-Key': requestId },
      // Banda's iOS contract uses idfv explicitly. IDFA is unavailable in this client,
      // so send it blank; never substitute IDFV for IDFA or send the server IP as player IP.
      body: JSON.stringify({ appId: appid, idfv, idfa: '', ip: clientIp, pushToken, userAgent, deviceName, appVersion, naming: JSON.stringify(adjust), deeplink, adjust })
    });
    if (response.status === 202) {
      await response.body?.cancel();
      console.warn('Banda click request pending', JSON.stringify({ requestId, status: response.status, clientIpForwarded: !!clientIp, elapsedMs: Date.now() - startedAt }));
      if (SETTINGS.BANDA_202_IS_PERMANENT_BLOCK) return json({ targetUrl: 'blocked' });
      throw new Failure(503, 'upstream_pending');
    }
    if (!response.ok) {
      const contentType = response.headers.get('content-type') || '';
      const responseLength = Number(response.headers.get('content-length')) || null;
      await response.body?.cancel();
      console.error('Banda click request rejected', JSON.stringify({ requestId, status: response.status, contentType, responseLength, elapsedMs: Date.now() - startedAt }));
      throw new Failure(502, 'upstream_unavailable');
    }
    console.info('Banda click request accepted', JSON.stringify({ requestId, status: response.status, clientIpForwarded: !!clientIp, elapsedMs: Date.now() - startedAt }));
    let payload = (await readBody(response)).trim();
    try { payload = JSON.parse(payload); } catch {}
    if (typeof payload === 'string') return json({ targetUrl: destination(payload, env) });
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw new Failure(502, 'invalid_response');
    const type = payload.type ?? (payload.status === 'policy' ? 'policy' : 'offer');
    if (type === 'policy') return json({ targetUrl: 'blocked' });
    if (type !== 'offer') throw new Failure(502, 'invalid_response');
    return json({ targetUrl: destination(payload.url, env) });
  } catch (error) {
    if (controller.signal.aborted) {
      console.error('Banda click request timed out', JSON.stringify({ requestId, elapsedMs: Date.now() - startedAt }));
      throw new Failure(504, 'upstream_timeout');
    }
    if (error instanceof Failure) console.error('Banda click response could not be accepted', JSON.stringify({ requestId, reason: error.message, elapsedMs: Date.now() - startedAt }));
    else console.error('Banda click response could not be processed', JSON.stringify({ requestId, errorType: error?.name || 'Error', elapsedMs: Date.now() - startedAt }));
    throw error;
  } finally { clearTimeout(timer); }
}
export default {
  async fetch(request, env) {
    try {
      const path = new URL(request.url).pathname;
      if (path === '/check') return await check(request, env);
      if (path === '/health' && request.method === 'GET') {
        const ready = !!(env.CHECK_API_KEY && env.BANDA_CLICK_TOKEN);
        return json({ status: ready ? 'ok' : 'not_configured' }, ready ? 200 : 503);
      }
      if (env.ASSETS) {
        const response = await env.ASSETS.fetch(request);
        if (request.method === 'GET' && response.headers.get('content-type')?.includes('text/html')) {
          const html = (await response.text()).replaceAll('support@featherfreeway.example', SETTINGS.WEBSITE_SUPPORT_EMAIL);
          const headers = new Headers(response.headers);
          headers.delete('content-length');
          headers.delete('etag');
          return new Response(html, { status: response.status, statusText: response.statusText, headers });
        }
        return response;
      }
      return new Response('Not found', { status: 404 });
    } catch (error) { return json({ error: error instanceof Failure ? error.message : 'internal_error' }, error instanceof Failure ? error.status : 503); }
  },
};
