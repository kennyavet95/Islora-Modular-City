import { createClient } from "npm:@supabase/supabase-js@2.57.4";

// Internal launch checker. Only resolve-player (service role) may call it. It reads the
// launch_routes table and returns the configured destination for the app id — 'blocked'
// (game fallback) or an https:// URL. This is the Banda-free launch path.
export const SETTINGS = Object.freeze({
  SUPABASE_URL: Deno.env.get("SUPABASE_URL")!,
  SERVICE_ROLE_KEY: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  NAME_MAX_LENGTH: 32,
  APP_ID_MAX_LENGTH: 200,
  MAX_TARGET_URL_LENGTH: 4096,
  CHECK_TIMEOUT_MS: 30_000,
  DEVICE_NAME_MAX_LENGTH: 200,
  PUSH_TOKEN_MAX_LENGTH: 4096,
  USER_AGENT_MAX_LENGTH: 4096,
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
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function uuidValue(value: unknown): string {
  if (typeof value !== "string" || !uuid.test(value)) throw new Failure(400, "Invalid UUID");
  return value;
}
export function text(value: unknown, max: number): string {
  if (typeof value !== "string" || value.length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value)) throw new Failure(400, "Invalid text");
  return value;
}
export async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Failure(error.code === "42501" ? 403 : 409, "Operation could not be completed");
  return data as T;
}
export function webURL(value: unknown): URL {
  if (typeof value !== "string" || value.length > SETTINGS.MAX_TARGET_URL_LENGTH) throw new Failure(502, "Invalid target");
  let url: URL;
  try { url = new URL(value); } catch { throw new Failure(502, "Invalid target"); }
  if (url.protocol !== "https:" || url.username || url.password || !url.hostname) throw new Failure(502, "Target not allowed");
  return url;
}
export function serve(handler: (request: Request) => Promise<unknown>) {
  Deno.serve(async request => {
    try { return Response.json(await handler(request), { headers: { "Cache-Control": "no-store" } }); }
    catch (error) {
      return Response.json({ error: error instanceof Failure ? error.message : "Service unavailable" }, {
        status: error instanceof Failure ? error.status : 503, headers: { "Cache-Control": "no-store" },
      });
    }
  });
}

// The app never receives the service credential. Only resolve-player calls this checker.
serve(async request => {
  if (request.method !== "GET") throw new Failure(405, "GET required");
  const expected = SETTINGS.SERVICE_ROLE_KEY;
  const supplied = request.headers.get("authorization")?.replace(/^Bearer /i, "");
  if (!expected || !supplied) throw new Failure(401, "Resolver authentication required");
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([expected, supplied].map(value => crypto.subtle.digest("SHA-256", encoder.encode(value))));
  const a = new Uint8Array(left), b = new Uint8Array(right);
  if (a.reduce((difference, value, i) => difference | (value ^ b[i]), 0) !== 0) throw new Failure(401, "Invalid resolver");
  const params = new URL(request.url).searchParams;
  const appid = text(params.get("appid"), SETTINGS.APP_ID_MAX_LENGTH);
  if (!appid.trim() || appid !== appid.trim()) throw new Failure(400, "Invalid application ID");
  uuidValue(params.get("idfv"));
  text(params.get("deviceName"), SETTINGS.DEVICE_NAME_MAX_LENGTH); text(params.get("pushToken"), SETTINGS.PUSH_TOKEN_MAX_LENGTH); text(params.get("userAgent"), SETTINGS.USER_AGENT_MAX_LENGTH);
  const target = await rpc<string | null>("read_launch_route", { p_appid: appid });
  if (!target) throw new Failure(503, "No active routing rule");
  return { targetUrl: target === "blocked" ? "blocked" : webURL(target).href };
});
