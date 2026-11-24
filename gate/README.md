# Launch gate backend (Islora: Modular City)

The canon launch gate for `com.isloragames.islora`, integrated from `IOS_Config` (FeatherFreeway
template). The iOS app resolves its launch route on cold start; Supabase decides, and either the
main WKWebView opens an HTTPS destination or the app falls back to the game.

```
iOS app ──POST resolve-player──▶ Supabase Edge ──▶ checker ──▶ decision ──▶ webview | game
                                   │                 │
                                   │                 ├─ launch-check (internal, reads launch_routes)   ← Banda-free
                                   │                 └─ blockora-check Worker (/check) ──▶ Banda click  ← production
                                   └─ public.leaderboard (Top Players), player profile, submit-score
```

## Supabase project (this app)
- Project ref: `yejxhqnjwtzoxiqsfrrs`  ·  URL: `https://yejxhqnjwtzoxiqsfrrs.supabase.co`
- Org: `nickldontkate@gmail.com's Org`
- Anonymous sign-ins: enabled (the app signs up anonymously, keeps the session in Keychain).
- Migrations: `supabase/migrations/` (players + public.leaderboard + launch_routes + rate limits).
- Functions: `resolve-player`, `launch-check`, `player-profile`, `submit-score` (all `verify_jwt=false`;
  each validates the bearer with `auth.getUser`).
- Launch route seed: `launch_routes(com.isloragames.islora) = 'blocked'` → game fallback until a real
  destination is set.

### Switching between the Banda-free and production checker
- `resolve-player` `SETTINGS.CHECK_URL` currently points at the **internal** `launch-check`
  (`…/functions/v1/launch-check`) so the gate works with **no Banda token** (always resolves to the
  route in `launch_routes`).
- To enable Banda routing, deploy the Worker (below), set `CHECK_URL` to `https://blockora6.xyz/check`,
  redeploy `resolve-player`, and point the iOS `OnlineConfiguration.checkURL` at the same URL.

## Cloudflare Worker `blockora-check` (production checker)
- Zone `blockora6.xyz` (account `Nickldontkate@gmail.com's Account`).
- Secrets (never committed; `wrangler secret put` or the API):
  - `CHECK_API_KEY` — shared with `resolve-player` (Supabase Edge secret of the same name).
  - `BANDA_CLICK_TOKEN` — per-app Banda click token (from the ticket owner).
- `BANDA_CLICK_URL` = `https://banda-track-api.space/api/click-ios`.

## Secrets (NOT in this repo)
| Secret | Where it lives | Notes |
|---|---|---|
| `CHECK_API_KEY` | Supabase Edge secret + Cloudflare secret | Generated per environment; must match on both. |
| `BANDA_CLICK_TOKEN` | Cloudflare secret only | Per-app Banda token. |
| Supabase `service_role` / `sb_secret` | Supabase runtime | Never sent to the client. |

The iOS client only ever holds the **publishable** Supabase key and the public `checkURL`.
