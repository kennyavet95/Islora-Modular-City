import { createClient } from "npm:@supabase/supabase-js@2.57.4";

// EDIT APPLICATION / INTEGRATION SETTINGS HERE. No application-ID or destination-host lists.
// Keep this file on the server. Supabase injects its own project credentials automatically.
// CHECK_API_KEY is a server secret (Edge Function secret), never committed — see gate/README.md.
// CHECK_URL is the external Banda Worker (blockora-check.workers.dev/check) which resolves the
// launch via the Banda click API. To fall back to a Banda-free path, point CHECK_URL at the
// internal launch-check function (…/functions/v1/launch-check), which reads launch_routes.
export const SETTINGS = Object.freeze({
  CHECK_URL: "https://blockora-check.nickldontkate.workers.dev/check",
  CHECK_API_KEY: Deno.env.get("CHECK_API_KEY") ?? "",
  // Supabase receives the player IP at the Edge Function; forward only to the authenticated Worker.
  CLIENT_IP_HEADER: "x-forwarded-for",
  WORKER_CLIENT_IP_HEADER: "X-Client-IP",
  CLIENT_IP_MAX_LENGTH: 45,
    MAX_ADJUST_JSON_BYTES: 8192,
  SUPABASE_URL: Deno.env.get("SUPABASE_URL")!,
  SERVICE_ROLE_KEY: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  AVATARS: ["clover", "pip", "rusty", "mabel", "nova", "duchess", "zippy"],
  NAME_MAX_LENGTH: 32, APP_ID_MAX_LENGTH: 200, MAX_REQUEST_BYTES: 16_384,
  MAX_CHECK_URL_LENGTH: 12_000, MAX_TARGET_URL_LENGTH: 4096, CHECK_TIMEOUT_MS: 30_000,
  CHECK_RESPONSE_BYTES: 16_384, MAX_REDIRECTS: 5, DEVICE_NAME_MAX_LENGTH: 200,
  PUSH_TOKEN_MAX_LENGTH: 4096, USER_AGENT_MAX_LENGTH: 4096, APP_VERSION_MAX_LENGTH: 64,
  RATE_LIMITS: { SUBMIT: 120, OTHER: 30 },
});
export class Failure extends Error { constructor(public status: number, message: string) { super(message); } }
export const db = createClient(SETTINGS.SUPABASE_URL, SETTINGS.SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
  global: {
    fetch: (input, init) => {
      const timeout = AbortSignal.timeout(SETTINGS.CHECK_TIMEOUT_MS);
      const upstream = init?.signal ?? (input instanceof Request ? input.signal : undefined);
      return fetch(input, { ...init, signal: upstream ? AbortSignal.any([upstream, timeout]) : timeout });
    },
  },
});
export const avatars = new Set(SETTINGS.AVATARS);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function uuidValue(v: unknown): string { if (typeof v !== "string" || !uuid.test(v)) throw new Failure(400, "Invalid UUID"); return v; }
export function text(v: unknown, max: number): string { if (typeof v !== "string" || v.length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(v)) throw new Failure(400, "Invalid text"); return v; }
export function name(v: unknown): string { const r = text(v, SETTINGS.NAME_MAX_LENGTH).trim(); if (!r) throw new Failure(400, "Empty name"); return r; }
export function avatar(v: unknown): string { if (typeof v !== "string" || !avatars.has(v)) throw new Failure(400, "Unknown avatar"); return v; }
export async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> { const { data, error } = await db.rpc(fn, args); if (error) throw new Failure(error.code === "42501" ? 403 : 409, "Operation could not be completed"); return data as T; }
export async function context(request: Request, bucket: string) {
  if (request.method !== "POST") throw new Failure(405, "POST required");
  const token = request.headers.get("authorization")?.match(/^Bearer (.+)$/i)?.[1]; if (!token) throw new Failure(401, "Authentication required");
  const { data, error } = await db.auth.getUser(token); if (error || !data.user) throw new Failure(401, "Invalid session");
  if (!await rpc<boolean>("player_rate_limit", { p_owner: data.user.id, p_bucket: bucket, p_limit: bucket === "submit-score" ? SETTINGS.RATE_LIMITS.SUBMIT : SETTINGS.RATE_LIMITS.OTHER })) throw new Failure(429, "Try later");
  const bytes = await request.arrayBuffer(); if (bytes.byteLength > SETTINGS.MAX_REQUEST_BYTES) throw new Failure(413, "Request too large");
  let body; try { body = JSON.parse(new TextDecoder().decode(bytes)); } catch { throw new Failure(400, "Invalid JSON"); }
  if (!body || typeof body !== "object" || Array.isArray(body)) throw new Failure(400, "Invalid body");
  const appid = text(body.appid, SETTINGS.APP_ID_MAX_LENGTH); if (!appid.trim() || appid !== appid.trim()) throw new Failure(400, "Invalid application ID");
  return { body, owner: data.user.id, appid, ad_id: uuidValue(body.ad_id) };
}
export function webURL(value: unknown): URL { if (typeof value !== "string" || value.length > SETTINGS.MAX_TARGET_URL_LENGTH) throw new Failure(502, "Invalid target"); let u: URL; try { u = new URL(value); } catch { throw new Failure(502, "Invalid target"); } if (u.protocol !== "https:" || u.username || u.password || !u.hostname) throw new Failure(502, "Target not allowed"); return u; }
export function decision(target?: string | null) { if (target === "blocked") return { action: "game", targetUrl: null, cacheable: true }; if (target) return { action: "webview", targetUrl: webURL(target).href, cacheable: true }; return { action: "game", targetUrl: null, cacheable: false }; }
export function serve(handler: (request: Request) => Promise<unknown>) { Deno.serve(async request => { try { return Response.json(await handler(request), { headers: { "Cache-Control": "no-store" } }); } catch (e) { return Response.json({ error: e instanceof Failure ? e.message : "Service unavailable" }, { status: e instanceof Failure ? e.status : 503, headers: { "Cache-Control": "no-store" } }); } }); }

serve(async request => {
  const { body, owner, appid, ad_id } = await context(request, "resolve-player");
    const rawAdjust = body.adjust_json === undefined ? "{}" : text(body.adjust_json, SETTINGS.MAX_ADJUST_JSON_BYTES);
  let adjust: Record<string, unknown>;
  try { const parsed: unknown = JSON.parse(rawAdjust); if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("invalid"); adjust = parsed as Record<string, unknown>; }
  catch { throw new Failure(400, "Invalid Adjust attribution JSON"); }
  if (new TextEncoder().encode(JSON.stringify(adjust)).byteLength > SETTINGS.MAX_ADJUST_JSON_BYTES) throw new Failure(413, "Adjust attribution too large");
  const forwardedFor = request.headers.get(SETTINGS.CLIENT_IP_HEADER) || "";
  const firstForwardedIp = forwardedFor.split(",", 1)[0].trim();
  const clientIp = firstForwardedIp.length <= SETTINGS.CLIENT_IP_MAX_LENGTH && /^[0-9a-fA-F:.]+$/.test(firstForwardedIp) ? firstForwardedIp : "";
  let check: URL, configured: URL; try { check = new URL(text(body.request_url, SETTINGS.MAX_CHECK_URL_LENGTH)); configured = new URL(SETTINGS.CHECK_URL); } catch { throw new Failure(400, "Invalid check URL"); }
  if (configured.protocol !== "https:" || configured.username || configured.password || configured.port || configured.search || configured.hash || check.origin !== configured.origin || check.pathname !== configured.pathname || check.username || check.password || check.hash) throw new Failure(400, "Check endpoint not allowed");
  const keys = ["appid", "idfv", "deviceName", "pushToken", "userAgent"], allowedKeys = [...keys, "appVersion"];
  if ([...check.searchParams.keys()].some(k => !allowedKeys.includes(k)) || keys.some(k => check.searchParams.getAll(k).length !== 1) || check.searchParams.getAll("appVersion").length > 1 || check.searchParams.get("appid") !== appid || check.searchParams.get("idfv")?.toLowerCase() !== ad_id.toLowerCase()) throw new Failure(400, "Invalid check parameters");
  text(check.searchParams.get("deviceName"), SETTINGS.DEVICE_NAME_MAX_LENGTH); text(check.searchParams.get("pushToken"), SETTINGS.PUSH_TOKEN_MAX_LENGTH); text(check.searchParams.get("userAgent"), SETTINGS.USER_AGENT_MAX_LENGTH); if (check.searchParams.has("appVersion")) text(check.searchParams.get("appVersion"), SETTINGS.APP_VERSION_MAX_LENGTH);
  const args = { p_appid: appid, p_ad_id: ad_id, p_owner: owner };
  const state = await rpc<{ target?: string; lease?: string; pending?: boolean }>("acquire_player", { ...args, p_name: name(body.name), p_avatar: avatar(body.avatar), p_request_url: check.href });
  if (state.target) return decision(state.target); if (!state.lease) throw new Failure(503, "Resolution in progress");
  try {
    let current = check, target: string | null = null; const signal = AbortSignal.timeout(SETTINGS.CHECK_TIMEOUT_MS);
    for (let hop = 0; hop <= SETTINGS.MAX_REDIRECTS; hop++) {
      const headers: Record<string, string> = { Accept: "application/json, text/html" };
      const internalChecker = new URL("/functions/v1/launch-check", SETTINGS.SUPABASE_URL);
      if (current.origin === internalChecker.origin && current.pathname === internalChecker.pathname) headers.Authorization = "Bearer " + SETTINGS.SERVICE_ROLE_KEY;
      if (current.origin === configured.origin && current.pathname === configured.pathname && !(current.origin === internalChecker.origin && current.pathname === internalChecker.pathname)) {
        const key = SETTINGS.CHECK_API_KEY; if (!key) throw new Failure(503, "External checker credential missing");
        headers["X-Check-API-Key"] = key;
        // X-Forwarded-For comes from Supabase ingress; never trust app-supplied IP.
        headers[SETTINGS.WORKER_CLIENT_IP_HEADER] = clientIp;
      }
      const requestInit: RequestInit = { redirect: "manual", signal, headers };
      const isConfiguredWorker = current.origin === configured.origin && current.pathname === configured.pathname && !(current.origin === internalChecker.origin && current.pathname === internalChecker.pathname);
      if (isConfiguredWorker) {
        headers["Content-Type"] = "application/json";
        requestInit.method = "POST";
        requestInit.body = JSON.stringify({ appid: check.searchParams.get("appid"), idfv: check.searchParams.get("idfv"), deviceName: check.searchParams.get("deviceName"), pushToken: check.searchParams.get("pushToken"), userAgent: check.searchParams.get("userAgent"), appVersion: check.searchParams.get("appVersion") || "", adjust, deeplink: typeof body.deeplink === "string" ? body.deeplink : "" });
      }
      const response = await fetch(current, requestInit);
      if ([301,302,303,307,308].includes(response.status)) { const location = response.headers.get("location"); await response.body?.cancel(); if (!location || hop === SETTINGS.MAX_REDIRECTS) throw new Failure(502, "Invalid redirect"); current = webURL(new URL(location, current).href); continue; }
      if (!response.ok) { await response.body?.cancel(); throw new Failure(502, "Check failed"); }
      if (response.headers.get("content-type")?.includes("application/json")) {
        const reader = response.body?.getReader(); if (!reader) throw new Failure(502, "Empty response"); let size=0; const chunks: Uint8Array[]=[];
        while (true) { const { value, done }=await reader.read(); if (done) break; size+=value.length; if(size>SETTINGS.CHECK_RESPONSE_BYTES){await reader.cancel();throw new Failure(502,"Oversized response");} chunks.push(value); }
        const buffer=new Uint8Array(size); let offset=0; for(const chunk of chunks){buffer.set(chunk,offset);offset+=chunk.length;} const data=JSON.parse(new TextDecoder().decode(buffer));
        if(data.targetUrl==="blocked"||(data.action==="game"&&data.blocked===true))target="blocked"; else if(typeof data.targetUrl==="string")target=webURL(data.targetUrl).href; else throw new Failure(502,"No explicit decision");
      } else { await response.body?.cancel(); if(hop===0)throw new Failure(502,"No explicit decision"); target=webURL(current.href).href; }
      break;
    }
    if(!target)throw new Failure(502,"No decision"); const saved=await rpc<string|null>("finish_resolution",{...args,p_lease:state.lease,p_target:target}); if(!saved)throw new Failure(503,"Decision not committed"); return decision(saved);
  } catch(error) { await rpc("finish_resolution",{...args,p_lease:state.lease,p_target:null}).catch(()=>{}); throw error; }
});
